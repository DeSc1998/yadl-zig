const std = @import("std");

const utils = @import("test-utils");

const files = [_][]const u8{
    "array_access.yadl",
    "array_modification.yadl",
    "empty-array.yadl",
    "nested_array_modification.yadl",
    "simple1.yadl",
};

test "array" {
    comptime for (files) |file| {
        const content = @embedFile(file);
        try utils.runContent(std.testing.allocator, content);
    };
}
