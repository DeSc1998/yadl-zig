const std = @import("std");
const stmt = @import("statement.zig");
const expr = @import("expression.zig");
const stdlib = @import("stdlib.zig");

const Expression = expr.Expression;
const Statement = stmt.Statement;

const Bindings = std.StringHashMap(*Expression);
const Functions = std.StringHashMap(expr.Function);

const Scope = @This();

pub const Error = std.mem.Allocator.Error || error{
    NotImplemented,
};

allocator: std.mem.Allocator,
out: std.io.AnyWriter,
parent: ?*Scope = null,
locals: Bindings,
functions: Functions,
return_result: ?*Expression = null,

pub fn empty(alloc: std.mem.Allocator, out: std.io.AnyWriter) Scope {
    return .{
        .allocator = alloc,
        .out = out,
        .locals = Bindings.init(alloc),
        .functions = Functions.init(alloc),
    };
}

pub fn init(alloc: std.mem.Allocator, out: std.io.AnyWriter, parent: *Scope, vars: []const expr.Identifier, exprs: []Expression) !Scope {
    var tmp: Scope = .{
        .allocator = alloc,
        .out = out,
        .parent = parent,
        .locals = Bindings.init(alloc),
        .functions = Functions.init(alloc),
    };
    for (vars, exprs) |v, *e| {
        try tmp.locals.put(v.name, e);
    }
    return tmp;
}

pub fn hasResult(self: Scope) bool {
    return if (self.return_result) |_| true else false;
}

pub fn result(self: *Scope) ?Expression {
    if (self.return_result) |res| {
        self.return_result = null;
        return res.*;
    } else return null;
}

pub fn result_ref(self: *Scope) ?*Expression {
    if (self.return_result) |res| {
        self.return_result = null;
        return res;
    } else return null;
}

pub fn isGlobal(self: Scope) bool {
    return if (self.parent) |_| false else true;
}

pub fn lookup(self: Scope, ident: expr.Identifier) Error!?*Expression {
    if (self.locals.get(ident.name)) |ex| {
        if (ex.* == .identifier and !std.mem.eql(u8, ex.identifier.name, ident.name)) {
            return ex;
        } else if (ex.* != .identifier) {
            return ex;
        } else {
            return self.lookupInParent(ident);
        }
    } else {
        return try self.lookupInParent(ident) orelse b: {
            const f = self.lookupFunction(ident) orelse break :b null;
            const out = try self.allocator.create(Expression);
            out.* = .{ .function = f };
            break :b out;
        };
    }
}

pub fn lookupFunction(self: Scope, ident: expr.Identifier) ?expr.Function {
    if (self.functions.get(ident.name)) |func| {
        return func;
    } else {
        return self.lookupFunctionInParent(ident);
    }
}

fn lookupInParent(self: Scope, ident: expr.Identifier) Error!?*Expression {
    if (self.parent) |p| {
        return try p.lookup(ident);
    } else return null;
}

fn lookupFunctionInParent(self: Scope, ident: expr.Identifier) ?expr.Function {
    if (self.parent) |p| {
        if (p.functions.get(ident.name)) |func| {
            return func;
        } else {
            return p.lookupFunctionInParent(ident);
        }
    } else return null;
}

pub fn update(self: *Scope, ident: expr.Identifier, value: *Expression) Error!void {
    if (value.* == .function) {
        if (self.functions.get(ident.name)) |_| {
            const new_body = try self.captureExternals(value.function.args, value.function.body);
            const new_fn = .{
                .args = value.function.args,
                .body = new_body,
            };
            try self.functions.put(ident.name, new_fn);
        } else {
            try self.functions.put(ident.name, value.function);
        }
    } else {
        try self.locals.put(ident.name, value);
    }
}

pub fn captureExternals(scope: *Scope, fn_args: []const expr.Identifier, fn_body: []const Statement) Error![]Statement {
    var bound = std.ArrayList([]const u8).init(scope.allocator);
    const new_body = try scope.allocator.alloc(Statement, fn_body.len);
    for (fn_args) |arg| {
        try bound.append(arg.name);
    }
    try bound.append("print");
    const keys = stdlib.builtins.keys();
    for (keys) |key| {
        try bound.append(key);
    }

    for (fn_body, new_body) |st, *new_st| {
        new_st.* = try captureFromStatement(st, &bound, scope);
    }
    return new_body;
}

fn captureFromStatement(statement: Statement, bound: *std.ArrayList([]const u8), scope: *Scope) Error!Statement {
    return switch (statement) {
        .assignment => |a| b: {
            for (bound.items) |item| {
                if (std.mem.eql(u8, item, a.varName.name)) {
                    break :b statement;
                }
            }
            const new_value = try captureFromValue(a.value, bound, scope);
            try bound.append(a.varName.name);
            break :b .{ .assignment = .{
                .varName = a.varName,
                .value = new_value,
            } };
        },
        .functioncall => |fc| b: {
            const func = try captureFromValue(fc.func, bound, scope);
            const new_args = try scope.allocator.alloc(Expression, fc.args.len);
            for (fc.args, new_args) |*st, *new_st| {
                const tmp = try captureFromValue(st, bound, scope);
                new_st.* = tmp.*;
            }
            const out: Statement = .{ .functioncall = .{
                .func = func,
                .args = new_args,
            } };
            break :b out;
        },
        .@"return" => |r| b: {
            const ret_val = try captureFromValue(r.value, bound, scope);
            const out = .{ .@"return" = .{
                .value = ret_val,
            } };
            break :b out;
        },
        else => |s| s,
    };
}

fn captureFromValue(value: *const Expression, bound: *std.ArrayList([]const u8), scope: *Scope) Error!*Expression {
    return switch (value.*) {
        .wrapped => |e| captureFromValue(e, bound, scope),
        .identifier => |id| b: {
            for (bound.items) |item| {
                if (std.mem.eql(u8, item, id.name)) {
                    break :b value.clone(scope.allocator);
                }
            }
            if (try scope.lookup(id)) |out| {
                break :b out.clone(scope.allocator);
            } else {
                break :b value.clone(scope.allocator);
            }
        },
        .function => |f| b: {
            const new_body = try scope.allocator.alloc(Statement, f.body.len);
            for (f.body, new_body) |st, *new_st| {
                new_st.* = try captureFromStatement(st, bound, scope);
            }
            const out = try scope.allocator.create(Expression);
            out.* = .{ .function = .{
                .args = f.args,
                .body = new_body,
            } };
            break :b out;
        },
        .functioncall => |fc| b: {
            const func = try captureFromValue(fc.func, bound, scope);
            const new_args = try scope.allocator.alloc(Expression, fc.args.len);
            for (fc.args, new_args) |*st, *new_st| {
                const tmp = try captureFromValue(st, bound, scope);
                new_st.* = tmp.*;
            }
            const out = try scope.allocator.create(Expression);
            out.* = .{ .functioncall = .{
                .func = func,
                .args = new_args,
            } };
            break :b out;
        },
        else => value.clone(scope.allocator),
    };
}
