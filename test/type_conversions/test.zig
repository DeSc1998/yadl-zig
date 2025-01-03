const std = @import("std");

const utils = @import("test-utils");

test "type-conversion.number-to-string" {
    const content = @embedFile("num_to_str.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "type-conversion.boolean-to-number" {
    const content = @embedFile("bool_to_num.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "type-conversion.boolean-to-string" {
    const content = @embedFile("bool_to_str.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "type-conversion.dictionary-to-string" {
    const content = @embedFile("dict_to_str.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "type-conversion.conversion-calls" {
    const content = @embedFile("conversion_calls.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "type-conversion.string-conversions" {
    const content = @embedFile("string_conversions.yadl");
    try utils.runContent(std.testing.allocator, content);
}
