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
            try scope.update(a.varName, scope.result_ref() orelse unreachable);
        },
        .functioncall => |fc| {
            var tmp = fc;
            try evalFunctionCall(&tmp, scope);
            scope.return_result = null;
        },
        .@"return" => |r| {
            try evalExpression(r.value, scope);
            const result = scope.result_ref() orelse unreachable;
            scope.return_result = result;
        },
        .whileloop => |w| {
            var cond = false;
            try evalExpression(w.loop.condition, scope);
            var tmp = scope.result() orelse unreachable;
            cond = tmp == .boolean and tmp.boolean.value;
            while (cond) {
                for (w.loop.body) |st| {
                    try evalStatement(st, scope);
                }

                try evalExpression(w.loop.condition, scope);
                tmp = scope.result() orelse unreachable;
                cond = tmp == .boolean and tmp.boolean.value;
            }
        },
        .if_statement => |i| {
            try evalExpression(i.ifBranch.condition, scope);
            const tmp = scope.result() orelse unreachable;
            if (tmp == .boolean and tmp.boolean.value) {
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
    const ex = scope.result_ref() orelse unreachable;
    try evalExpression(strct.struct_access.strct, scope);
    const contianer = scope.result_ref() orelse unreachable;
    try evalExpression(strct.struct_access.key, scope);
    const key = scope.result_ref() orelse unreachable;

    switch (contianer.*) {
        .array => |*a| {
            if (key.* != .number or key.number != .integer or key.number.integer >= a.elements.len and key.number.integer < 0) {
                std.debug.print("ERROR: invalid expressoin type: {s}\n", .{@tagName(key.*)});
                if (std.mem.eql(u8, @tagName(key.*), "binary_op"))
                    std.debug.print("ERROR: operator of binary: {}\n", .{key.binary_op.op});
                return Error.InvalidExpressoinType;
            }
            const index = @as(usize, @intCast(key.number.integer));
            expr.free_local(scope.allocator, a.elements[index]);
            a.elements[index] = ex.*;
        },
        .dictionary => |*d| {
            if (key.* != .number and key.* != .string and key.* != .boolean) {
                return Error.InvalidExpressoinType;
            }
            for (d.entries) |*e| {
                if (key.eql(e.key.*)) {
                    expr.free(scope.allocator, e.value);
                    e.value = ex;
                    return;
                }
            }
            const new_entries = try scope.allocator.alloc(expr.DictionaryEntry, d.entries.len + 1);
            for (d.entries, new_entries[0..d.entries.len]) |e, *new| {
                new.* = e;
            }
            new_entries[d.entries.len] = .{
                .key = key,
                .value = ex,
            };
            scope.allocator.free(d.entries);
            d.entries = new_entries;
        },
        else => return Error.InvalidExpressoinType,
    }
}

fn evalStdlibCall(context: stdlib.FunctionContext, evaled_args: []Expression, scope: *Scope) Error!void {
    if (stdlib.match_call_args(evaled_args, context.arity)) |match| {
        context.function(match, scope) catch unreachable; // TODO: handle error once error values are added
    } else |err| {
        std.debug.print(
            "ERROR: arguments mismatch expected: {}\n",
            .{err},
        );
        return Error.ArityMismatch;
    }
}

pub fn evalFunctionCall(fc: *expr.FunctionCall, scope: *Scope) Error!void {
    const tmpArgs = try scope.allocator.alloc(Expression, fc.args.len);
    defer scope.allocator.free(tmpArgs);

    for (fc.args, tmpArgs) |*arg, *tmparg| {
        try evalExpression(arg, scope);
        const tmp = scope.result() orelse unreachable;
        tmparg.* = tmp;
    }

    switch (fc.func.*) {
        .identifier => |id| {
            if (stdlib.builtins.get(id.name)) |fn_ctxt| {
                try evalStdlibCall(fn_ctxt, tmpArgs, scope);
            } else {
                if (scope.lookupFunction(id)) |f| {
                    const match = stdlib.match_runtime_call_args(tmpArgs, f.arity) catch return Error.ArityMismatch;
                    var localScope = try Scope.fromCallMatch(scope.allocator, scope.out, scope, f.arity, match);
                    for (f.body) |st| {
                        try evalStatement(st, &localScope);
                    }
                    const result = localScope.result_ref();
                    scope.return_result = result;
                } else {
                    std.debug.print("ERROR: no function found under the name '{s}'\n", .{id.name});
                    return Error.FunctionNotFound;
                }
            }
        },
        .wrapped => |e| {
            var tmp = .{ .func = e, .args = fc.args };
            try evalFunctionCall(&tmp, scope);
        },
        .functioncall => {
            var tmp = fc.func.*;
            try evalExpression(&tmp, scope);
            const f = scope.result_ref() orelse unreachable;
            // if (f != .function) {
            //     std.debug.print("ERROR: returned expression from function call is not a function but '{s}'\n", .{@tagName(f)});
            //     return Error.InvalidExpressoinType;
            // }
            var tmp2 = .{ .func = f, .args = fc.args };
            try evalFunctionCall(&tmp2, scope);
        },
        .function => |f| {
            const match = stdlib.match_runtime_call_args(tmpArgs, f.arity) catch return Error.ArityMismatch;
            var localScope = try Scope.fromCallMatch(scope.allocator, scope.out, scope, f.arity, match);
            for (f.body) |st| {
                try evalStatement(st, &localScope);
            }
            const result = localScope.result_ref();
            scope.return_result = result;
        },
        else => |e| {
            std.debug.print("ERROR: unhandled expression case in function call: {s}\n", .{@tagName(e)});
            return Error.NotImplemented;
        },
    }
}

fn evalStructAccess(strct: *Expression, key: *Expression, scope: *Scope) Error!void {
    switch (strct.*) {
        .struct_access => |sa| {
            try evalStructAccess(sa.strct, sa.key, scope);
            const st = scope.result_ref() orelse unreachable;
            try evalStructAccess(st, key, scope);
        },
        .identifier => {
            try evalExpression(strct, scope);
            const st = scope.result_ref() orelse unreachable;
            try evalStructAccess(st, key, scope);
        },
        .array => |a| {
            try evalExpression(key, scope);
            const tmp_key = scope.result_ref() orelse unreachable;
            if (tmp_key.* != .number or tmp_key.number != .integer or tmp_key.number.integer >= a.elements.len and tmp_key.number.integer < 0) {
                std.debug.print("INFO: expr was: {s}\n", .{@tagName(tmp_key.*)});
                if (std.mem.eql(u8, @tagName(tmp_key.*), "binary_op"))
                    std.debug.print("ERROR: operator of binary: {}\n", .{tmp_key.binary_op.op});
                return Error.InvalidExpressoinType;
            }
            const index = tmp_key.number.integer;
            scope.return_result = &a.elements[@intCast(index)];
        },
        .dictionary => |d| {
            try evalExpression(key, scope);
            const tmp_key = scope.result_ref() orelse unreachable;
            if (tmp_key.* != .number and tmp_key.* != .string and tmp_key.* != .boolean) {
                return Error.InvalidExpressoinType;
            }
            for (d.entries) |e| {
                if (tmp_key.eql(e.key.*)) {
                    scope.return_result = e.value;
                    return;
                }
            }
            return Error.NoEntryForKey;
        },
        else => |v| {
            const value = @tagName(v);
            std.debug.print("ERROR: Invalid structure to access: {s}\n", .{value});
            return Error.InvalidExpressoinType;
        },
    }
}

pub fn evalExpression(value: *Expression, scope: *Scope) Error!void {
    switch (value.*) {
        .identifier => |id| {
            var v = try scope.lookup(id) orelse {
                std.debug.print("ERROR: no value found for '{s}'\n", .{id.name});
                return Error.ValueNotFound;
            };
            while (v.* == .identifier) {
                v = try scope.lookup(id) orelse {
                    std.debug.print("ERROR: no value found for '{s}'\n", .{id.name});
                    return Error.ValueNotFound;
                };
            }
            scope.return_result = v;
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
            const tmp = try scope.allocator.alloc(Expression, a.elements.len);
            for (a.elements, tmp) |*elem, *target| {
                try evalExpression(elem, scope);
                const out = scope.result() orelse unreachable;
                target.* = out;
            }
            scope.return_result = try expr.Array.init(scope.allocator, tmp);
        },
        .dictionary => |d| {
            const tmp = try scope.allocator.alloc(expr.DictionaryEntry, d.entries.len);
            for (d.entries, tmp) |entry, *target| {
                try evalExpression(entry.key, scope);
                const out_key = scope.result_ref() orelse unreachable;
                try evalExpression(entry.value, scope);
                const out_value = scope.result_ref() orelse unreachable;
                target.* = expr.DictionaryEntry{
                    .key = out_key,
                    .value = out_value,
                };
            }
            scope.return_result = try expr.Dictionary.init(scope.allocator, tmp);
        },
        .function => |f| {
            const arity = expr.Function.Arity{ .args = ([0]expr.Identifier{})[0..] };
            const new_body = try scope.captureExternals(arity, f.body);
            const out = try scope.allocator.create(Expression);
            out.* = .{ .function = .{
                .arity = f.arity,
                .body = new_body,
            } };
            scope.return_result = out;
        },
        .number, .string, .boolean, .formatted_string, .none, .iterator => {
            scope.return_result = value;
        },
    }
}

fn evalUnaryOp(op: expr.Operator, operant: *Expression, scope: *Scope) !void {
    switch (op) {
        .arithmetic => |ops| {
            if (ops != .Sub) unreachable;
            switch (operant.*) {
                .number => |num| {
                    if (num == .float) {
                        const tmp = try expr.Number.init(scope.allocator, f64, -num.float);
                        scope.return_result = tmp;
                    } else {
                        const tmp = try expr.Number.init(scope.allocator, i64, -num.integer);
                        scope.return_result = tmp;
                    }
                },
                else => return Error.NotImplemented,
            }
        },
        .boolean => |ops| {
            if (ops != .Not) unreachable;
            switch (operant.*) {
                .boolean => |b| {
                    const tmp = try expr.Boolean.init(scope.allocator, !b.value);
                    scope.return_result = tmp;
                },
                else => return Error.NotImplemented,
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
                    const out = try scope.allocator.create(Expression);
                    const tmp = try std.mem.join(scope.allocator, "", &[_][]const u8{ l.value, r.value });
                    out.* = .{ .string = .{ .value = tmp } };
                    scope.return_result = out;
                },
                .boolean => {
                    var tmp_array = [1]Expression{rightEval};
                    try stdlib.conversions.toString(
                        stdlib.libtype.CallMatch.init(tmp_array[0..1], null, null),
                        scope,
                    );
                    const r = scope.result() orelse unreachable;
                    const out = try scope.allocator.create(Expression);
                    const inner = try std.mem.join(scope.allocator, "", &[_][]const u8{ l.value, r.string.value });
                    out.* = .{ .string = .{ .value = inner } };
                    scope.return_result = out;
                },
                .number => {
                    var tmp_array = [1]Expression{rightEval};
                    try stdlib.conversions.toString(
                        stdlib.libtype.CallMatch.init(tmp_array[0..1], null, null),
                        scope,
                    );
                    const r = scope.result() orelse unreachable;
                    const out = try scope.allocator.create(Expression);
                    const inner = try std.mem.join(scope.allocator, "", &[_][]const u8{ l.value, r.string.value });
                    out.* = .{ .string = .{ .value = inner } };
                    scope.return_result = out;
                },
                else => return Error.NotImplemented,
            },
            .number => |l| switch (rightEval) {
                .number => |r| {
                    const n = l.add(r);
                    if (n == .float) {
                        const tmp = try expr.Number.init(scope.allocator, f64, n.float);
                        scope.return_result = tmp;
                    } else {
                        const tmp = try expr.Number.init(scope.allocator, i64, n.integer);
                        scope.return_result = tmp;
                    }
                },
                .string => |str| {
                    var tmp_array = [1]Expression{leftEval};
                    try stdlib.conversions.toString(
                        stdlib.libtype.CallMatch.init(tmp_array[0..1], null, null),
                        scope,
                    );
                    const r = scope.result() orelse unreachable;
                    const out = try scope.allocator.create(Expression);
                    const inner = try std.mem.join(scope.allocator, "", &[_][]const u8{ r.string.value, str.value });
                    out.* = .{ .string = .{ .value = inner } };
                    scope.return_result = out;
                },
                else => {
                    std.debug.print("ERROR: arith. op. add: left = number, right = {s}\n", .{@tagName(rightEval)});
                    return Error.NotImplemented;
                },
            },
            else => |e| {
                var tmp_array = [1]Expression{e};
                try stdlib.conversions.toNumber(
                    stdlib.libtype.CallMatch.init(tmp_array[0..1], null, null),
                    scope,
                );
                const l = scope.result() orelse unreachable;
                tmp_array = [1]Expression{rightEval};
                try stdlib.conversions.toNumber(
                    stdlib.libtype.CallMatch.init(tmp_array[0..1], null, null),
                    scope,
                );
                const r = scope.result() orelse unreachable;
                const res = l.number.add(r.number);
                if (res == .float) {
                    const tmp = try expr.Number.init(scope.allocator, f64, res.float);
                    scope.return_result = tmp;
                } else {
                    const tmp = try expr.Number.init(scope.allocator, i64, res.integer);
                    scope.return_result = tmp;
                }
            },
        },
        .Mul => switch (leftEval) {
            .number => |l| switch (rightEval) {
                .number => |r| {
                    const n = l.mul(r);
                    if (n == .float) {
                        const tmp = try expr.Number.init(scope.allocator, f64, n.float);
                        scope.return_result = tmp;
                    } else {
                        const tmp = try expr.Number.init(scope.allocator, i64, n.integer);
                        scope.return_result = tmp;
                    }
                },
                else => |v| {
                    std.debug.print("ERROR: unhandled case in arith. Mul - number: {}\n", .{v});
                    return Error.NotImplemented;
                },
            },
            .string => |l| switch (rightEval) {
                .number => |r| {
                    std.debug.assert(r == .integer and r.integer >= 0);
                    const count = r.integer;
                    const tmp = try scope.allocator.alloc(u8, l.value.len * @as(usize, @intCast(count)));
                    for (0..@as(usize, @intCast(count))) |current| {
                        const index = current * l.value.len;
                        @memcpy(tmp[index .. index + l.value.len], l.value);
                    }
                    scope.return_result = try expr.String.init(scope.allocator, tmp);
                },
                else => |v| {
                    std.debug.print("ERROR: unhandled case in arith. Mul - number: {}\n", .{v});
                    return Error.NotImplemented;
                },
            },
            else => |e| {
                var tmp_array = [1]Expression{e};
                try stdlib.conversions.toNumber(
                    stdlib.libtype.CallMatch.init(tmp_array[0..1], null, null),
                    scope,
                );
                const l = scope.result() orelse unreachable;
                tmp_array = [1]Expression{rightEval};
                try stdlib.conversions.toNumber(
                    stdlib.libtype.CallMatch.init(tmp_array[0..1], null, null),
                    scope,
                );
                const r = scope.result() orelse unreachable;
                const res = l.number.mul(r.number);
                if (res == .float) {
                    const tmp = try expr.Number.init(scope.allocator, f64, res.float);
                    scope.return_result = tmp;
                } else {
                    const tmp = try expr.Number.init(scope.allocator, i64, res.integer);
                    scope.return_result = tmp;
                }
            },
        },
        .Sub => switch (leftEval) {
            .number => |l| switch (rightEval) {
                .number => |r| {
                    const n = l.sub(r);
                    if (n == .float) {
                        const tmp = try expr.Number.init(scope.allocator, f64, n.float);
                        scope.return_result = tmp;
                    } else {
                        const tmp = try expr.Number.init(scope.allocator, i64, n.integer);
                        scope.return_result = tmp;
                    }
                },
                else => return Error.NotImplemented,
            },
            else => |e| {
                var tmp_array = [1]Expression{e};
                try stdlib.conversions.toNumber(
                    stdlib.libtype.CallMatch.init(tmp_array[0..1], null, null),
                    scope,
                );
                const l = scope.result() orelse unreachable;
                tmp_array = [1]Expression{rightEval};
                try stdlib.conversions.toNumber(
                    stdlib.libtype.CallMatch.init(tmp_array[0..1], null, null),
                    scope,
                );
                const r = scope.result() orelse unreachable;
                const res = l.number.sub(r.number);
                if (res == .float) {
                    const tmp = try expr.Number.init(scope.allocator, f64, res.float);
                    scope.return_result = tmp;
                } else {
                    const tmp = try expr.Number.init(scope.allocator, i64, res.integer);
                    scope.return_result = tmp;
                }
            },
        },
        .Div => switch (leftEval) {
            .number => |l| switch (rightEval) {
                .number => |r| {
                    const n = l.div(r);
                    if (n == .float) {
                        const tmp = try expr.Number.init(scope.allocator, f64, n.float);
                        scope.return_result = tmp;
                    } else {
                        const tmp = try expr.Number.init(scope.allocator, i64, n.integer);
                        scope.return_result = tmp;
                    }
                },
                else => |v| {
                    std.debug.print("ERROR: unhandled case in arith. Div - number: {}\n", .{v});
                    return Error.NotImplemented;
                },
            },
            else => |e| {
                var tmp_array = [1]Expression{e};
                try stdlib.conversions.toNumber(
                    stdlib.libtype.CallMatch.init(tmp_array[0..1], null, null),
                    scope,
                );
                const l = scope.result() orelse unreachable;
                tmp_array = [1]Expression{rightEval};
                try stdlib.conversions.toNumber(
                    stdlib.libtype.CallMatch.init(tmp_array[0..1], null, null),
                    scope,
                );
                const r = scope.result() orelse unreachable;
                const res = l.number.div(r.number);
                if (res == .float) {
                    const tmp = try expr.Number.init(scope.allocator, f64, res.float);
                    scope.return_result = tmp;
                } else {
                    const tmp = try expr.Number.init(scope.allocator, i64, res.integer);
                    scope.return_result = tmp;
                }
            },
        },
        .Expo => switch (leftEval) {
            .number => |l| switch (rightEval) {
                .number => |r| {
                    const n = l.expo(r);
                    if (n == .float) {
                        const tmp = try expr.Number.init(scope.allocator, f64, n.float);
                        scope.return_result = tmp;
                    } else {
                        const tmp = try expr.Number.init(scope.allocator, i64, n.integer);
                        scope.return_result = tmp;
                    }
                },
                else => return Error.NotImplemented,
            },
            else => {
                std.debug.print("ERROR: can not add value of type '{s}'\n", .{@tagName(leftEval)});
                return Error.NotImplemented;
            },
        },
        .Mod => switch (leftEval) {
            .number => |l| switch (rightEval) {
                .number => |r| {
                    if (r == .integer and l == .integer) {
                        const tmp = std.math.mod(i64, l.integer, r.integer) catch return Error.InvalidExpressoinType;
                        scope.return_result = try expr.Number.init(scope.allocator, i64, tmp);
                    } else {
                        const leftmp = if (l == .integer) @as(f64, @floatFromInt(l.integer)) else l.float;
                        const rightmp = if (r == .integer) @as(f64, @floatFromInt(r.integer)) else r.float;

                        const tmp = std.math.mod(f64, leftmp, rightmp) catch return Error.InvalidExpressoinType;
                        scope.return_result = try expr.Number.init(scope.allocator, f64, tmp);
                    }
                },
                else => return Error.NotImplemented,
            },
            else => return Error.NotImplemented,
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
            const tmp = try scope.allocator.create(Expression);
            tmp.* = .{ .boolean = .{ .value = leftEval.eql(rightEval) } };
            scope.return_result = tmp;
        },
        .NotEqual => {
            const tmp = try scope.allocator.create(Expression);
            tmp.* = .{ .boolean = .{ .value = !leftEval.eql(rightEval) } };
            scope.return_result = tmp;
        },
        .Less => switch (leftEval) {
            .number => |l| switch (rightEval) {
                .number => |r| {
                    const out = try scope.allocator.create(Expression);
                    const tmp: bool = if (l == .integer and r == .integer) l.integer < r.integer else l.asFloat() < r.asFloat();
                    out.* = .{ .boolean = .{ .value = tmp } };
                    scope.return_result = out;
                },
                else => return Error.NotImplemented,
            },
            else => return Error.NotImplemented,
        },
        .LessEqual => {
            try evalCompareOps(.Less, left, right, scope);
            const less = scope.result_ref() orelse unreachable;
            try evalCompareOps(.Equal, left, right, scope);
            var out = scope.result_ref() orelse unreachable;
            out.boolean.value = out.boolean.value or less.boolean.value;
            expr.free(scope.allocator, less);
            scope.return_result = out;
        },
        .Greater => {
            try evalCompareOps(.LessEqual, left, right, scope);
            var out = scope.result_ref() orelse unreachable;
            out.boolean.value = !out.boolean.value;
            scope.return_result = out;
        },
        .GreaterEqual => {
            try evalCompareOps(.Less, left, right, scope);
            var out = scope.result_ref() orelse unreachable;
            out.boolean.value = !out.boolean.value;
            scope.return_result = out;
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

    const l = leftEval.boolean.value;
    const r = rightEval.boolean.value;

    switch (op) {
        .And => {
            const out = try scope.allocator.create(Expression);
            out.* = .{ .boolean = .{ .value = l and r } };
            scope.return_result = out;
        },
        .Or => {
            const out = try scope.allocator.create(Expression);
            out.* = .{ .boolean = .{ .value = l or r } };
            scope.return_result = out;
        },
        else => {
            unreachable;
        },
    }
}
