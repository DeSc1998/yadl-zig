const std = @import("std");

const utils = @import("test-utils");

test "functions.simple" {
    const content = @embedFile("simple.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "functions.chained" {
    const content = @embedFile("chained.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "functions.plane" {
    const content = @embedFile("function.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "functions.simple-block" {
    const content = @embedFile("block_simple.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "functions.nested-scope" {
    const content = @embedFile("nested_scope.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "functions.plane-simple" {
    const content = @embedFile("function-simple.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "functions.variadic-arguments" {
    const content = @embedFile("var-args-function.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "functions.return-empty-dictionary" {
    const content = @embedFile("empty_dictionaries.yadl");
    try utils.runContent(std.testing.allocator, content);
}
