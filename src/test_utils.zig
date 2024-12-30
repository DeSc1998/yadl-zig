const std = @import("std");
const yadl = @import("yadl");

pub const Parser = yadl.Parser;
pub const interpreter = yadl.interpreter;
pub const Scope = yadl.Scope;

const Config = struct {
    allocator: std.mem.Allocator,
    output: [][]const u8,

    fn init(alloc: std.mem.Allocator, content: []const u8) !Config {
        var output = std.ArrayList([]const u8).init(alloc);
        var lines = std.mem.splitAny(u8, content, "\n");
        while (lines.next()) |line| {
            if (!std.mem.startsWith(u8, line, "// ")) continue;

            const option = line[3..];
            const check_out = "CHECK-OUT: ";
            if (std.mem.startsWith(u8, option, check_out)) {
                const tmp = option[check_out.len..];
                try output.append(tmp);
            }
        }
        return .{
            .allocator = alloc,
            .output = try output.toOwnedSlice(),
        };
    }

    fn deinit(self: Config) void {
        self.allocator.free(self.output);
    }
};

fn toLines(alloc: std.mem.Allocator, content: []const u8) ![][]const u8 {
    var output = std.ArrayList([]const u8).init(alloc);
    var lines = std.mem.splitAny(u8, content, "\n");
    while (lines.next()) |line| {
        if (line.len != 0)
            try output.append(line);
    }
    return output.toOwnedSlice();
}

fn validateOutput(expected: Config, actual: []const u8) !void {
    const lines = try toLines(expected.allocator, actual);
    defer expected.allocator.free(lines);
    try std.testing.expectEqual(expected.output.len, lines.len);
    for (lines, expected.output) |act, exp| {
        try std.testing.expectEqualStrings(exp, act);
    }
}

fn readFile(alloc: std.mem.Allocator, filepath: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(filepath, .{});
    defer file.close();
    const stat = try file.stat();
    const contents = try file.readToEndAlloc(alloc, stat.size);
    return contents;
}

fn testRun(alloc: std.mem.Allocator, test_file: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(alloc);
    const allocator = arena.allocator();
    defer arena.deinit();

    var output_buffer: [1024 * 50]u8 = undefined;
    var stream = std.io.fixedBufferStream(output_buffer[0..]);
    var out = stream.writer();

    std.debug.print("INFO: running test file: {s}\n", .{test_file});

    const content = try readFile(alloc, test_file);
    defer alloc.free(content);

    var parser = Parser.init(content, allocator);
    const stmts = try parser.parse();
    var scope = Scope.empty(allocator, out.any());
    for (stmts) |st| {
        try interpreter.evalStatement(st, &scope);
    }
    const expected = try Config.init(std.testing.allocator, content);
    defer expected.deinit();
    try validateOutput(expected, stream.getWritten());
}

pub fn runContent(alloc: std.mem.Allocator, content: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(alloc);
    const allocator = arena.allocator();
    defer arena.deinit();

    var output_buffer: [1024 * 50]u8 = undefined;
    var stream = std.io.fixedBufferStream(output_buffer[0..]);
    var out = stream.writer();

    var parser = Parser.init(content, allocator);
    const stmts = try parser.parse();
    var scope = Scope.empty(allocator, out.any());
    for (stmts) |st| {
        try interpreter.evalStatement(st, &scope);
    }
    const expected = try Config.init(std.testing.allocator, content);
    defer expected.deinit();
    try validateOutput(expected, stream.getWritten());
}
