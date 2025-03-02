const std = @import("std");

const utils = @import("test-utils");

test "data-loading.csv-headerless" {
    const content = @embedFile("csv-without-header.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "data-loading.csv" {
    const content = @embedFile("csv-with-header.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "data-loading.line-loading" {
    const content = @embedFile("lines_loading.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "data-loading.chars-loading" {
    const content = @embedFile("chars_loading.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "data-loading.json-top-level-array" {
    const content = @embedFile("top-level-array.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "data-loading.loading-and-filter" {
    const content = @embedFile("load_and_filter.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "data-loading.saving-of-json" {
    const content = @embedFile("json-saving.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "data-loading.saving-of-csv" {
    const content = @embedFile("csv-saving.yadl");
    try utils.runContent(std.testing.allocator, content);
}
