const std = @import("std");

const utils = @import("test-utils");

test "stdlib.map" {
    const content = @embedFile("map.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "stdlib.do" {
    const content = @embedFile("do.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "stdlib.zip" {
    const content = @embedFile("zip.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "stdlib.count" {
    const content = @embedFile("count.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "stdlib.filter" {
    const content = @embedFile("filter.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "stdlib.reduce" {
    const content = @embedFile("reduce.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "stdlib.group-by" {
    const content = @embedFile("groupBy.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "stdlib.flatmap" {
    const content = @embedFile("flatmap.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "stdlib.flatten" {
    const content = @embedFile("flatten.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "stdlib.first-and-last" {
    const content = @embedFile("firstAndLast.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "stdlib.reduce-string" {
    const content = @embedFile("reduce_string.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "stdlib.check-builtins" {
    const content = @embedFile("check_builtins.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "stdlib.sort" {
    const content = @embedFile("sort.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "stdlib.length" {
    const content = @embedFile("len.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "stdlib.write" {
    const content = @embedFile("write.yadl");
    try utils.runContent(std.testing.allocator, content);
}
