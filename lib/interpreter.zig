const std = @import("std");
const Parser = @import("Parser.zig");
const stmt = @import("statement.zig");
const expr = @import("expression.zig");

const Scope = @import("Scope.zig");
const stdlib = @import("stdlib.zig");

const Expression = expr.Expression;
const Statement = stmt.Statement;

pub const Error = error{
    NotImplemented,
    FunctionNotFound,
    FormatNotSupportted,
    ValueNotFound,
    NoEntryForKey,
    IOWrite,
    InvalidExpressoinType,
    MalformedFormattedString,
    ArityMismatch,
} || Scope.Error;

pub fn evalStatement(statement: Statement, scope: *Scope) Error!void {
    if (scope.hasResult() and !scope.isGlobal()) {
        return;
    }

    switch (statement) {
        .assignment => |a| {
            try evalExpression(a.value, scope);
            try scope.update(a.varName, scope.result() orelse unreachable);
        },
        .functioncall => |fc| {
            var tmp = fc;
            try evalFunctionCall(&tmp, scope);
            scope.return_result = null;
        },
        .@"return" => |r| {
            try evalExpression(r.value, scope);
            const result = scope.result() orelse unreachable;
            scope.return_result = result;
        },
        .whileloop => |w| {
            var cond = false;
            try evalExpression(w.loop.condition, scope);
            var tmp = scope.result() orelse unreachable;
            cond = tmp == .boolean and tmp.boolean;
            while (cond) {
                for (w.loop.body) |st| {
                    try evalStatement(st, scope);
                }

                try evalExpression(w.loop.condition, scope);
                tmp = scope.result() orelse unreachable;
                cond = tmp == .boolean and tmp.boolean;
            }
        },
        .if_statement => |i| {
            try evalExpression(i.ifBranch.condition, scope);
            const tmp = scope.result() orelse unreachable;
            if (tmp == .boolean and tmp.boolean) {
                for (i.ifBranch.body) |st| {
                    try evalStatement(st, scope);
                }
            } else {
                if (i.elseBranch) |b| {
                    for (b) |st| {
                        try evalStatement(st, scope);
                    }
                }
            }
        },
        .struct_assignment => |sa| {
            try modify(sa.access, sa.value, scope);
        },
    }
}

fn modify(strct: *Expression, value: *Expression, scope: *Scope) Error!void {
    std.debug.assert(strct.* == .struct_access);
    try evalExpression(value, scope);
    const ex = scope.result() orelse unreachable;
    try evalExpression(strct.struct_access.strct, scope);
    const contianer = scope.result() orelse unreachable;
    try evalExpression(strct.struct_access.key, scope);
    const key = scope.result() orelse unreachable;

    switch (contianer) {
        .array => |a| {
            if (key != .number or key.number != .integer or key.number.integer >= a.len and key.number.integer < 0) {
                std.debug.print("ERROR: invalid expressoin type: {s}\n", .{@tagName(key)});
                return Error.InvalidExpressoinType;
            }
            const index = @as(usize, @intCast(key.number.integer));
            a[index] = ex;
        },
        .dictionary => |d| {
            try d.entries.put(key, ex);
        },
        else => |v| {
            std.log.err("unable to modify: value was {s}", .{@tagName(v)});
            return Error.InvalidExpressoinType;
        },
    }
}

fn evalStdlibCall(
    name: []const u8,
    context: stdlib.FunctionContext,
    evaled_args: []expr.Value,
    scope: *Scope,
) Error!void {
    if (stdlib.match_call_args(evaled_args, context.arity)) |match| {
        context.function(match, scope) catch unreachable; // TODO: handle error once error values are added
    } else |err| {
        std.debug.print(
            "ERROR: when calling '{s}': {}\n",
            .{ name, err },
        );
        return Error.ArityMismatch;
    }
}

pub fn evalFunctionCall(fc: *expr.FunctionCall, scope: *Scope) Error!void {
    const tmpArgs = try scope.allocator.alloc(expr.Value, fc.args.len);
    defer scope.allocator.free(tmpArgs);

    for (fc.args, tmpArgs) |*arg, *tmparg| {
        try evalExpression(arg, scope);
        tmparg.* = scope.result() orelse unreachable;
    }

    switch (fc.func.*) {
        .identifier => |id| {
            if (stdlib.builtins.get(id.name)) |fn_ctxt| {
                try evalStdlibCall(id.name, fn_ctxt, tmpArgs, scope);
            } else {
                if (scope.lookupFunction(id)) |f| {
                    const match = stdlib.match_runtime_call_args(tmpArgs, f.arity) catch
                        return Error.ArityMismatch;
                    var localScope = try Scope.fromCallMatch(scope.allocator, scope.out, scope, f.arity, match);
                    for (f.body) |st| {
                        try evalStatement(st, &localScope);
                    }
                    const result = localScope.result();
                    scope.return_result = result;
                } else {
                    std.debug.print("ERROR: no function with name '{s}'\n", .{id.name});
                    return Error.FunctionNotFound;
                }
            }
        },
        .wrapped => |e| {
            var tmp = expr.FunctionCall{ .func = e, .args = fc.args };
            try evalFunctionCall(&tmp, scope);
        },
        .functioncall => {
            var tmp = fc.func.*;
            try evalExpression(&tmp, scope);
            const f = scope.result() orelse unreachable;
            if (f != .function) {
                std.debug.print("ERROR: returned expression from function call is not a function but '{s}'\n", .{@tagName(f)});
                return Error.InvalidExpressoinType;
            }
            const tmp_fn = expr.Expression{ .value = f };
            var tmp2 = expr.FunctionCall{ .func = &tmp_fn, .args = fc.args };
            try evalFunctionCall(&tmp2, scope);
        },
        .value => |value| {
            if (value != .function) {
                std.log.err("called expression is not a function: {s}", .{@tagName(value)});
                return Error.InvalidExpressoinType;
            }
            const f = value.function;
            const match = stdlib.match_runtime_call_args(tmpArgs, f.arity) catch return Error.ArityMismatch;
            var localScope = try Scope.fromCallMatch(scope.allocator, scope.out, scope, f.arity, match);
            for (f.body) |st| {
                try evalStatement(st, &localScope);
            }
            const result = localScope.result();
            scope.return_result = result;
        },
        else => |e| {
            std.debug.print("ERROR: unexpected expression in function call: {s}\n", .{@tagName(e)});
            return Error.InvalidExpressoinType;
        },
    }
}

fn evalStructAccess(strct: *Expression, key: *Expression, scope: *Scope) Error!void {
    switch (strct.*) {
        .struct_access => |sa| {
            try evalStructAccess(sa.strct, sa.key, scope);
            const st = scope.result() orelse unreachable;
            var tmp = expr.Expression{ .value = st };
            try evalStructAccess(&tmp, key, scope);
        },
        .identifier => {
            try evalExpression(strct, scope);
            const st = scope.result() orelse unreachable;
            var tmp = expr.Expression{ .value = st };
            try evalStructAccess(&tmp, key, scope);
        },
        .value => |v| {
            try evalExpression(key, scope);
            const k = scope.result() orelse unreachable;
            switch (v) {
                .array => |xs| {
                    if (k != .number and k.number != .integer) {
                        std.log.err("in array index: key is not an integer: {s}", .{@tagName(k)});
                        return Error.InvalidExpressoinType;
                    }
                    const index = k.number.integer;
                    if (index >= 0 and index >= xs.len) {
                        std.log.err("in array index: key is out of bounds", .{});
                        return Error.InvalidExpressoinType;
                    }
                    scope.return_result = xs[@intCast(index)];
                },
                .dictionary => |dict| {
                    scope.return_result = dict.entries.get(k) orelse .{ .none = null };
                    // scope.return_result = dict.entries.get(k) orelse b: {
                    //     std.log.err("accessing index '{}' in dict found no element", .{k});
                    //     break :b .{ .none = null };
                    // };
                },
                else => |value| {
                    std.log.err("value can not be accessed: {s}", .{@tagName(value)});
                    return Error.InvalidExpressoinType;
                },
            }
        },
        .array => {
            try evalExpression(key, scope);
            const tmp_key = scope.result() orelse unreachable;
            try evalExpression(strct, scope);
            const a = (scope.result() orelse unreachable).array;
            if (tmp_key != .number or tmp_key.number != .integer or tmp_key.number.integer >= a.len and tmp_key.number.integer < 0) {
                std.debug.print("INFO: expr was: {s}\n", .{@tagName(tmp_key)});
                return Error.InvalidExpressoinType;
            }
            const index = tmp_key.number.integer;
            scope.return_result = a[@intCast(index)];
        },
        .dictionary => {
            try evalExpression(key, scope);
            const tmp_key = scope.result() orelse unreachable;
            try evalExpression(strct, scope);
            const d = (scope.result() orelse unreachable).dictionary;
            if (tmp_key != .number and tmp_key != .string and tmp_key != .boolean) {
                return Error.InvalidExpressoinType;
            }
            scope.return_result = d.entries.get(tmp_key) orelse return Error.NoEntryForKey;
        },
        else => |v| {
            const value = @tagName(v);
            std.debug.print("ERROR: Invalid structure to access: {s}\n", .{value});
            return Error.InvalidExpressoinType;
        },
    }
}

pub fn evalValue(value: expr.Value, scope: *Scope) Error!void {
    _ = scope;
    switch (value) {
        else => return Error.NotImplemented,
    }
}

pub fn evalExpression(value: *Expression, scope: *Scope) Error!void {
    switch (value.*) {
        .value => |v| {
            if (v == .function) {
                const f = v.function;
                const new_body = try scope.captureExternals(f.arity, f.body);
                scope.return_result = .{ .function = .{
                    .arity = f.arity,
                    .body = new_body,
                } };
            } else scope.return_result = v;
        },
        .identifier => |id| {
            scope.return_result = scope.lookup(id) orelse {
                std.debug.print("ERROR: no value found for '{s}'\n", .{id.name});
                return Error.ValueNotFound;
            };
        },
        .binary_op => |bin| try evalBinaryOp(bin.op, bin.left, bin.right, scope),
        .unary_op => |un| try evalUnaryOp(un.op, un.operant, scope),
        .wrapped => |w| {
            try evalExpression(w, scope);
        },
        .functioncall => |fc| {
            var tmp = fc;
            try evalFunctionCall(&tmp, scope);
        },
        .struct_access => |sa| try evalStructAccess(sa.strct, sa.key, scope),
        .array => |a| {
            const tmp = try scope.allocator.alloc(expr.Value, a.elements.len);
            for (a.elements, tmp) |*elem, *target| {
                try evalExpression(elem, scope);
                target.* = scope.result() orelse unreachable;
            }
            scope.return_result = .{ .array = tmp };
        },
        .dictionary => |d| {
            var tmp = try expr.yadlValue.Dictionary.empty(scope.allocator);
            for (d.entries) |entry| {
                try evalExpression(entry.key, scope);
                const out_key = scope.result() orelse unreachable;
                try evalExpression(entry.value, scope);
                const out_value = scope.result() orelse unreachable;
                try tmp.dictionary.entries.put(out_key, out_value);
            }
            scope.return_result = tmp;
        },
    }
}

fn evalUnaryOp(op: expr.Operator, operant: *Expression, scope: *Scope) !void {
    switch (op) {
        .arithmetic => |ops| {
            if (ops != .Sub) unreachable;
            try evalExpression(operant, scope);
            switch (scope.result() orelse unreachable) {
                .number => |num| {
                    if (num == .float) {
                        scope.return_result = expr.Value{ .number = .{ .float = -num.float } };
                    } else {
                        scope.return_result = expr.Value{ .number = .{ .integer = -num.integer } };
                    }
                },
                else => |value| {
                    std.log.err("operant of unary minus is not a number: {s}", .{@tagName(value)});
                    return Error.InvalidExpressoinType;
                },
            }
        },
        .boolean => |ops| {
            if (ops != .Not) unreachable;
            try evalExpression(operant, scope);
            switch (scope.result() orelse unreachable) {
                .boolean => |value| {
                    scope.return_result = .{ .boolean = !value };
                },
                else => |value| {
                    std.log.err("operant of unary not is not a boolean: {s}", .{@tagName(value)});
                    return Error.InvalidExpressoinType;
                },
            }
        },
        else => unreachable,
    }
}

fn evalBinaryOp(op: expr.Operator, left: *Expression, right: *Expression, scope: *Scope) !void {
    switch (op) {
        .arithmetic => |ops| try evalArithmeticOps(ops, left, right, scope),
        .compare => |ops| try evalCompareOps(ops, left, right, scope),
        .boolean => |ops| try evalBooleanOps(ops, left, right, scope),
    }
}

fn evalArithmeticOps(op: expr.ArithmeticOps, left: *Expression, right: *Expression, scope: *Scope) !void {
    try evalExpression(left, scope);
    const leftEval = scope.result() orelse unreachable;
    try evalExpression(right, scope);
    const rightEval = scope.result() orelse unreachable;

    switch (op) {
        .Add => switch (leftEval) {
            .string => |l| switch (rightEval) {
                .string => |r| {
                    const tmp = try std.mem.join(scope.allocator, "", &[_][]const u8{ l, r });
                    scope.return_result = .{ .string = tmp };
                },
                else => |value| {
                    std.log.err(
                        "right hand side of addition is {s}. Consider using the 'string' conversion function",
                        .{@tagName(value)},
                    );
                    return Error.InvalidExpressoinType;
                },
            },
            .number => |l| switch (rightEval) {
                .number => |r| {
                    const n = l.add(r);
                    if (n == .float) {
                        scope.return_result = .{ .number = .{ .float = n.float } };
                    } else {
                        scope.return_result = .{ .number = .{ .integer = n.integer } };
                    }
                },
                else => |value| {
                    std.log.err(
                        "right hand side of addition is {s}. Consider using the 'number' conversion function",
                        .{@tagName(value)},
                    );
                    return Error.InvalidExpressoinType;
                },
            },
            else => |e| {
                std.log.err(
                    "left hand side of addition is {s} which is not supportted implicitly.",
                    .{@tagName(e)},
                );
                return Error.InvalidExpressoinType;
            },
        },
        .Mul => switch (leftEval) {
            .number => |l| switch (rightEval) {
                .number => |r| {
                    const n = l.mul(r);
                    if (n == .float) {
                        scope.return_result = .{ .number = .{ .float = n.float } };
                    } else {
                        scope.return_result = .{ .number = .{ .integer = n.integer } };
                    }
                },
                else => |value| {
                    std.log.err(
                        "right hand side of multiplication is {s}. Consider using the 'number' conversion function",
                        .{@tagName(value)},
                    );
                    return Error.InvalidExpressoinType;
                },
            },
            else => |e| {
                std.log.err(
                    "left hand side of multiplication is {s} which is not supportted implicitly.",
                    .{@tagName(e)},
                );
                return Error.InvalidExpressoinType;
            },
        },
        .Sub => switch (leftEval) {
            .number => |l| switch (rightEval) {
                .number => |r| {
                    const n = l.sub(r);
                    if (n == .float) {
                        scope.return_result = .{ .number = .{ .float = n.float } };
                    } else {
                        scope.return_result = .{ .number = .{ .integer = n.integer } };
                    }
                },
                else => |value| {
                    std.log.err(
                        "right hand side of subtracion is {s}. Consider using the 'number' conversion function",
                        .{@tagName(value)},
                    );
                    return Error.InvalidExpressoinType;
                },
            },
            else => |e| {
                std.log.err(
                    "left hand side of multiplication is {s} which is not supportted implicitly.",
                    .{@tagName(e)},
                );
                return Error.InvalidExpressoinType;
            },
        },
        .Div => switch (leftEval) {
            .number => |l| switch (rightEval) {
                .number => |r| {
                    const n = l.div(r);
                    if (n == .float) {
                        scope.return_result = .{ .number = .{ .float = n.float } };
                    } else {
                        scope.return_result = .{ .number = .{ .integer = n.integer } };
                    }
                },
                else => |value| {
                    std.log.err(
                        "right hand side of division is {s}. Consider using the 'number' conversion function",
                        .{@tagName(value)},
                    );
                    return Error.InvalidExpressoinType;
                },
            },
            else => |e| {
                std.log.err(
                    "left hand side of division is {s} which is not supportted implicitly.",
                    .{@tagName(e)},
                );
                return Error.InvalidExpressoinType;
            },
        },
        .Expo => switch (leftEval) {
            .number => |l| switch (rightEval) {
                .number => |r| {
                    const n = l.expo(r);
                    if (n == .float) {
                        scope.return_result = .{ .number = .{ .float = n.float } };
                    } else {
                        scope.return_result = .{ .number = .{ .integer = n.integer } };
                    }
                },
                else => |value| {
                    std.log.err(
                        "Exponent is {s}. Consider using the 'number' conversion function",
                        .{@tagName(value)},
                    );
                    return Error.InvalidExpressoinType;
                },
            },
            else => |value| {
                std.log.err(
                    "right hand side of exponent is {s} which is not supportted implicitly.",
                    .{@tagName(value)},
                );
                return Error.InvalidExpressoinType;
            },
        },
        .Mod => switch (leftEval) {
            .number => |l| switch (rightEval) {
                .number => |r| {
                    const n = l.mod(r);
                    if (n == .float) {
                        scope.return_result = .{ .number = .{ .float = n.float } };
                    } else {
                        scope.return_result = .{ .number = .{ .integer = n.integer } };
                    }
                },
                else => |value| {
                    std.log.err(
                        "right hand side is {s}. Consider using the 'number' conversion function",
                        .{@tagName(value)},
                    );
                    return Error.InvalidExpressoinType;
                },
            },
            else => |value| {
                std.log.err(
                    "left hand side of modulo is {s} which is not supportted implicitly.",
                    .{@tagName(value)},
                );
                return Error.InvalidExpressoinType;
            },
        },
    }
}

fn evalCompareOps(op: expr.CompareOps, left: *Expression, right: *Expression, scope: *Scope) !void {
    try evalExpression(left, scope);
    const leftEval = scope.result() orelse unreachable;
    try evalExpression(right, scope);
    const rightEval = scope.result() orelse unreachable;

    switch (op) {
        .Equal => {
            scope.return_result = .{ .boolean = leftEval.eql(rightEval) };
        },
        .NotEqual => {
            scope.return_result = .{ .boolean = !leftEval.eql(rightEval) };
        },
        .Less => switch (leftEval) {
            .number => |l| switch (rightEval) {
                .number => |r| {
                    const tmp: bool = if (l == .integer and r == .integer) l.integer < r.integer else l.asFloat() < r.asFloat();
                    scope.return_result = .{ .boolean = tmp };
                },
                else => return Error.NotImplemented,
            },
            else => return Error.NotImplemented,
        },
        .LessEqual => {
            try evalCompareOps(.Less, left, right, scope);
            const less = scope.result() orelse unreachable;
            try evalCompareOps(.Equal, left, right, scope);
            const eql = scope.result() orelse unreachable;
            scope.return_result = .{ .boolean = less.boolean or eql.boolean };
        },
        .Greater => {
            try evalCompareOps(.LessEqual, left, right, scope);
            const out = scope.result() orelse unreachable;
            scope.return_result = .{ .boolean = !out.boolean };
        },
        .GreaterEqual => {
            try evalCompareOps(.Less, left, right, scope);
            const out = scope.result() orelse unreachable;
            scope.return_result = .{ .boolean = !out.boolean };
        },
    }
}

fn evalBooleanOps(op: expr.BooleanOps, left: *Expression, right: *Expression, scope: *Scope) !void {
    try evalExpression(left, scope);
    const leftEval = scope.result() orelse unreachable;
    try evalExpression(right, scope);
    const rightEval = scope.result() orelse unreachable;

    if (leftEval != .boolean or rightEval != .boolean) {
        std.debug.print("ERROR: boolean operators are only allowed for booleans\n", .{});
        return Error.InvalidExpressoinType;
    }

    const l = leftEval.boolean;
    const r = rightEval.boolean;

    switch (op) {
        .And => {
            scope.return_result = .{ .boolean = l and r };
        },
        .Or => {
            scope.return_result = .{ .boolean = l or r };
        },
        else => {
            unreachable;
        },
    }
}
