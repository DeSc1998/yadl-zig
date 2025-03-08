const std = @import("std");

const expression = @import("../expression.zig");
const libtype = @import("type.zig");
const Scope = @import("../Scope.zig");
const Expression = expression.Expression;

const Error = @import("type.zig").Error;

pub fn toBoolean(args: libtype.CallMatch, scope: *Scope) Error!void {
    switch (args.unnamed_args[0]) {
        .boolean => |b| scope.return_result = .{ .boolean = b },
        .number => |n| scope.return_result = switch (n) {
            .integer => |i| .{ .boolean = i != 0 },
            .float => |f| .{ .boolean = f != 0.0 },
        },
        .array => |a| scope.return_result = .{ .boolean = a.len != 0 },
        .dictionary => |d| scope.return_result = .{ .boolean = d.entries.count() != 0 },
        .string => |s| scope.return_result = .{ .boolean = s.len != 0 },
        else => return Error.NotImplemented,
    }
}

pub fn toNumber(args: libtype.CallMatch, scope: *Scope) Error!void {
    const expr = args.unnamed_args[0];
    switch (expr) {
        .boolean => |b| scope.return_result = .{ .number = .{ .integer = @intFromBool(b) } },
        .number => scope.return_result = expr,
        .string => |str| {
            if (std.fmt.parseFloat(f64, str)) |f| {
                scope.return_result = .{ .number = .{ .float = f } };
            } else |_| {
                const tmp = std.fmt.parseInt(i64, str, 10) catch return Error.InvalidExpressoinType;
                scope.return_result = .{ .number = .{ .integer = tmp } };
            }
            return Error.NotImplemented;
        },
        else => |e| {
            std.debug.print("ERROR: unhandled type in 'toNumber': {s}\n", .{@tagName(e)});
            return Error.NotImplemented;
        },
    }
}

pub fn asInterger(args: libtype.CallMatch, scope: *Scope) Error!void {
    const expr = args.unnamed_args[0];
    if (expr == .number) {
        switch (expr.number) {
            .integer => scope.return_result = expr,
            .float => |f| scope.return_result =
                .{ .number = .{ .integer = @intFromFloat(f) } },
        }
    } else {
        try toNumber(args, scope);
        const result = scope.result() orelse unreachable;
        switch (result.number) {
            .integer => scope.return_result = result,
            .float => |f| scope.return_result =
                .{ .number = .{ .integer = @intFromFloat(f) } },
        }
    }
}

pub fn toString(args: libtype.CallMatch, scope: *Scope) Error!void {
    const expr = args.unnamed_args[0];
    switch (expr) {
        .boolean => |b| {
            const out = std.fmt.allocPrint(scope.allocator, "{}", .{b}) catch return Error.IOWrite;
            scope.return_result = .{ .string = out };
        },
        .number => |n| switch (n) {
            .integer => |i| {
                const out = std.fmt.allocPrint(scope.allocator, "{}", .{i}) catch return Error.IOWrite;
                scope.return_result = .{ .string = out };
            },
            .float => |f| {
                const out = std.fmt.allocPrint(scope.allocator, "{}", .{f}) catch return Error.IOWrite;
                scope.return_result = .{ .string = out };
            },
        },
        .string => scope.return_result = expr,
        else => |v| {
            std.log.err("can not convert to string: {s}", .{@tagName(v)});
            return Error.InvalidExpressoinType;
        },
    }
}
