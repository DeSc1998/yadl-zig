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
    dump_bytecode: bool,
    dump_to_file: bool,

    fn init(args: *std.process.ArgIterator) !Options {
        var files = std.ArrayList([]const u8).init(allocator);
        var should_compile = false;
        var dump_bytecode = false;
        var dump_to_file = false;
        while (args.next()) |arg| {
            if (std.mem.endsWith(u8, arg, ".yadl")) {
                try files.append(arg);
                continue;
            }
            if (std.mem.eql(u8, arg, "--compile")) {
                should_compile = true;
                continue;
            }
            if (std.mem.eql(u8, arg, "-d")) {
                dump_bytecode = true;
                continue;
            }
            if (std.mem.eql(u8, arg, "--dump-to-file")) {
                dump_to_file = true;
                continue;
            }
            std.log.err("unable to process argument '{s}': {s}", .{ arg, "unsupported option" });
            return error.UnsupportedOption;
        }
        return .{
            .files = try files.toOwnedSlice(),
            .should_compile = should_compile,
            .dump_bytecode = dump_bytecode,
            .dump_to_file = dump_to_file,
        };
    }
};

fn runCompiled(stdout: std.io.AnyWriter, options: Options) !void {
    for (options.files) |filepath| {
        const input = readFile(allocator, filepath) catch |err| {
            try stdout.print("ERROR: reading file '{s}' failed: {}\n", .{ filepath, err });
            continue;
        };

        var out = try yadl.compile_source(input, allocator);
        if (options.dump_bytecode) {
            const dump_file = if (options.dump_to_file)
                try std.fs.cwd().createFile("dump_source.txt", .{})
            else
                std.io.getStdErr();

            const tmp_writer = dump_file.writer();
            _ = try tmp_writer.write("--- stdlib ---\n");
            try yadl.compiled_sources.?.items[0].dump(dump_file);
            _ = try tmp_writer.write("--------------\n");
            try out.dump(dump_file);
        }
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
        const out = std.io.getStdOut().writer().any();
        runCompiled(out, options) catch |e| {
            try bw.flush();
            return e;
        };
        try bw.flush();
    } else {
        run(stdout.any(), options.files) catch |e| {
            try bw.flush();
            return e;
        };
        try bw.flush();
    }
}
