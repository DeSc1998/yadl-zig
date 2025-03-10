const std = @import("std");
const stmt = @import("statement.zig");
pub const yadlValue = @import("value.zig");
const stdlibType = @import("stdlib/type.zig");

pub const Value = yadlValue.Value;
pub const Iterator = yadlValue.Iterator;
pub const Function = yadlValue.Function;
pub const ValueMap = yadlValue.ValueMap;

pub const ArithmeticOps = enum { Add, Sub, Mul, Div, Expo, Mod };
pub const BooleanOps = enum { And, Or, Not };
pub const CompareOps = enum { Less, LessEqual, Greater, GreaterEqual, Equal, NotEqual };

pub const Operator = union(enum) {
    arithmetic: ArithmeticOps,
    boolean: BooleanOps,
    compare: CompareOps,
};

pub const BinaryOp = struct {
    left: *Expression,
    right: *Expression,
    op: Operator,

    pub fn init(alloc: std.mem.Allocator, op: Operator, l: *Expression, r: *Expression) !*Expression {
        const out = try alloc.create(Expression);
        out.* = .{ .binary_op = BinaryOp{
            .op = op,
            .left = l,
            .right = r,
        } };
        return out;
    }
};

pub const UnaryOp = struct {
    operant: *Expression,
    op: Operator,

    pub fn init(alloc: std.mem.Allocator, op: Operator, operant: *Expression) !*Expression {
        const out = try alloc.create(Expression);
        out.* = .{ .unary_op = UnaryOp{
            .op = op,
            .operant = operant,
        } };
        return out;
    }
};

pub const Identifier = struct {
    name: []const u8,

    pub fn init(
        alloc: std.mem.Allocator,
        name: []const u8,
    ) !*Expression {
        const out = try alloc.create(Expression);
        out.* = .{ .identifier = Identifier{
            .name = name,
        } };
        return out;
    }
};

pub const FunctionCall = struct {
    func: *const Expression,
    args: []Expression,

    pub fn init(
        alloc: std.mem.Allocator,
        func: *const Expression,
        args: []Expression,
    ) !*Expression {
        const out = try alloc.create(Expression);
        out.* = .{ .functioncall = FunctionCall{
            .args = args,
            .func = func,
        } };
        return out;
    }
};

pub const StructureAccess = struct {
    strct: *Expression,
    key: *Expression,

    pub fn init(
        alloc: std.mem.Allocator,
        strct: *Expression,
        key: *Expression,
    ) !*Expression {
        const out = try alloc.create(Expression);
        out.* = .{ .struct_access = StructureAccess{
            .key = key,
            .strct = strct,
        } };
        return out;
    }
};

pub const Array = struct {
    elements: []Expression,

    pub fn init(
        alloc: std.mem.Allocator,
        elements: []Expression,
    ) !*Expression {
        const out = try alloc.create(Expression);
        out.* = .{ .array = Array{
            .elements = elements,
        } };
        return out;
    }
};

pub const DictionaryEntry = struct {
    key: *Expression,
    value: *Expression,
};
pub const Dictionary = struct {
    entries: []DictionaryEntry,

    pub fn init(
        alloc: std.mem.Allocator,
        entries: []DictionaryEntry,
    ) !*Expression {
        const out = try alloc.create(Expression);
        out.* = .{ .dictionary = Dictionary{
            .entries = entries,
        } };
        return out;
    }

    fn eql(self: Dictionary, other: Dictionary) bool {
        for (self.entries) |left| {
            for (other.entries) |right| {
                if (left.key.eql(right.key.*) and !left.value.eql(right.value.*)) {
                    return false;
                }
            }
        }
        return true;
    }
};

pub fn initValue(alloc: std.mem.Allocator, v: Value) !*Expression {
    const out = try alloc.create(Expression);
    out.* = .{ .value = v };
    return out;
}

pub const Expression = union(enum) {
    binary_op: BinaryOp,
    unary_op: UnaryOp,
    identifier: Identifier,
    wrapped: *Expression,
    struct_access: StructureAccess,
    functioncall: FunctionCall,
    array: Array,
    dictionary: Dictionary,
    value: yadlValue.Value,

    pub fn eql(self: Expression, other: Expression) bool {
        return switch (self) {
            .value => |v| {
                if (other == .value) {
                    return v.eql(other.value);
                } else return false;
            },
            else => {
                std.debug.print("INFO: expr eql for '{s}' and '{s}'\n", .{ @tagName(self), @tagName(other) });
                unreachable;
            },
        };
    }

    pub fn clone(self: Expression, alloc: std.mem.Allocator) !*Expression {
        return switch (self) {
            .identifier => |id| Identifier.init(alloc, id.name),
            .binary_op => |b| s: {
                const tmp = try alloc.create(Expression);
                tmp.* = .{ .binary_op = .{
                    .left = try b.left.clone(alloc),
                    .right = try b.right.clone(alloc),
                    .op = b.op,
                } };
                break :s tmp;
            },
            .unary_op => |u| b: {
                const tmp = try alloc.create(Expression);
                tmp.* = .{ .unary_op = .{
                    .operant = try u.operant.clone(alloc),
                    .op = u.op,
                } };
                break :b tmp;
            },
            .struct_access => |sa| b: {
                const st = try sa.strct.clone(alloc);
                const key = try sa.key.clone(alloc);
                break :b try StructureAccess.init(alloc, st, key);
            },
            .functioncall => |fc| b: {
                const tmp = try fc.func.clone(alloc);
                const args = try alloc.alloc(Expression, fc.args.len);
                for (fc.args, args) |fa, *a| {
                    const t = try fa.clone(alloc);
                    a.* = t.*;
                    alloc.destroy(t);
                }
                break :b try FunctionCall.init(alloc, tmp, args);
            },
            .wrapped => |e| try e.clone(alloc),
            .value => |v| b: {
                const tmp = try alloc.create(Expression);
                tmp.* = .{ .value = try v.clone() };
                break :b tmp;
            },
            .dictionary => |dict| {
                const entries = dict.entries;
                const out = try alloc.alloc(DictionaryEntry, entries.len);
                for (out, entries) |*o, entry| {
                    o.* = .{ .key = try entry.key.clone(alloc), .value = try entry.value.clone(alloc) };
                }
                const tmp = try alloc.create(Expression);
                tmp.* = .{ .dictionary = .{ .entries = out } };
                return tmp;
            },
            else => |v| {
                std.debug.print("TODO: clone of {s}\n", .{@tagName(v)});
                return error.NotImplemented;
            },
        };
    }
};

pub fn identifier(chars: []const u8) Identifier {
    return .{ .name = chars };
}

pub fn mapOp(chars: []const u8) Operator {
    // std.debug.print("INFO: mapOp {s}\n", .{chars});

    if (std.mem.eql(u8, chars, "+")) return .{ .arithmetic = .Add };
    if (std.mem.eql(u8, chars, "-")) return .{ .arithmetic = .Sub };
    if (std.mem.eql(u8, chars, "*")) return .{ .arithmetic = .Mul };
    if (std.mem.eql(u8, chars, "/")) return .{ .arithmetic = .Div };
    if (std.mem.eql(u8, chars, "^")) return .{ .arithmetic = .Expo };
    if (std.mem.eql(u8, chars, "%")) return .{ .arithmetic = .Mod };
    if (std.mem.eql(u8, chars, "and")) return .{ .boolean = .And };
    if (std.mem.eql(u8, chars, "or")) return .{ .boolean = .Or };
    if (std.mem.eql(u8, chars, "not")) return .{ .boolean = .Not };
    if (std.mem.eql(u8, chars, "==")) return .{ .compare = .Equal };
    if (std.mem.eql(u8, chars, "!=")) return .{ .compare = .NotEqual };
    if (std.mem.eql(u8, chars, "<=")) return .{ .compare = .LessEqual };
    if (std.mem.eql(u8, chars, ">=")) return .{ .compare = .GreaterEqual };
    if (std.mem.eql(u8, chars, "<")) return .{ .compare = .Less };
    if (std.mem.eql(u8, chars, ">")) return .{ .compare = .Greater };

    unreachable;
}

fn printIdent(out: std.io.AnyWriter, level: u8) !void {
    var l = level;
    while (l > 0) : (l -= 1) {
        try out.print("  ", .{});
    }
}

pub fn printExpression(out: std.io.AnyWriter, expr: Expression, indent: u8) !void {
    switch (expr) {
        .identifier => |id| {
            try printIdent(out, indent);
            try out.print("{s}\n", .{id.name});
        },
        .number => |n| {
            try printIdent(out, indent);
            switch (n) {
                .float => |v| try out.print("{}\n", .{v}),
                .integer => |v| try out.print("{}\n", .{v}),
            }
        },
        .boolean => |b| {
            try printIdent(out, indent);
            try out.print("{}\n", .{b.value});
        },
        .binary_op => |bin| {
            try printIdent(out, indent);
            switch (bin.op) {
                .arithmetic => |op| try out.print("{}\n", .{op}),
                .compare => |op| try out.print("{}\n", .{op}),
                .boolean => |op| try out.print("{}\n", .{op}),
            }
            try printExpression(out, bin.left.*, indent + 1);
            try printExpression(out, bin.right.*, indent + 1);
        },
        else => |ex| try out.print("TODO: {}\n", .{ex}),
    }
}

pub fn free_local(allocator: std.mem.Allocator, expr: Expression) void {
    switch (expr) {
        .wrapped => |e| {
            free(allocator, e);
        },
        .unary_op => |u| {
            free(allocator, u.operant);
        },
        .binary_op => |b| {
            free(allocator, b.left);
            free(allocator, b.right);
        },
        .struct_access => |sta| {
            free(allocator, sta.key);
            free(allocator, sta.strct);
        },
        .functioncall => |fc| {
            free(allocator, fc.func);
            allocator.free(fc.args);
        },
        .array => |a| {
            allocator.free(a.elements);
        },
        .dictionary => |d| {
            for (d.entries) |*e| {
                free(allocator, e.key);
                free(allocator, e.value);
            }
            allocator.free(d.entries);
        },
        else => {},
    }
}

pub fn free(allocator: std.mem.Allocator, expr: *const Expression) void {
    free_local(allocator, expr.*);
    allocator.destroy(expr);
}
