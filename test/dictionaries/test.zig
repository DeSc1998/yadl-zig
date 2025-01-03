const std = @import("std");

const utils = @import("test-utils");

test "dictionaries.accessing" {
    const content = @embedFile("accessing.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "dictionaries.empty" {
    const content = @embedFile("empty.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "dictionaries.simple" {
    const content = @embedFile("dictionary.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "dictionaries.multilevel-access" {
    const content = @embedFile("multilevel-access.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "dictionaries.multilevel-access-empty" {
    const content = @embedFile("multilevel-access-empty.yadl");
    try utils.runContent(std.testing.allocator, content);
}
