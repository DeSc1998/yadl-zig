const std = @import("std");
const expr = @import("expression.zig");

pub const Assignment = struct {
    varName: expr.Identifier,
    value: *expr.Expression,
};
pub const StructuredAssignment = struct {
    access: *expr.Expression,
    value: *expr.Expression,
};
pub const Branch = struct {
    condition: *expr.Expression,
    body: []const Statement,
};
pub const If = struct {
    ifBranch: Branch,
    elseBranch: ?[]const Statement,
};
pub const WhileLoop = struct { loop: Branch };
pub const Return = struct { value: *expr.Expression };

pub const Statement = union(enum) {
    assignment: Assignment,
    struct_assignment: StructuredAssignment,
    if_statement: If,
    whileloop: WhileLoop,
    functioncall: expr.FunctionCall,
    @"return": Return,
};

pub fn assignment(id: []const u8, expression: *expr.Expression) Statement {
    return .{ .assignment = .{
        .varName = expr.identifier(id),
        .value = expression,
    } };
}

pub fn whileloop(cond: *expr.Expression, code: []const Statement) Statement {
    return .{ .whileloop = .{ .loop = .{
        .condition = cond,
        .body = code,
    } } };
}

fn printIdent(out: std.io.AnyWriter, level: u8) !void {
    var l = level;
    while (l > 0) : (l -= 1) {
        try out.print("  ", .{});
    }
}

pub fn printStatement(out: std.io.AnyWriter, st: Statement, indent: u8) !void {
    switch (st) {
        .ret => |r| {
            try printIdent(out, indent);
            try out.print("Return\n", .{});
            try expr.printExpression(out, r.value.*, indent + 1);
        },
        .whileloop => |w| {
            try printIdent(out, indent);
            try out.print("While loop\n", .{});
            try printIdent(out, indent);
            try out.print(" Condition\n", .{});
            try expr.printExpression(out, w.loop.condition.*, indent + 1);
            try printIdent(out, indent);
            try out.print(" Body\n", .{});
            for (w.loop.body) |stmt| {
                try printStatement(out, stmt, indent + 1);
            }
        },
        .assignment => |a| {
            try printIdent(out, indent);
            try out.print("Assignment\n", .{});
            try expr.printExpression(out, .{ .identifier = a.varName }, indent + 1);
            try expr.printExpression(out, a.value.*, indent + 1);
        },
        .struct_assignment => {
            try out.print("TODO: struct_assignment", .{});
        },
        .if_statement => |i| {
            try printIdent(out, indent);
            try out.print("If Statement\n", .{});
            try printIdent(out, indent);
            try out.print(" Condition\n", .{});
            try expr.printExpression(out, i.ifBranch.condition.*, indent + 1);
            try printIdent(out, indent);
            try out.print(" Body\n", .{});
            for (i.ifBranch.body) |stmt| {
                try printStatement(out, stmt, indent + 1);
            }

            if (i.elseBranch) |stmts| {
                try printIdent(out, indent);
                try out.print(" Else branch\n", .{});
                for (stmts) |stmt| {
                    try printStatement(out, stmt, indent + 1);
                }
            }
        },
        .functioncall => |fc| {
            try printIdent(out, indent);
            try out.print("Function Call:\n", .{});
            try printIdent(out, indent);
            try out.print(" name:\n", .{});
            try expr.printExpression(out, fc.func.*, indent + 1);
            try printIdent(out, indent);
            try out.print(" args:\n", .{});
            for (fc.args) |arg| {
                try expr.printExpression(out, arg, indent + 1);
            }
        },
    }
}

pub fn free(allocator: std.mem.Allocator, st: Statement) void {
    switch (st) {
        .@"return" => |r| {
            expr.free(allocator, r.value);
        },
        .whileloop => |w| {
            expr.free(allocator, w.loop.condition);
            allocator.free(w.loop.body);
        },
        .assignment => |a| {
            expr.free(allocator, a.value);
        },
        .if_statement => |i| {
            expr.free(allocator, i.ifBranch.condition);
            for (i.ifBranch.body) |s| {
                free(allocator, s);
            }
            allocator.free(i.ifBranch.body);
            if (i.elseBranch) |b| {
                for (b) |s| {
                    free(allocator, s);
                }
                allocator.free(b);
            }
        },
        .functioncall => |fc| {
            for (fc.args) |*arg| {
                expr.free(allocator, arg);
            }
            expr.free(allocator, fc.func);
        },
        .struct_assignment => |sa| {
            expr.free(allocator, sa.value);
            expr.free(allocator, sa.access);
        },
    }
}
