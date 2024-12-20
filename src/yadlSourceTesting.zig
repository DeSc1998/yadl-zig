const std = @import("std");

const Parser = @import("Parser.zig");
const interpreter = @import("interpreter.zig");
const Scope = @import("Scope.zig");

const test_dir = "test/"; // TODO: hard coded file path

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

const array_test_dir = test_dir ++ "array/";
const array_files = [_][]const u8{
    "array_access.yadl",
    "array_modification.yadl",
    "empty-array.yadl",
    "nested_array_modification.yadl",
    "simple1.yadl",
};
const array_tests = b: {
    var tmp: [array_files.len][]const u8 = undefined;
    for (&tmp, array_files) |*out, file| {
        out.* = array_test_dir ++ file;
    }
    break :b tmp;
};

test "array" {
    const alloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    const allocator = arena.allocator();
    defer arena.deinit();

    var output_buffer: [1024 * 50]u8 = undefined;
    var stream = std.io.fixedBufferStream(output_buffer[0..]);
    var out = stream.writer();

    for (array_tests) |file| {
        const content = try readFile(std.testing.allocator, file);
        defer std.testing.allocator.free(content);

        var parser = Parser.init(content, allocator);
        const stmts = try parser.parse();
        var scope = Scope.empty(allocator, out.any());
        for (stmts) |st| {
            try interpreter.evalStatement(st, &scope);
        }
        const expected = try Config.init(std.testing.allocator, content);
        defer expected.deinit();
        try validateOutput(expected, stream.getWritten());
        stream.reset();
    }
}

const control_flow_test_dir = test_dir ++ "control_flow/";
const control_flow_files = [_][]const u8{
    "if-branches.yadl",
    "whileloop.yadl",
};
const control_flow_tests = b: {
    var tmp: [control_flow_files.len][]const u8 = undefined;
    for (&tmp, control_flow_files) |*out, file| {
        out.* = control_flow_test_dir ++ file;
    }
    break :b tmp;
};

test "control flow" {
    const alloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    const allocator = arena.allocator();
    defer arena.deinit();

    var output_buffer: [1024 * 50]u8 = undefined;
    var stream = std.io.fixedBufferStream(output_buffer[0..]);
    var out = stream.writer();

    for (control_flow_tests) |file| {
        const content = try readFile(std.testing.allocator, file);
        defer std.testing.allocator.free(content);

        var parser = Parser.init(content, allocator);
        const stmts = try parser.parse();
        var scope = Scope.empty(allocator, out.any());
        for (stmts) |st| {
            try interpreter.evalStatement(st, &scope);
        }
        const expected = try Config.init(std.testing.allocator, content);
        defer expected.deinit();
        try validateOutput(expected, stream.getWritten());
        stream.reset();
    }
}

const dictionary_test_dir = test_dir ++ "dictionaries/";
const dictionary_files = [_][]const u8{
    "accessing.yadl",
    "dictionary.yadl",
    "multilevel-access-empty.yadl",
    "multilevel-access.yadl",
    "simple.yadl",
};
const dictionary_tests = b: {
    var tmp: [dictionary_files.len][]const u8 = undefined;
    for (&tmp, dictionary_files) |*out, file| {
        out.* = dictionary_test_dir ++ file;
    }
    break :b tmp;
};

test "dictionay" {
    const alloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    const allocator = arena.allocator();
    defer arena.deinit();

    var output_buffer: [1024 * 50]u8 = undefined;
    var stream = std.io.fixedBufferStream(output_buffer[0..]);
    var out = stream.writer();

    for (dictionary_tests) |file| {
        const content = try readFile(std.testing.allocator, file);
        defer std.testing.allocator.free(content);

        var parser = Parser.init(content, allocator);
        const stmts = try parser.parse();
        var scope = Scope.empty(allocator, out.any());
        for (stmts) |st| {
            try interpreter.evalStatement(st, &scope);
        }
        const expected = try Config.init(std.testing.allocator, content);
        defer expected.deinit();
        try validateOutput(expected, stream.getWritten());
        stream.reset();
    }
}

const expressions_test_dir = test_dir ++ "expressions/";
const expressions_files = [_][]const u8{
    "add_mul.yadl",
    "associativity_minus.yadl",
    "exponent.yadl",
    "newline_in_expression_1.yadl",
    "newline_in_expression_2.yadl",
    "not_and.yadl",
    "operator-precedence.yadl",
    "simple.yadl",
    "unary_numbers.yadl",
};
const expressions_tests = b: {
    var tmp: [expressions_files.len][]const u8 = undefined;
    for (&tmp, expressions_files) |*out, file| {
        out.* = expressions_test_dir ++ file;
    }
    break :b tmp;
};

test "expressions" {
    const alloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    const allocator = arena.allocator();
    defer arena.deinit();

    var output_buffer: [1024 * 50]u8 = undefined;
    var stream = std.io.fixedBufferStream(output_buffer[0..]);
    var out = stream.writer();

    for (expressions_tests) |file| {
        const content = try readFile(std.testing.allocator, file);
        defer std.testing.allocator.free(content);

        var parser = Parser.init(content, allocator);
        const stmts = try parser.parse();
        var scope = Scope.empty(allocator, out.any());
        for (stmts) |st| {
            try interpreter.evalStatement(st, &scope);
        }
        const expected = try Config.init(std.testing.allocator, content);
        defer expected.deinit();
        try validateOutput(expected, stream.getWritten());
        stream.reset();
    }
}

const functions_test_dir = test_dir ++ "functions/";
const functions_files = [_][]const u8{
    "block_simple.yadl",
    "chained.yadl",
    "empty_dictionaries.yadl",
    "function-simple.yadl",
    "function.yadl",
    "nested_scope.yadl",
    "simple.yadl",
    "var-args-function.yadl",
};
const functions_tests = b: {
    var tmp: [functions_files.len][]const u8 = undefined;
    for (&tmp, functions_files) |*out, file| {
        out.* = functions_test_dir ++ file;
    }
    break :b tmp;
};

test "functions" {
    const alloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    const allocator = arena.allocator();
    defer arena.deinit();

    var output_buffer: [1024 * 50]u8 = undefined;
    var stream = std.io.fixedBufferStream(output_buffer[0..]);
    var out = stream.writer();

    for (functions_tests) |file| {
        const content = try readFile(std.testing.allocator, file);
        defer std.testing.allocator.free(content);

        var parser = Parser.init(content, allocator);
        const stmts = try parser.parse();
        var scope = Scope.empty(allocator, out.any());
        for (stmts) |st| {
            try interpreter.evalStatement(st, &scope);
        }
        const expected = try Config.init(std.testing.allocator, content);
        defer expected.deinit();
        try validateOutput(expected, stream.getWritten());
        stream.reset();
    }
}

const iterator_test_dir = test_dir ++ "iterator/";
const iterator_files = [_][]const u8{
    "check_builtins.yadl",
    "count.yadl",
    "default_iterator.yadl",
    "filter.yadl",
    "firstAndLast.yadl",
    "flatmap.yadl",
    "flatten.yadl",
    "groupBy.yadl",
    "iterator.yadl",
    "map.yadl",
    "reduce.yadl",
    "reduce_string.yadl",
    "zip.yadl",
};
const iterator_tests = b: {
    var tmp: [iterator_files.len][]const u8 = undefined;
    for (&tmp, iterator_files) |*out, file| {
        out.* = iterator_test_dir ++ file;
    }
    break :b tmp;
};

test "iterator" {
    const alloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    const allocator = arena.allocator();
    defer arena.deinit();

    var output_buffer: [1024 * 50]u8 = undefined;
    var stream = std.io.fixedBufferStream(output_buffer[0..]);
    var out = stream.writer();

    for (iterator_tests) |file| {
        const content = try readFile(std.testing.allocator, file);
        defer std.testing.allocator.free(content);

        var parser = Parser.init(content, allocator);
        const stmts = try parser.parse();
        var scope = Scope.empty(allocator, out.any());
        for (stmts) |st| {
            try interpreter.evalStatement(st, &scope);
        }
        const expected = try Config.init(std.testing.allocator, content);
        defer expected.deinit();
        try validateOutput(expected, stream.getWritten());
        stream.reset();
    }
}

const scoping_test_dir = test_dir ++ "scoping/";
const scoping_files = [_][]const u8{
    "same-var-name-complex1.yadl",
    "same-var-name-complex2.yadl",
    "same-var-name-simple1.yadl",
    "same-var-name-simple2.yadl",
    "scoping_complex.yadl",
    "scoping_simple.yadl",
};
const scoping_tests = b: {
    var tmp: [scoping_files.len][]const u8 = undefined;
    for (&tmp, scoping_files) |*out, file| {
        out.* = scoping_test_dir ++ file;
    }
    break :b tmp;
};

test "scoping" {
    const alloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    const allocator = arena.allocator();
    defer arena.deinit();

    var output_buffer: [1024 * 50]u8 = undefined;
    var stream = std.io.fixedBufferStream(output_buffer[0..]);
    var out = stream.writer();

    for (scoping_tests) |file| {
        const content = try readFile(std.testing.allocator, file);
        defer std.testing.allocator.free(content);

        var parser = Parser.init(content, allocator);
        const stmts = try parser.parse();
        var scope = Scope.empty(allocator, out.any());
        for (stmts) |st| {
            try interpreter.evalStatement(st, &scope);
        }
        const expected = try Config.init(std.testing.allocator, content);
        defer expected.deinit();
        try validateOutput(expected, stream.getWritten());
        stream.reset();
    }
}
