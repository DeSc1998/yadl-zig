const std = @import("std");

const utils = @import("test-utils");

const Error = utils.interpreter.Error;

test "failing.unknown-identifier" {
    const content = @embedFile("name_error.yadl");
    const result = utils.runContent(std.testing.allocator, content);
    try std.testing.expectError(Error.ValueNotFound, result);
}

test "failing.arity-missmatch" {
    const content = @embedFile("argument_missmatch.yadl");
    const result = utils.runContent(std.testing.allocator, content);
    try std.testing.expectError(Error.ArityMismatch, result);
}
