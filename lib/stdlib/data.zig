const std = @import("std");

const expression = @import("../expression.zig");

pub fn load_lines(path: []const u8, allocator: std.mem.Allocator) ![][]const u8 {
    const cwd = std.fs.cwd();
    const file = try cwd.openFile(path, .{ .mode = .read_only });
    const stat = try file.stat();
    const content = try file.readToEndAlloc(allocator, stat.size);
    // defer allocator.free(content);

    var splitter = std.mem.split(u8, content, "\n");
    var out = std.ArrayList([]const u8).init(allocator);
    while (splitter.next()) |line| {
        if (line.len == 0 and splitter.peek() == null)
            break;
        try out.append(line);
    }
    return try out.toOwnedSlice();
}

pub fn load_json(path: []const u8, allocator: std.mem.Allocator) !expression.Value {
    const cwd = std.fs.cwd();
    const file = try cwd.openFile(path, .{ .mode = .read_only });
    const stat = try file.stat();
    const content = try file.readToEndAlloc(allocator, stat.size);
    var tmp = std.json.Scanner.initCompleteInput(allocator, content);
    const value = try std.json.Value.jsonParse(
        allocator,
        &tmp,
        // TODO: hard coded value here
        .{ .duplicate_field_behavior = .use_first, .max_value_len = 1024 },
    );
    return map_to_expression(allocator, value);
}

pub fn load_csv(path: []const u8, allocator: std.mem.Allocator) !expression.Value {
    const cwd = std.fs.cwd();
    const file = try cwd.openFile(path, .{ .mode = .read_only });
    const stat = try file.stat();
    const content = try file.readToEndAlloc(allocator, stat.size);

    var splitter = std.mem.split(u8, content, "\n");
    var header: ?[][]const u8 = null;
    if (splitter.next()) |h| {
        if (is_header(h)) {
            // std.debug.print("INFO: 'is_header' was true\n", .{});
            var tmp = std.ArrayList([]const u8).init(allocator);
            var keys_splitter = std.mem.split(u8, h, ",");
            while (keys_splitter.next()) |key| {
                if (key.len > 2 and key[0] == '"') {
                    try tmp.append(key[1 .. key.len - 1]);
                } else {
                    try tmp.append(key);
                }
            }
            header = try tmp.toOwnedSlice();
        } else {
            // std.debug.print("INFO: 'is_header' was false\n", .{});
            splitter.reset();
        }
    }

    var out = std.ArrayList(expression.Value).init(allocator);
    while (splitter.next()) |line| {
        const data = parse_line(line, allocator) catch |err| if (err == error.LineEmpty) continue else return err;
        if (header) |heading| {
            var tmp = expression.ValueMap.init(allocator);
            std.debug.assert(heading.len == data.len);
            for (heading, data) |key, value| {
                try tmp.put(.{ .string = key }, value);
            }
            try out.append(.{ .dictionary = .{ .entries = tmp } });
        } else {
            try out.append(.{ .array = data });
        }
    }
    return .{ .array = try out.toOwnedSlice() };
}

fn parse_line(line: []const u8, allocator: std.mem.Allocator) ![]expression.Value {
    const Lexer = @import("../Lexer.zig");
    if (line.len == 0) return error.LineEmpty;
    var splitter = std.mem.split(u8, line, ",");
    var out = std.ArrayList(expression.Value).init(allocator);
    while (splitter.next()) |element| {
        var lexer = Lexer.init(element);
        if (lexer.nextToken()) |token| {
            switch (token.kind) {
                .Number => {
                    const tmp = try parseNumber(token.chars);
                    try out.append(tmp);
                },
                .String => {
                    try out.append(.{ .string = token.chars });
                },
                .Identifier => {
                    try out.append(.{ .string = token.chars });
                },
                .Boolean => {
                    try out.append(.{ .boolean = std.mem.eql(u8, token.chars, "true") });
                },
                .Keyword => {
                    try out.append(.{ .string = token.chars });
                },
                else => unreachable,
            }
            std.debug.assert(lexer.current_position == lexer.data.len);
        } else |err| {
            if (err != Lexer.Error.EndOfFile)
                return err;
        }
    }
    return out.toOwnedSlice();
}

fn baseOf(digits: []const u8) u8 {
    if (digits.len < 3)
        return 10;

    return switch (digits[1]) {
        'x' => 16,
        'o' => 8,
        'b' => 2,
        else => 10,
    };
}

fn parseNumber(chars: []const u8) !expression.Value {
    const base = baseOf(chars);

    if (std.mem.count(u8, chars, ".") > 0) {
        var parts = std.mem.split(u8, chars, ".");
        const tmp = parts.next() orelse unreachable;
        const int_part = if (base == 10) tmp else tmp[2..];
        const fraction_part = parts.rest();

        const int = try std.fmt.parseInt(i64, int_part, base);
        const fraction = try std.fmt.parseInt(i64, fraction_part, base);
        const frac: f64 = @as(f64, @floatFromInt(fraction)) / std.math.pow(
            f64,
            @floatFromInt(base),
            @floatFromInt(fraction_part.len),
        );
        const composite = @as(f64, @floatFromInt(int)) + frac;
        return .{ .number = .{ .float = composite } };
    } else {
        const int_part = if (base == 10) chars else chars[2..];
        const num = try std.fmt.parseInt(i64, int_part, base);
        return .{ .number = .{ .integer = num } };
    }
}

fn is_header(line: []const u8) bool {
    var splitter = std.mem.split(u8, line, ",");
    while (splitter.next()) |element| {
        // std.debug.print("INFO: considering element: '{s}'\n", .{element});
        if (element.len > 2 and element[0] == '"' and element[element.len - 1] == '"') {
            for (element[1 .. element.len - 1]) |char| {
                // std.debug.print("INFO: considering char: '{c}'\n", .{char});
                if (!std.ascii.isAlphanumeric(char) and !std.ascii.isWhitespace(char)) return false;
            }
        } else {
            for (element) |char|
                if (!std.ascii.isAlphabetic(char)) return false;
        }
    }
    return true;
}

fn map_to_expression(allocator: std.mem.Allocator, value: std.json.Value) std.mem.Allocator.Error!expression.Value {
    return switch (value) {
        .null => .{ .none = null },
        .bool => |b| .{ .boolean = b },
        .float => |f| .{ .number = .{ .float = f } },
        .integer => |n| .{ .number = .{ .integer = n } },
        .string => |s| .{ .string = s },
        .array => |a| b: {
            const tmp = try allocator.alloc(expression.Value, a.items.len);
            for (a.items, tmp) |item, *elem| {
                const t = try map_to_expression(allocator, item);
                elem.* = t;
            }
            break :b .{ .array = tmp };
        },
        .object => |o| b: {
            var tmp = expression.ValueMap.init(allocator);
            var iter = o.iterator();
            while (iter.next()) |entry| {
                const s: []u8 = try allocator.alloc(u8, entry.key_ptr.len);
                std.mem.copyForwards(u8, s, entry.key_ptr.*);
                const val = try map_to_expression(allocator, entry.value_ptr.*);
                const str = .{ .string = s };
                try tmp.put(str, val);
            }
            break :b .{ .dictionary = .{ .entries = tmp } };
        },
        else => unreachable,
    };
}
