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

pub fn main() !void {
    defer arena.deinit();

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var args = try std.process.argsWithAllocator(allocator);
    _ = args.next() orelse unreachable; // program name

    while (args.next()) |filepath| {
        const input = readFile(allocator, filepath) catch |err| {
            try stdout.print("ERROR: reading file '{s}' failed: {}\n", .{ filepath, err });
            continue;
        };

        var parser = Parser.init(input, allocator);
        const stmts = try parser.parse();
        var scope = Scope.empty(allocator, stdout.any());

        for (stmts) |st| {
            interpreter.evalStatement(st, &scope) catch |err| {
                try bw.flush();
                return err;
            };
        }
        try bw.flush();

        if (!arena.reset(.retain_capacity)) {
            for (stmts) |st| {
                stmt.free(allocator, st);
            }
            allocator.free(stmts);
        }
    }
}
