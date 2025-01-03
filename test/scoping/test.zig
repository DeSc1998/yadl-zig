const std = @import("std");

const utils = @import("test-utils");

test "scoping.simple" {
    const content = @embedFile("scoping_simple.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "scoping.complex" {
    const content = @embedFile("scoping_complex.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "scoping.complex-same-var-name-1" {
    const content = @embedFile("same-var-name-complex1.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "scoping.complex-same-var-name-2" {
    const content = @embedFile("same-var-name-complex2.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "scoping.simple-same-var-name-1" {
    const content = @embedFile("same-var-name-simple1.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "scoping.simple-same-var-name-2" {
    const content = @embedFile("same-var-name-simple2.yadl");
    try utils.runContent(std.testing.allocator, content);
}
