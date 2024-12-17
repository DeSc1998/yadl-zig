const std = @import("std");
const stmt = @import("statement.zig");
const stdlibType = @import("stdlib/type.zig");

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

pub const Number = union(enum) {
    integer: i64,
    float: f64,

    pub fn asFloat(self: Number) f64 {
        return if (self == .float) self.float else @as(f64, @floatFromInt(self.integer));
    }

    pub fn eql(self: Number, other: Number) bool {
        if (self == .integer and other == .integer) {
            return self.integer == other.integer;
        } else {
            return self.asFloat() == other.asFloat();
        }
    }

    pub fn add(self: Number, other: Number) Number {
        if (self == .integer and other == .integer) {
            return Number{ .integer = self.integer + other.integer };
        } else {
            return Number{ .float = self.asFloat() + other.asFloat() };
        }
    }

    pub fn sub(self: Number, other: Number) Number {
        if (self == .integer and other == .integer) {
            return Number{ .integer = self.integer - other.integer };
        } else {
            return Number{ .float = self.asFloat() - other.asFloat() };
        }
    }

    pub fn mul(self: Number, other: Number) Number {
        if (self == .integer and other == .integer) {
            return Number{ .integer = self.integer * other.integer };
        } else {
            return Number{ .float = self.asFloat() * other.asFloat() };
        }
    }

    pub fn div(self: Number, other: Number) Number {
        return Number{ .float = self.asFloat() / other.asFloat() };
    }

    pub fn expo(self: Number, other: Number) Number {
        if (self == .integer and other == .integer and other.integer >= 0) {
            const tmp = std.math.pow(i64, self.integer, other.integer);
            return Number{ .integer = tmp };
        } else {
            const tmp = std.math.pow(f64, self.asFloat(), other.asFloat());
            return Number{ .float = tmp };
        }
    }

    pub fn init(alloc: std.mem.Allocator, comptime T: type, value: T) !*Expression {
        std.debug.assert(T == f64 or T == i64);
        const out = try alloc.create(Expression);
        if (T == f64) {
            out.* = .{ .number = Number{
                .float = value,
            } };
        } else if (T == i64) {
            out.* = .{ .number = Number{
                .integer = value,
            } };
        } else unreachable;
        return out;
    }
};

pub const String = struct {
    value: []const u8,

    pub fn init(alloc: std.mem.Allocator, value: []const u8) !*Expression {
        const out = try alloc.create(Expression);
        out.* = .{ .string = String{
            .value = value,
        } };
        return out;
    }

    pub fn initFormatted(alloc: std.mem.Allocator, value: []const u8) !*Expression {
        const out = try alloc.create(Expression);
        out.* = .{ .formatted_string = String{
            .value = value,
        } };
        return out;
    }

    pub fn eql(self: String, other: String) bool {
        return std.mem.eql(u8, self.value, other.value);
    }
};
pub const Boolean = struct {
    value: bool,

    pub fn init(alloc: std.mem.Allocator, value: bool) !*Expression {
        const out = try alloc.create(Expression);
        out.* = .{ .boolean = Boolean{
            .value = value,
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

pub const Function = struct {
    arity: Arity,
    body: []const stmt.Statement,

    pub const Arity = struct {
        // allocator: std.mem.Allocator,
        args: []Identifier,
        optional_args: []Identifier = ([0]Identifier{})[0..],
        var_args: ?Identifier = null,

        pub fn init(args: []Identifier) Arity {
            return .{ .args = args };
        }

        pub fn initVarArgs(args: []Identifier, var_args: Identifier) Arity {
            return .{
                .args = args,
                .var_args = var_args,
            };
        }

        pub fn initFull(
            args: []Identifier,
            options: []Identifier,
            var_args: ?Identifier,
        ) Arity {
            return .{
                .args = args,
                .optional_args = options,
                .var_args = var_args,
            };
        }
    };

    pub fn init(
        alloc: std.mem.Allocator,
        arity: Arity,
        body: []const stmt.Statement,
    ) !*Expression {
        const out = try alloc.create(Expression);
        out.* = .{ .function = Function{
            .arity = arity,
            .body = body,
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

pub const Iterator = struct {
    next_fn: union(enum) {
        runtime: Function,
        builtin: stdlibType.NextFn,
    },
    has_next_fn: union(enum) {
        runtime: Function,
        builtin: stdlibType.HasNextFn,
    },
    peek_fn: ?union(enum) {
        runtime: Function,
        builtin: stdlibType.PeekFn,
    } = null,
    data: *Expression,

    pub fn init(
        alloc: std.mem.Allocator,
        next_fn: Function,
        has_next_fn: Function,
        data: *Expression,
    ) !*Expression {
        const out = try alloc.create(Expression);
        out.* = .{ .iterator = .{
            .next_fn = .{ .runtime = next_fn },
            .has_next_fn = .{ .runtime = has_next_fn },
            .data = data,
        } };
        return out;
    }

    pub fn initBuiltin(
        alloc: std.mem.Allocator,
        next_fn: stdlibType.NextFn,
        has_next_fn: stdlibType.HasNextFn,
        peek_fn: stdlibType.PeekFn,
        data: *Expression,
    ) !*Expression {
        const out = try alloc.create(Expression);
        out.* = .{ .iterator = .{
            .next_fn = .{ .builtin = next_fn },
            .has_next_fn = .{ .builtin = has_next_fn },
            .peek_fn = .{ .builtin = peek_fn },
            .data = data,
        } };
        return out;
    }
};

pub const Expression = union(enum) {
    boolean: Boolean,
    binary_op: BinaryOp,
    unary_op: UnaryOp,
    identifier: Identifier,
    number: Number,
    string: String,
    formatted_string: String,
    wrapped: *Expression,
    none: ?*Expression,
    struct_access: StructureAccess,
    functioncall: FunctionCall,
    function: Function,
    array: Array,
    dictionary: Dictionary,
    iterator: Iterator,

    pub fn eql(self: Expression, other: Expression) bool {
        return switch (self) {
            .number => |n| if (other == .number) n.eql(other.number) else false,
            .boolean => |n| if (other == .boolean) n.value == other.boolean.value else false,
            .string => |n| if (other == .string) n.eql(other.string) else false,
            .dictionary => |n| if (other == .dictionary) n.eql(other.dictionary) else if (other == .none) n.entries.len == 0 else false,
            .none => b: {
                std.debug.assert(if (self.none) |_| false else true);
                if (other == .dictionary) {
                    break :b other.dictionary.entries.len == 0;
                } else if (other == .none) {
                    break :b true;
                } else break :b false;
            },
            else => {
                std.debug.print("INFO: expr eql for '{s}' and '{s}'\n", .{ @tagName(self), @tagName(other) });
                unreachable;
            },
        };
    }

    pub fn clone(self: Expression, alloc: std.mem.Allocator) !*Expression {
        return switch (self) {
            .number => |n| if (n == .integer) Number.init(alloc, i64, n.integer) else Number.init(alloc, f64, n.float),
            .identifier => |id| Identifier.init(alloc, id.name),
            .string => |s| String.init(alloc, s.value),
            .array => |a| b: {
                const tmp = try alloc.alloc(Expression, a.elements.len);
                for (a.elements, tmp) |elem, *out| {
                    const t = try elem.clone(alloc);
                    out.* = t.*;
                    alloc.destroy(t);
                }
                break :b Array.init(alloc, tmp);
            },
            .dictionary => |d| b: {
                const new_entries = try alloc.alloc(DictionaryEntry, d.entries.len);
                for (d.entries, new_entries) |e, *new| {
                    new.key = try e.key.clone(alloc);
                    new.value = try e.value.clone(alloc);
                }
                break :b Dictionary.init(alloc, new_entries);
            },
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
            .function => |f| b: {
                const tmp = try alloc.create(Expression);
                const args = try alloc.alloc(Identifier, f.arity.args.len);
                const optionals = try alloc.alloc(Identifier, f.arity.optional_args.len);
                const body = try alloc.alloc(@TypeOf(f.body[0]), f.body.len);
                for (f.arity.args, args) |old, *new| {
                    new.* = .{ .name = old.name };
                }
                for (f.arity.optional_args, optionals) |old, *new| {
                    new.* = .{ .name = old.name };
                }
                for (f.body, body) |old, *new| {
                    new.* = old;
                }
                tmp.* = .{ .function = .{
                    .arity = Function.Arity.initFull(args, optionals, f.arity.var_args),
                    .body = body,
                } };
                break :b tmp;
            },
            .none => b: {
                const tmp = try alloc.create(Expression);
                tmp.* = .{ .none = null };
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
            .iterator => |iter| b: {
                const tmp = try iter.data.clone(alloc);
                if (iter.next_fn == .builtin) {
                    break :b try Iterator.initBuiltin(
                        alloc,
                        iter.next_fn.builtin,
                        iter.has_next_fn.builtin,
                        if (iter.peek_fn) |f| f.builtin else unreachable,
                        tmp,
                    );
                } else break :b try Iterator.init(alloc, iter.next_fn.runtime, iter.has_next_fn.runtime, tmp);
            },
            .boolean => |b| try Boolean.init(alloc, b.value),
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
        .function => |f| {
            for (f.body) |st| {
                stmt.free(allocator, st);
            }
            allocator.free(f.body);
            allocator.free(f.arity.args);
            allocator.free(f.arity.optional_args);
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
