const std = @import("std");
const yadl = @import("yadl");

const Parser = yadl.Parser;
const stmt = yadl.statement;
const interpreter = yadl.interpreter;

const Scope = yadl.Scope;

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

fn readFile(alloc: std.mem.Allocator, filepath: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(filepath, .{});
    defer file.close();
    const stat = try file.stat();
    const contents = try file.readToEndAlloc(alloc, stat.size);
    return contents;
}

const Options = struct {
    files: []const []const u8,
    should_compile: bool,

    fn init(args: *std.process.ArgIterator) !Options {
        var files = std.ArrayList([]const u8).init(allocator);
        var should_compile = false;
        while (args.next()) |arg| {
            if (std.mem.endsWith(u8, arg, ".yadl")) {
                try files.append(arg);
                continue;
            }

            if (std.mem.eql(u8, arg, "--compile")) {
                should_compile = true;
                continue;
            }
            std.log.err("unable to process argument '{s}': {s}", .{ arg, "unsupported option" });
            return error.UnsupportedOption;
        }
        return .{
            .files = try files.toOwnedSlice(),
            .should_compile = should_compile,
        };
    }
};

fn runCompiled(stdout: std.io.AnyWriter, files: []const []const u8) !void {
    for (files) |filepath| {
        const input = readFile(allocator, filepath) catch |err| {
            try stdout.print("ERROR: reading file '{s}' failed: {}\n", .{ filepath, err });
            continue;
        };

        var out = try yadl.compile_source(input, allocator);
        try yadl.execute_source(out, stdout);
        out.deinit();
    }
}

fn run(stdout: std.io.AnyWriter, files: []const []const u8) !void {
    for (files) |filepath| {
        const input = readFile(allocator, filepath) catch |err| {
            try stdout.print("ERROR: reading file '{s}' failed: {}\n", .{ filepath, err });
            continue;
        };

        var parser = Parser.init(input, allocator);
        const stmts = try parser.parse();
        var scope = Scope.empty(allocator, stdout);

        for (stmts) |st| {
            try interpreter.evalStatement(st, &scope);
        }

        if (!arena.reset(.retain_capacity)) {
            for (stmts) |st| {
                stmt.free(allocator, st);
            }
            allocator.free(stmts);
        }
    }
}

pub fn main() !void {
    defer arena.deinit();

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var args = try std.process.argsWithAllocator(allocator);
    _ = args.next() orelse unreachable; // program name

    const options = try Options.init(&args);

    if (options.should_compile) {
        try runCompiled(stdout.any(), options.files);
        try bw.flush();
    } else {
        run(stdout.any(), options.files) catch |e| {
            try bw.flush();
            return e;
        };
        try bw.flush();
    }
}
