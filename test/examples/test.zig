const std = @import("std");

const utils = @import("test-utils");

test "examples.weather-data" {
    const content = @embedFile("weather-data.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "examples.old-people-in-bern" {
    const content = @embedFile("old-people-in-bern.yadl");
    try utils.runContent(std.testing.allocator, content);
}
