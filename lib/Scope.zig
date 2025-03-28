const std = @import("std");
const stmt = @import("statement.zig");
const expr = @import("expression.zig");
const stdlib = @import("stdlib.zig");

const Expression = expr.Expression;
const Statement = stmt.Statement;

const Bindings = std.StringHashMap(expr.Value);
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
return_result: ?expr.Value = null,

pub fn empty(alloc: std.mem.Allocator, out: std.io.AnyWriter) Scope {
    return .{
        .allocator = alloc,
        .out = out,
        .locals = Bindings.init(alloc),
        .functions = Functions.init(alloc),
    };
}

pub fn init(
    alloc: std.mem.Allocator,
    out: std.io.AnyWriter,
    parent: *Scope,
    vars: []const expr.Identifier,
    exprs: []Expression,
) !Scope {
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

pub fn fromCallMatch(
    alloc: std.mem.Allocator,
    out: std.io.AnyWriter,
    parent: *Scope,
    func_arity: expr.Function.Arity,
    call_match: stdlib.libtype.CallMatch,
) !Scope {
    var tmp: Scope = .{
        .allocator = alloc,
        .out = out,
        .parent = parent,
        .locals = Bindings.init(alloc),
        .functions = Functions.init(alloc),
    };
    for (func_arity.args, call_match.unnamed_args) |v, e| {
        try tmp.locals.put(v.name, e);
    }
    if (func_arity.var_args) |vars_id| {
        const tmp_vars = call_match.var_args.?;
        try tmp.locals.put(vars_id.name, .{ .array = tmp_vars });
    }

    return tmp;
}

pub fn hasResult(self: Scope) bool {
    return if (self.return_result) |_| true else false;
}

pub fn result(self: *Scope) ?expr.Value {
    if (self.return_result) |res| {
        defer self.return_result = null;
        return res;
    } else return null;
}

pub fn isGlobal(self: Scope) bool {
    return if (self.parent) |_| false else true;
}

pub fn lookup(self: Scope, ident: expr.Identifier) ?expr.Value {
    if (self.locals.get(ident.name)) |ex| {
        return ex;
    } else {
        return self.lookupInParent(ident) orelse b: {
            const f = self.lookupFunction(ident) orelse break :b null;
            break :b .{ .function = f };
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

fn lookupInParent(self: Scope, ident: expr.Identifier) ?expr.Value {
    if (self.parent) |p| {
        return p.lookup(ident);
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

pub fn update(self: *Scope, ident: expr.Identifier, value: expr.Value) Error!void {
    if (value == .function) {
        const f = value.function;
        if (self.functions.get(ident.name)) |_| {
            const new_body = try self.captureExternals(f.arity, f.body);
            const new_fn = expr.yadlValue.Function{
                .arity = f.arity,
                .body = new_body,
            };
            try self.functions.put(ident.name, new_fn);
        } else {
            try self.functions.put(ident.name, f);
        }
    } else {
        try self.locals.put(ident.name, value);
    }
}

pub fn captureExternals(scope: *Scope, fn_arity: expr.Function.Arity, fn_body: []const Statement) Error![]Statement {
    var bound = std.ArrayList([]const u8).init(scope.allocator);
    const new_body = try scope.allocator.alloc(Statement, fn_body.len);
    for (fn_arity.args) |arg| {
        try bound.append(arg.name);
    }
    for (fn_arity.optional_args) |arg| {
        try bound.append(arg.name);
    }

    if (fn_arity.var_args) |va|
        try bound.append(va.name);

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
            const out = Statement{ .@"return" = .{
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
        .value => |v| b: {
            if (v == .function) {
                const f = v.function;
                const new_body = try scope.allocator.alloc(Statement, f.body.len);
                for (f.body, new_body) |st, *new_st| {
                    new_st.* = try captureFromStatement(st, bound, scope);
                }
                break :b expr.initValue(scope.allocator, .{ .function = .{
                    .arity = f.arity,
                    .body = new_body,
                } });
            } else break :b value.clone(scope.allocator);
        },
        .identifier => |id| b: {
            for (bound.items) |item| {
                if (std.mem.eql(u8, item, id.name)) {
                    break :b value.clone(scope.allocator);
                }
            }
            if (scope.lookup(id)) |out| {
                break :b expr.initValue(scope.allocator, out);
            } else {
                break :b value.clone(scope.allocator);
            }
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
