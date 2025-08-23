const std = @import("std");

const libtypes = @import("type.zig");
const loading = @import("data.zig");
const maschine = @import("../maschine.zig");
const value = @import("../value.zig");

const Error = libtypes.MaschineError;

pub fn length(m: *maschine.Maschine) Error!void {
    const tmp = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    switch (tmp) {
        .array => |elements| {
            m.registers[0] =
                .{ .number = .{ .integer = @intCast(elements.len) } };
        },
        .dictionary => |d| {
            m.registers[0] =
                .{ .number = .{ .integer = @intCast(d.entries.count()) } };
        },
        else => |v| {
            std.debug.print("ERROR: unexpected case: {s}\n", .{@tagName(v)});
            return Error.IllegalValue;
        },
    }
}

pub fn @"type"(m: *maschine.Maschine) Error!void {
    const tmp = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    if (tmp != .function_pointer) {
        m.registers[0] = .{ .string = @tagName(tmp) };
    } else {
        m.registers[0] = .{ .string = "function" };
    }
}

pub fn is_none(m: *maschine.Maschine) Error!void {
    const tmp = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    m.registers[0] = .{ .boolean = tmp == .none };
}

fn printValue(val: value.Value, out: std.io.AnyWriter) Error!void {
    switch (val) {
        .number => |n| {
            if (n == .float) {
                out.print("{d}", .{n.float}) catch return Error.IO;
            } else out.print("{d}", .{n.integer}) catch return Error.IO;
        },
        .address => |addr| {
            out.print("0x{x}", .{addr}) catch return Error.IO;
        },
        .boolean => |v| {
            out.print("{}", .{v}) catch return Error.IO;
        },
        .string => |v| {
            out.print("{s}", .{v}) catch return Error.IO;
        },
        .array => |vs| {
            out.print("[", .{}) catch return Error.IO;
            var has_printed = false;
            for (vs) |v| {
                if (has_printed) {
                    out.print(", ", .{}) catch return Error.IO;
                } else has_printed = true;
                try printValue(v, out);
            }
            out.print("]", .{}) catch return Error.IO;
        },
        .dictionary => |vs| {
            _ = out.write("{") catch return Error.IO;
            var has_printed = false;
            var iter = vs.entries.iterator();
            while (iter.next()) |entry| {
                if (has_printed) {
                    _ = out.write(", ") catch return Error.IO;
                } else has_printed = true;
                try printValue(entry.key_ptr.*, out);
                _ = out.write(": ") catch return Error.IO;
                const v = vs.entries.get(entry.key_ptr.*) orelse unreachable;
                try printValue(v, out);
            }
            _ = out.write("}") catch return Error.IO;
        },
        // .formatted_string => |f| {
        //     try evalFormattedString(f, out);
        //     const string = result() orelse unreachable;
        //     std.debug.assert(string == .string);
        //     out.print("{s}", .{string.string}) catch return Error.IO;
        // },
        .iterator => {
            out.print("<{s}>", .{@tagName(val)}) catch return Error.IO;
        },
        .function_pointer => |cf| {
            out.print("<addr: 0x{X}, src-addr: 0x{X}, arity: (args: {}, var_args: {})>", .{
                cf.function_address,
                cf.source_address,
                cf.arity.args.len,
                if (cf.arity.var_args) |_| true else false,
            }) catch return Error.IO;
        },
        .none => _ = out.write("none") catch return Error.IO,
        else => |v| {
            std.debug.print("TODO: printing of value: {s}\n", .{@tagName(v)});
            return Error.NotImplemented;
        },
    }
}

pub fn print(m: *maschine.Maschine) Error!void {
    const count: usize = @intCast(m.registers[0].number.integer);
    var current: usize = 0;
    var has_printed = false;
    while (current < count) {
        const val = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
        if (has_printed) {
            m.out.print(" ", .{}) catch return Error.IO;
        } else has_printed = true;
        try printValue(val, m.out);
        current += 1;
    }
    m.out.print("\n", .{}) catch return Error.IO;
}

pub fn write(m: *maschine.Maschine) Error!void {
    const count: usize = @intCast(m.registers[0].number.integer);
    var current: usize = 0;
    var has_printed = false;
    while (current < count) {
        const val = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
        if (has_printed) {
            m.out.print(" ", .{}) catch return Error.IO;
        } else has_printed = true;
        try printValue(val, m.out);
        current += 1;
    }
}

pub fn append(m: *maschine.Maschine) Error!void {
    const array = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    const item = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    const allocator = m.value_stack.allocator;

    if (item != .array) {
        const out = try allocator.alloc(value.Value, array.array.len + 1);
        @memcpy(out[0..array.array.len], array.array);
        out[array.array.len] = item;
        m.registers[0] = .{ .array = out };
    } else {
        const src = array.array;
        const tmp = item.array;
        const out = try allocator.alloc(value.Value, src.len + tmp.len);
        @memcpy(out[0..src.len], src);
        @memcpy(out[src.len..], tmp);
        m.registers[0] = .{ .array = out };
    }
}

pub fn append_items(m: *maschine.Maschine) Error!void {
    const array = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    const allocator = m.value_stack.allocator;
    const arg_count_tmp = m.registers[0];
    if (arg_count_tmp != .number or arg_count_tmp.number != .integer) {
        return Error.IllegalValue;
    }
    if (array != .array) return Error.IllegalValue;
    const arg_count: usize = @intCast(arg_count_tmp.number.integer - 1);

    const tmp = try allocator.alloc(value.Value, array.array.len + arg_count);
    @memcpy(tmp[0..array.array.len], array.array);
    for (tmp[array.array.len..]) |*tmp_item| {
        const item = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
        tmp_item.* = item;
    }
    m.registers[0] = .{ .array = tmp };
}

pub fn take(m: *maschine.Maschine) Error!void {
    const elements = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    const number = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    std.debug.assert(number == .number and number.number == .integer);
    if (number.number.integer < 0) return Error.IllegalValue;

    switch (elements) {
        .array => |a| {
            const size: usize = @intCast(number.number.integer);
            m.registers[0] = .{ .array = a[0..size] };
        },
        else => |e| {
            std.debug.print("ERROR: `sort` is not defined for '{s}'\n", .{@tagName(e)});
            return Error.IllegalValue;
        },
    }
}
pub fn drop(m: *maschine.Maschine) Error!void {
    const elements = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    const number = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    std.debug.assert(number == .number and number.number == .integer);
    if (number.number.integer < 0) return Error.IllegalValue;

    switch (elements) {
        .array => |a| {
            const size: usize = @intCast(number.number.integer);
            if (size <= a.len)
                m.registers[0] = .{ .array = a[size..] }
            else
                m.registers[0] = .{ .array = &.{} };
        },
        else => |e| {
            std.debug.print("ERROR: `sort` is not defined for '{s}'\n", .{@tagName(e)});
            return Error.IllegalValue;
        },
    }
}

pub fn next(m: *maschine.Maschine) Error!void {
    const tmp = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    const iter = tmp.iterator;
    switch (iter.next_fn) {
        .pointer => |ptr| {
            const len = iter.data.len;
            for (0..iter.data.len) |index| {
                try m.value_stack.append(iter.data[len - index - 1]);
            }
            m.registers[0] = .{ .number = .{ .integer = @intCast(len) } };
            try maschine.push_frame(m, ptr);
        },
        .intrinsic => |func| {
            try func(iter.data, m);
        },
        else => unreachable,
    }
}

pub fn peek(m: *maschine.Maschine) Error!void {
    const tmp = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    const iter = tmp.iterator;
    switch (iter.peek_fn.?) {
        .pointer => |ptr| {
            const len = iter.data.len;
            for (0..iter.data.len) |index| {
                try m.value_stack.append(iter.data[len - index - 1]);
            }
            m.registers[0] = .{ .number = .{ .integer = @intCast(len) } };
            try maschine.push_frame(m, ptr);
        },
        .intrinsic => |func| {
            try func(iter.data, m);
        },
        else => unreachable,
    }
}

pub fn has_next(m: *maschine.Maschine) Error!void {
    const tmp = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    const iter = tmp.iterator;
    switch (iter.has_next_fn) {
        .pointer => |ptr| {
            const len = iter.data.len;
            for (0..iter.data.len) |index| {
                try m.value_stack.append(iter.data[len - index - 1]);
            }
            m.registers[0] = .{ .number = .{ .integer = @intCast(len) } };
            try maschine.push_frame(m, ptr);
        },
        .intrinsic => |func| {
            try func(iter.data, m);
        },
        else => unreachable,
    }
}

pub fn custom_iterator(m: *maschine.Maschine) Error!void {
    const source = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    const next_fn = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    const has_next_fn = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    const peek_fn = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);

    if (source == .iterator) {
        m.registers[0] = .{ .iterator = .{
            .allocator = m.value_stack.allocator,
            .data = try m.value_stack.allocator.dupe(value.Value, &.{source}),
            .next_fn = .{ .pointer = next_fn.function_pointer },
            .has_next_fn = .{ .pointer = has_next_fn.function_pointer },
            .peek_fn = .{ .pointer = peek_fn.function_pointer },
        } };
    } else if (source == .array) {
        m.registers[0] = .{ .iterator = .{
            .allocator = m.value_stack.allocator,
            .data = source.array,
            .next_fn = .{ .pointer = next_fn.function_pointer },
            .has_next_fn = .{ .pointer = has_next_fn.function_pointer },
            .peek_fn = .{ .pointer = peek_fn.function_pointer },
        } };
    }
}

const DEFAULT_INDEX = 1;
const DEFAULT_DATA_INDEX = 0;
fn default_next(data_expr: []value.Value, m: *maschine.Maschine) Error!void {
    const local_data = data_expr;
    switch (local_data[DEFAULT_DATA_INDEX]) {
        .array => |a| {
            std.debug.assert(local_data[DEFAULT_INDEX] == .number);
            std.debug.assert(local_data[DEFAULT_INDEX].number == .integer);
            const index = local_data[DEFAULT_INDEX].number.integer;
            const i: usize = @intCast(index);
            m.registers[0] = a[i];
            local_data[DEFAULT_INDEX] = .{ .number = .{ .integer = index + 1 } };
        },
        .dictionary => return Error.NotImplemented,
        else => return Error.IllegalValue,
    }
}

fn default_peek(data_expr: []value.Value, m: *maschine.Maschine) Error!void {
    const local_data = data_expr;
    switch (local_data[DEFAULT_DATA_INDEX]) {
        .array => |a| {
            std.debug.assert(local_data[DEFAULT_INDEX] == .number);
            std.debug.assert(local_data[DEFAULT_INDEX].number == .integer);
            const index = local_data[DEFAULT_INDEX];
            const i: usize = @intCast(index.number.integer);
            m.registers[0] = a[i];
        },
        .dictionary => return Error.NotImplemented,
        else => return Error.IllegalValue,
    }
}

fn default_has_next(data_expr: []value.Value, m: *maschine.Maschine) Error!void {
    const local_data = data_expr;
    switch (local_data[DEFAULT_DATA_INDEX]) {
        .array => |a| {
            std.debug.assert(local_data[DEFAULT_INDEX] == .number);
            std.debug.assert(local_data[DEFAULT_INDEX].number == .integer);
            const n: usize = @intCast(local_data[DEFAULT_INDEX].number.integer);
            const tmp: value.Value = .{ .boolean = a.len > n };
            m.registers[0] = tmp;
        },
        .dictionary => return Error.NotImplemented,
        else => return Error.IllegalValue,
    }
}

pub fn default_iterator(m: *maschine.Maschine) Error!void {
    const tmp = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    switch (tmp) {
        .iterator => {
            m.registers[0] = try tmp.clone();
        },
        .array => {
            const data = try m.value_stack.allocator.alloc(value.Value, 2);
            data[DEFAULT_DATA_INDEX] = tmp;
            data[DEFAULT_INDEX] = .{ .number = .{ .integer = 0 } };
            m.registers[0] = value.Iterator.initIntr(
                m.value_stack.allocator,
                &default_next,
                &default_has_next,
                &default_peek,
                data,
            );
        },
        .dictionary => return Error.NotImplemented,
        else => |v| {
            m.out.print(
                "error: in default_iterator: provided value was of type '{s}' which is not allowed",
                .{@tagName(v)},
            ) catch return Error.IO;
            return Error.IllegalValue;
        },
    }
}

pub fn toBoolean(m: *maschine.Maschine) Error!void {
    const tmp = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    m.registers[0] = switch (tmp) {
        .boolean => |b| .{ .boolean = b },
        .number => |n| switch (n) {
            .integer => |i| .{ .boolean = i != 0 },
            .float => |f| .{ .boolean = f != 0.0 },
        },
        .array => |a| .{ .boolean = a.len != 0 },
        .dictionary => |d| .{ .boolean = d.entries.count() != 0 },
        .string => |s| .{ .boolean = s.len != 0 },
        .none => .{ .boolean = false },
        else => return Error.NotImplemented,
    };
}

pub fn toNumber(m: *maschine.Maschine) Error!void {
    const expr = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    m.registers[0] = switch (expr) {
        .boolean => |b| .{ .number = .{ .integer = @intFromBool(b) } },
        .number => expr,
        .string => |str| if (std.fmt.parseFloat(f64, str)) |f|
            value.Value{ .number = .{ .float = f } }
        else |_| if (std.fmt.parseInt(i64, str, 10)) |i|
            value.Value{ .number = .{ .integer = i } }
        else |err| {
            std.log.err("failed to convert string to number: {}", .{err});
            return Error.IllegalValue;
        },
        .none => .{ .number = .{ .integer = 0 } },
        else => |e| {
            std.debug.print("ERROR: unhandled type in 'toNumber': {s}\n", .{@tagName(e)});
            return Error.NotImplemented;
        },
    };
}

pub fn asInterger(m: *maschine.Maschine) Error!void {
    const expr = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    if (expr == .number) {
        switch (expr.number) {
            .integer => m.registers[0] = expr,
            .float => |f| m.registers[0] =
                .{ .number = .{ .integer = @intFromFloat(f) } },
        }
    } else {
        try toNumber(m);
        const result = m.registers[0];
        m.registers[0] = switch (result.number) {
            .integer => result,
            .float => |f| .{ .number = .{ .integer = @intFromFloat(f) } },
        };
    }
}

pub fn toString(m: *maschine.Maschine) Error!void {
    const expr = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    switch (expr) {
        .boolean => |b| {
            const out = std.fmt.allocPrint(m.value_stack.allocator, "{}", .{b}) catch return Error.IO;
            m.registers[0] = .{ .string = out };
        },
        .number => |n| switch (n) {
            .integer => |i| {
                const out = std.fmt.allocPrint(m.value_stack.allocator, "{}", .{i}) catch return Error.IO;
                m.registers[0] = .{ .string = out };
            },
            .float => |f| {
                const out = std.fmt.allocPrint(m.value_stack.allocator, "{}", .{f}) catch return Error.IO;
                m.registers[0] = .{ .string = out };
            },
        },
        .string => m.registers[0] = expr,
        .none => m.registers[0] = .{ .string = "none" },
        else => |v| {
            std.log.err("can not convert to string: {s}", .{@tagName(v)});
            return Error.IllegalValue;
        },
    }
}

pub fn string_repeat(m: *maschine.Maschine) Error!void {
    const s = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    const r = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    const source = if (s == .string) s.string else return Error.IllegalValue;
    const reps = if (r == .number) r.number else return Error.IllegalValue;
    if (reps != .integer) {
        std.log.err("in 'repeat': can not repeat a string in a fractional amount", .{});
        return Error.IllegalValue;
    }
    const repeats = @as(usize, @intCast(reps.integer));
    const out = try m.value_stack.allocator.alloc(u8, repeats * source.len);
    for (0..repeats) |index| {
        const start = index * source.len;
        const end = (index + 1) * source.len;
        @memcpy(out[start..end], source);
    }
    m.registers[0] = .{ .string = out };
}

pub fn string_count(m: *maschine.Maschine) Error!void {
    const s = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    const n = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    const source = if (s == .string) s.string else return Error.IllegalValue;
    const needle = if (n == .string) n.string else return Error.IllegalValue;
    if (needle.len > 0) {
        const out: i64 = @truncate(@as(i128, std.mem.count(u8, source, needle)));
        m.registers[0] = .{ .number = .{ .integer = out } };
    } else m.registers[0] = .{ .number = .{ .integer = 0 } };
}

pub fn string_split(m: *maschine.Maschine) Error!void {
    const s = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    const n = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    const source = if (s == .string) s.string else return Error.IllegalValue;
    const needle = if (n == .string) n.string else return Error.IllegalValue;
    if (needle.len == 0) {
        var out = std.ArrayList(value.Value).init(m.value_stack.allocator);
        try out.append(try s.clone());
        m.registers[0] = .{ .array = try out.toOwnedSlice() };
        return;
    }
    var iter = std.mem.splitSequence(u8, source, needle);
    var out = std.ArrayList(value.Value).init(m.value_stack.allocator);
    while (iter.next()) |str| {
        const tmp = value.Value{ .string = str };
        try out.append(tmp);
    }
    m.registers[0] = .{ .array = try out.toOwnedSlice() };
}

pub fn string_trim(m: *maschine.Maschine) Error!void {
    const s = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    const string = if (s == .string) s.string else return Error.IllegalValue;
    if (string.len == 0) return;
    var front_index: usize = 0;
    var back_index: usize = string.len - 1;
    while (std.ascii.isWhitespace(string[front_index])) : (front_index += 1) {}
    while (std.ascii.isWhitespace(string[back_index])) : (back_index -= 1) {}
    const size = back_index - front_index + 1;
    if (size > 0) {
        const out = try m.value_stack.allocator.alloc(u8, size);
        for (out, string[front_index .. back_index + 1]) |*tmp, val| {
            tmp.* = val;
        }
        m.registers[0] = .{ .string = out };
    } else {
        m.registers[0] = .{ .string = "" };
    }
}

pub fn string_starts_with(m: *maschine.Maschine) Error!void {
    const s = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    const source = if (s == .string) s.string else return Error.IllegalValue;
    const n = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    const needle = if (n == .string) n.string else return Error.IllegalValue;
    m.registers[0] = .{ .boolean = std.mem.startsWith(u8, source, needle) };
}

pub fn string_ends_with(m: *maschine.Maschine) Error!void {
    const s = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    const source = if (s == .string) s.string else return Error.IllegalValue;
    const n = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    const needle = if (n == .string) n.string else return Error.IllegalValue;
    m.registers[0] = .{ .boolean = std.mem.endsWith(u8, source, needle) };
}

const DataFormat = enum {
    lines,
    json,
    csv,
    chars,
};

const DataFormatError = error{
    UnsupportedFormat,
};

fn parse_format(format: []const u8) DataFormatError!DataFormat {
    if (std.mem.eql(u8, format, "lines")) {
        return .lines;
    } else if (std.mem.eql(u8, format, "json")) {
        return .json;
    } else if (std.mem.eql(u8, format, "csv")) {
        return .csv;
    } else if (std.mem.eql(u8, format, "chars")) {
        return .chars;
    } else {
        return DataFormatError.UnsupportedFormat;
    }
}

pub fn load(m: *maschine.Maschine) Error!void {
    const allocator = m.value_stack.allocator;
    const file_path = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    const data_format = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    std.debug.assert(file_path == .string);
    std.debug.assert(data_format == .string);
    const format = parse_format(data_format.string) catch return Error.IO;
    m.registers[0] = switch (format) {
        .lines => lines: {
            const lines = loading.load_lines(file_path.string, allocator) catch |err| {
                std.debug.print("ERROR: loading file failed: {}\n", .{err});
                return Error.IO;
            };
            defer allocator.free(lines);
            const out = try allocator.alloc(value.Value, lines.len);
            for (lines, out) |line, *elem| {
                elem.* = .{ .string = line };
            }
            break :lines .{ .array = out };
        },
        .chars => chars: {
            const dir = std.fs.cwd();
            const file = dir.openFile(file_path.string, .{}) catch |err| {
                std.debug.print("ERROR: loading file '{s}' failed: {}\n", .{ file_path.string, err });
                return Error.IO;
            };
            const stat = file.stat() catch return Error.IO;
            const chars = file.readToEndAlloc(allocator, stat.size) catch return Error.OutOfMemory;
            break :chars .{ .string = chars };
        },
        .csv => loading.load_csv(file_path.string, allocator) catch |err| {
            std.debug.print("ERROR: loading file '{s}' failed: {}\n", .{ file_path.string, err });
            return Error.IO;
        },
        .json => loading.load_json(file_path.string, allocator) catch |err| {
            std.debug.print("ERROR: loading file '{s}' failed: {}\n", .{ file_path.string, err });
            return Error.IO;
        },
    };
}

pub fn save(m: *maschine.Maschine) Error!void {
    const user_data = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    const file_path = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    const data_format = m.value_stack.pop() orelse return maschine.print_trace(m, Error.EmptyStack);
    std.debug.assert(file_path == .string);
    std.debug.assert(data_format == .string);
    const format = parse_format(data_format.string) catch return Error.IO;
    const cwd = std.fs.cwd();
    var buffer: [128]u8 = undefined;
    const formatted_name = std.fmt.bufPrint(&buffer, "{s}.{s}", .{ file_path.string, @tagName(format) }) catch {
        std.debug.print("error: filename is to large\n", .{});
        return Error.IO;
    };
    var file = cwd.createFile(formatted_name, .{}) catch |err| {
        m.out.print("error: failed to create/open file '{s}': {}", .{ formatted_name, err }) catch return Error.IO;
        return Error.IO;
    };
    defer file.close();
    switch (format) {
        .json => {
            save_as_json(file.writer().any(), user_data) catch |err| {
                std.debug.print("error: loading file failed: {}\n", .{err});
                return Error.IO;
            };
            _ = file.write("\n\n") catch return Error.IO;
        },
        .csv => {
            var expr_map = value.ValueMap.init(m.value_stack.allocator);
            defer expr_map.deinit();
            save_as_csv(file.writer().any(), user_data, &expr_map) catch |err| {
                std.debug.print("error: loading file failed: {}\n", .{err});
                return Error.IO;
            };
            _ = file.write("\n\n") catch return Error.IO;
        },
        else => {
            m.out.print("error: can not save data: unsupportted format '{s}'", .{data_format.string}) catch return Error.IO;
            return Error.IO;
        },
    }
}

pub fn save_as_json(writer: std.io.AnyWriter, expr: value.Value) !void {
    _ = switch (expr) {
        .none => try writer.write("null"),
        .number => |n| {
            switch (n) {
                .integer => |int| try writer.print("{}", .{int}),
                .float => |fl| try writer.print("{d}", .{fl}),
            }
        },
        .boolean => |val| try writer.print("{}", .{val}),
        .string => |val| try writer.print("\"{s}\"", .{val}),
        .dictionary => |dict| {
            _ = try writer.write("{");
            var has_written = false;
            var iter = dict.entries.iterator();
            while (iter.next()) |entry| {
                if (has_written) {
                    _ = try writer.write(", ");
                } else has_written = true;
                try save_as_json(writer, entry.key_ptr.*);
                _ = try writer.write(": ");
                try save_as_json(writer, entry.value_ptr.*);
            }
            _ = try writer.write("");
            _ = try writer.write("}");
        },
        .array => |array| {
            _ = try writer.write("[");
            for (array[0 .. array.len - 1]) |entry| {
                try save_as_json(writer, entry);
                _ = try writer.write(", ");
            }
            const entry = array[array.len - 1];
            try save_as_json(writer, entry);
            _ = try writer.write("]");
        },
        else => return Error.IllegalValue,
    };
}

fn save_as_csv(writer: std.io.AnyWriter, expr: value.Value, expr_map: *value.ValueMap) !void {
    switch (expr) {
        .array => |elems| {
            if (elems.len > 0 and elems[0] == .dictionary) {
                try save_csv_header(writer, elems[0], expr_map);
                _ = try writer.write("\n");
            }
            for (elems) |entry| {
                try save_csv_entry(writer, entry, expr_map);
                _ = try writer.write("\n");
            }
        },
        .dictionary => {
            try save_csv_header(writer, expr, expr_map);
            _ = try writer.write("\n");
            try save_csv_dictionary(writer, expr, expr_map);
        },
        else => try save_csv_simple_entry(writer, expr),
    }
}

fn save_csv_entry(writer: std.io.AnyWriter, expr: value.Value, expr_map: *value.ValueMap) !void {
    switch (expr) {
        .array => |elems| {
            var has_printed = false;
            for (elems) |entry| {
                if (has_printed) {
                    _ = try writer.write(", ");
                } else has_printed = true;
                try save_csv_simple_entry(writer, entry);
            }
        },
        .dictionary => try save_csv_dictionary(writer, expr, expr_map),
        else => try save_csv_simple_entry(writer, expr),
    }
}

fn save_csv_simple_entry(writer: std.io.AnyWriter, expr: value.Value) !void {
    _ = switch (expr) {
        .none => try writer.print("\"{s}\"", .{"null"}),
        .string => |str| try writer.print("\"{s}\"", .{str}),
        .boolean => |val| try writer.print("{}", .{val}),
        .number => |n| {
            switch (n) {
                .float => |f| try writer.print("{d}", .{f}),
                .integer => |i| try writer.print("{}", .{i}),
            }
        },
        else => return Error.IllegalValue,
    };
}

fn save_csv_header(writer: std.io.AnyWriter, expr: value.Value, expr_map: *value.ValueMap) !void {
    std.debug.assert(expr == .dictionary);
    const entries = expr.dictionary.entries;
    if (entries.count() > 0) {
        var iter = entries.iterator();
        while (iter.next()) |entry| {
            try expr_map.put(entry.key_ptr.*, entry.value_ptr.*);
        }
    } else return;
    var has_printed = false;
    var iter = expr_map.keyIterator();
    while (iter.next()) |entry| {
        if (has_printed) {
            _ = try writer.write(", ");
        } else has_printed = true;
        try printValue(entry.*, writer);
    }
}

fn save_csv_dictionary(writer: std.io.AnyWriter, expr: value.Value, expr_map: *value.ValueMap) !void {
    std.debug.assert(expr == .dictionary);
    const entries = expr.dictionary.entries;
    var iter = entries.iterator();
    while (iter.next()) |entry| {
        try expr_map.put(entry.key_ptr.*, entry.value_ptr.*);
    }
    var has_printed = false;
    var out_iter = expr_map.keyIterator();
    while (out_iter.next()) |entry| {
        if (has_printed) {
            _ = try writer.write(", ");
        } else has_printed = true;
        const val = expr_map.get(entry.*) orelse unreachable;
        try save_csv_simple_entry(writer, val);
    }
}
