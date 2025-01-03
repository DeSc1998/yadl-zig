const std = @import("std");

const utils = @import("test-utils");

test "miscellaneous.multiline-comment" {
    const content = @embedFile("multiline_comment.yadl");
    try utils.runContent(std.testing.allocator, content);
}
