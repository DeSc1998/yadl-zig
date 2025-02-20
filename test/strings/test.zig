const std = @import("std");

const utils = @import("test-utils");

test "strings.concat" {
    const content = @embedFile("concat.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "strings.simple" {
    const content = @embedFile("simple.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "strings.multiline" {
    const content = @embedFile("multiline.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "strings.format" {
    const content = @embedFile("simple_format.yadl");
    try utils.runContent(std.testing.allocator, content);
}
