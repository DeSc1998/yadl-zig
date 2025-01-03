const std = @import("std");

const utils = @import("test-utils");

test "control-flow.whileloop" {
    const content = @embedFile("whileloop.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "control-flow.if-branches" {
    const content = @embedFile("if-branches.yadl");
    try utils.runContent(std.testing.allocator, content);
}
