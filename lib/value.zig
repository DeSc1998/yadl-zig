const std = @import("std");
const stmt = @import("statement.zig");
const stdlibType = @import("stdlib/type.zig");

pub const Identifier = @import("expression.zig").Identifier;

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

    pub fn init(comptime T: type, value: T) Value {
        std.debug.assert(T == f64 or T == i64);
        if (T == f64) {
            return .{ .number = Number{
                .float = value,
            } };
        } else if (T == i64) {
            return .{ .number = Number{
                .integer = value,
            } };
        } else unreachable;
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
        arity: Arity,
        body: []const stmt.Statement,
    ) Value {
        return .{ .function = Function{
            .arity = arity,
            .body = body,
        } };
    }
};

pub const Array = struct {
    elements: []Value,

    pub fn init(
        elements: []Value,
    ) !Value {
        return .{ .array = .{ .elements = elements } };
    }
};

const ValueMap = std.AutoHashMap(Value, Value);

pub const Dictionary = struct {
    entries: ValueMap,

    pub fn init(entries: ValueMap) Value {
        return .{ .entries = entries };
    }

    pub fn empty(alloc: std.mem.Allocator) !Value {
        return .{ .entries = ValueMap.init(alloc) };
    }

    fn eql(self: Dictionary, other: Dictionary) bool {
        _ = self;
        _ = other;
        return false;
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
    },
    data: Value,

    pub fn init(
        next_fn: Function,
        has_next_fn: Function,
        peek_fn: ?Function,
        data: Value,
    ) Value {
        return .{ .iterator = .{
            .next_fn = .{ .runtime = next_fn },
            .has_next_fn = .{ .runtime = has_next_fn },
            .peek_fn = if (peek_fn) |f| .{ .runtime = f } else null,
            .data = data,
        } };
    }

    pub fn initBuiltin(
        next_fn: stdlibType.NextFn,
        has_next_fn: stdlibType.HasNextFn,
        peek_fn: stdlibType.PeekFn,
        data: Value,
    ) Value {
        return .{ .iterator = .{
            .next_fn = .{ .builtin = next_fn },
            .has_next_fn = .{ .builtin = has_next_fn },
            .peek_fn = .{ .builtin = peek_fn },
            .data = data,
        } };
    }
};

const Value = union(enum) {
    none: void,
    boolean: bool,
    number: Number,
    string: []const u8,
    formatted_string: []const u8,
    array: Array,
    dictionary: Dictionary,
    iterator: Iterator,
    function: Function,

    pub fn none() Value {
        return .{.none};
    }

    pub fn eql(self: Value, other: Value) bool {
        switch (self) {
            .number => |n| {
                if (other == .number) {
                    return n.eql(other.number);
                } else return false;
            },
            else => return false,
        }
    }

    pub fn clone(self: Value) !Value {
        switch (self) {
            .dictionary => |d| {
                return .{ .dictionary = .{
                    .entries = try d.entries.clone(),
                } };
            },
            else => return self,
        }
    }
};

pub fn identifier(chars: []const u8) Identifier {
    return .{ .name = chars };
}

fn printIdent(out: std.io.AnyWriter, level: u8) !void {
    var l = level;
    while (l > 0) : (l -= 1) {
        try out.print("  ", .{});
    }
}

pub fn free(value: Value) void {
    if (value == .dictionary) {
        value.dictionary.entries.deinit();
    }
}
