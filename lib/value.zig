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

    pub fn mod(self: Number, other: Number) Number {
        if (self == .integer and other == .integer and other.integer > 0) {
            const out = std.math.mod(i64, self.integer, other.integer) catch unreachable;
            return Number{ .integer = out };
        } else {
            const out = std.math.mod(f64, self.asFloat(), other.asFloat()) catch std.math.nan(f64);
            return Number{ .float = out };
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

const ValueContext = struct {
    const Self = @This();
    const funcs = @import("stdlib/functions.zig");
    const Scope = @import("Scope.zig");
    pub fn hash(self: Self, key: Value) u64 {
        _ = self;
        var buffer: [2048]u8 = undefined;
        var fixed_stream = std.io.fixedBufferStream(&buffer);
        const writer = fixed_stream.writer().any();
        funcs.save_as_json(writer, key) catch {};
        const used = fixed_stream.getWritten();
        return std.hash_map.hashString(used);
    }

    pub fn eql(self: Self, key: Value, other: Value) bool {
        const key_hash = self.hash(key);
        const other_hash = self.hash(other);
        return key_hash == other_hash;
    }
};

pub const ValueMap = std.HashMap(Value, Value, ValueContext, 80);

pub const Dictionary = struct {
    allocator: std.mem.Allocator,
    entries: *ValueMap,

    pub fn init(entries: ValueMap) !Value {
        const tmp = try entries.allocator.create(ValueMap);
        tmp.* = entries;
        return .{ .dictionary = .{ .allocator = entries.allocator, .entries = tmp } };
    }

    pub fn empty(alloc: std.mem.Allocator) !Value {
        const tmp = try alloc.create(ValueMap);
        tmp.* = ValueMap.init(alloc);
        return .{ .dictionary = .{ .allocator = alloc, .entries = tmp } };
    }
};

pub const Iterator = struct {
    allocator: std.mem.Allocator,
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
    data: []Value,

    pub fn init(
        alloc: std.mem.Allocator,
        next_fn: Function,
        has_next_fn: Function,
        peek_fn: ?Function,
        data: []Value,
    ) Value {
        return .{ .iterator = .{
            .allocator = alloc,
            .next_fn = .{ .runtime = next_fn },
            .has_next_fn = .{ .runtime = has_next_fn },
            .peek_fn = if (peek_fn) |f| .{ .runtime = f } else null,
            .data = data,
        } };
    }

    pub fn initBuiltin(
        alloc: std.mem.Allocator,
        next_fn: stdlibType.NextFn,
        has_next_fn: stdlibType.HasNextFn,
        peek_fn: stdlibType.PeekFn,
        data: []Value,
    ) Value {
        return .{ .iterator = .{
            .allocator = alloc,
            .next_fn = .{ .builtin = next_fn },
            .has_next_fn = .{ .builtin = has_next_fn },
            .peek_fn = .{ .builtin = peek_fn },
            .data = data,
        } };
    }
};

pub const Value = union(enum) {
    none: ?void,
    boolean: bool,
    number: Number,
    string: []const u8,
    formatted_string: []const u8,
    array: []Value,
    dictionary: Dictionary,
    iterator: Iterator,
    function: Function,

    pub fn none() Value {
        return Value{ .none = null };
    }

    pub fn eql(self: Value, other: Value) bool {
        switch (self) {
            .number => |n| {
                if (other == .number) {
                    return n.eql(other.number);
                } else return false;
            },
            .string => |str| return if (other == .string) std.mem.eql(u8, str, other.string) else false,
            .dictionary => |dict| {
                if (other == .dictionary) {
                    const same_count = dict.entries.count() == other.dictionary.entries.count();
                    if (!same_count) return false;
                    var iter_self = dict.entries.iterator();
                    while (iter_self.next()) |entry| {
                        const right = other.dictionary.entries.get(entry.key_ptr.*);
                        if (right) |value| {
                            if (!entry.value_ptr.eql(value)) return false;
                        } else return false;
                    }
                    return true;
                } else if (other == .none) {
                    return dict.entries.count() == 0;
                } else return false;
            },
            .array => |items| {
                if (other == .array) {
                    const tmp = other.array;
                    if (items.len != tmp.len) return false;
                    for (items, tmp) |left, right| {
                        if (!left.eql(right)) return false;
                    }
                    return true;
                } else return false;
            },
            .none => return if (other == .none) true else if (other == .dictionary and other.dictionary.entries.count() == 0) true else false,
            else => return false,
        }
    }

    pub fn clone(self: Value) !Value {
        switch (self) {
            .dictionary => |d| {
                return Dictionary.init(try d.entries.clone());
            },
            .iterator => |iter| {
                const tmp = try iter.allocator.alloc(Value, iter.data.len);
                for (tmp, iter.data) |*out, in| {
                    out.* = try in.clone();
                }
                return .{ .iterator = .{
                    .allocator = iter.allocator,
                    .next_fn = iter.next_fn,
                    .has_next_fn = iter.has_next_fn,
                    .peek_fn = iter.peek_fn,
                    .data = tmp,
                } };
            },
            else => return self,
        }
    }

    pub fn iter_clone(self: Value) !Value {
        switch (self) {
            .iterator => |iter| {
                const tmp = try iter.allocator.alloc(Value, iter.data.len);
                for (tmp, iter.data) |*out, in| {
                    out.* = try in.iter_clone();
                }
                return .{ .iterator = .{
                    .allocator = iter.allocator,
                    .next_fn = iter.next_fn,
                    .has_next_fn = iter.has_next_fn,
                    .peek_fn = iter.peek_fn,
                    .data = tmp,
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

pub fn free(value: Value, alloc: std.mem.Allocator) void {
    switch (value) {
        .dictionary => |dict| {
            dict.entries.deinit();
        },
        .array => |xs| {
            alloc.free(xs);
        },
        .string => |str| {
            alloc.free(str);
        },
        .formatted_string => |str| {
            alloc.free(str);
        },
        .function => |f| {
            for (f.body) |st| {
                stmt.free(alloc, st);
            }
            alloc.free(f.body);
            alloc.free(f.arity.args);
            alloc.free(f.arity.optional_args);
        },
        else => {},
    }
}
