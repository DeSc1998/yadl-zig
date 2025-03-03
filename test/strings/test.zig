const std = @import("std");

const utils = @import("test-utils");

test "strings.concat" {
    const content = @embedFile("concat.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "strings.repeat" {
    const content = @embedFile("repeat.yadl");
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

test "strings.trim" {
    const content = @embedFile("trim.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "strings.split" {
    const content = @embedFile("split.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "strings.count" {
    const content = @embedFile("count.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "strings.affixes" {
    const content = @embedFile("pre-and-suffix.yadl");
    try utils.runContent(std.testing.allocator, content);
}
