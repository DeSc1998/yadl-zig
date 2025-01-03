const std = @import("std");

const utils = @import("test-utils");

test "iterator.custom-iterator" {
    const content = @embedFile("iterator.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "iterator.default-iterator" {
    const content = @embedFile("default_iterator.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "iterator.map" {
    const content = @embedFile("map.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "iterator.zip" {
    const content = @embedFile("zip.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "iterator.count" {
    const content = @embedFile("count.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "iterator.filter" {
    const content = @embedFile("filter.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "iterator.reduce" {
    const content = @embedFile("reduce.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "iterator.group-by" {
    const content = @embedFile("groupBy.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "iterator.flatmap" {
    const content = @embedFile("flatmap.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "iterator.flatten" {
    const content = @embedFile("flatten.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "iterator.first-and-last" {
    const content = @embedFile("firstAndLast.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "iterator.reduce-string" {
    const content = @embedFile("reduce_string.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "iterator.check-builtins" {
    const content = @embedFile("check_builtins.yadl");
    try utils.runContent(std.testing.allocator, content);
}
