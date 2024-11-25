const std = @import("std");

const interpreter = @import("../interpreter.zig");
const expression = @import("../expression.zig");
const Scope = @import("../scope.zig");

pub const Error = error{
    NotImplemented,
} || std.mem.Allocator.Error || interpreter.Error;

pub const StdlibFn = *const fn ([]const expression.Expression, *Scope) Error!void;
pub const NextFn = *const fn (*expression.Expression, *Scope) Error!void;
pub const HasNextFn = *const fn (*expression.Expression, *Scope) Error!void;
pub const PeekFn = *const fn (*expression.Expression, *Scope) Error!void;
