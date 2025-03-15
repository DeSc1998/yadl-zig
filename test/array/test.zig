const std = @import("std");

const utils = @import("test-utils");

test "array.access" {
    const content = @embedFile("array_access.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "array.modification" {
    const content = @embedFile("array_modification.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "array.modification_nested" {
    const content = @embedFile("nested_array_modification.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "array.empty" {
    const content = @embedFile("empty-array.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "array.simple" {
    const content = @embedFile("simple1.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "array.appending" {
    const content = @embedFile("appending.yadl");
    try utils.runContent(std.testing.allocator, content);
}
