const std = @import("std");

const utils = @import("test-utils");

test "expressions.simple" {
    const content = @embedFile("simple.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "expressions.exponent" {
    const content = @embedFile("exponent.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "expressions.add-and-multiply" {
    const content = @embedFile("add_mul.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "expressions.not-&-and" {
    const content = @embedFile("not_and.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "expressions.unary-numbers" {
    const content = @embedFile("unary_numbers.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "expressions.associativity-minus" {
    const content = @embedFile("associativity_minus.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "expressions.operator-precedence" {
    const content = @embedFile("operator-precedence.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "expressions.newline-in-expression-1" {
    const content = @embedFile("newline_in_expression_1.yadl");
    try utils.runContent(std.testing.allocator, content);
}

test "expressions.newline-in-expression-2" {
    const content = @embedFile("newline_in_expression_2.yadl");
    try utils.runContent(std.testing.allocator, content);
}
