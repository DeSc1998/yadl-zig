const std = @import("std");

const interpreter = @import("../interpreter.zig");
const expression = @import("../expression.zig");
const Scope = @import("../Scope.zig");

pub const Error = error{
    NotImplemented,
} || std.mem.Allocator.Error || interpreter.Error;

pub const Arity = struct {
    // NOTE: unnamed from the perspective of the call site
    unnamed_count: u32,
    optionals: [][]const u8 = &[0][]const u8{},
    has_variadics: bool = false,
};

pub const OptionalArg = struct {
    name: []const u8,
    expr: expression.Expression,
};

pub const CallMatch = struct {
    unnamed_args: []expression.Expression,
    optional_args: []OptionalArg,
    var_args: ?[]expression.Expression,

    pub fn init(
        unnamed_args: []expression.Expression,
        optionals: ?[]OptionalArg,
        var_args: ?[]expression.Expression,
    ) CallMatch {
        return .{
            .unnamed_args = unnamed_args,
            .optional_args = if (optionals) |ops| ops else (([0]OptionalArg{})[0..]),
            .var_args = var_args,
        };
    }

    pub fn optional_by_name(self: CallMatch, name: []const u8) ?expression.Expression {
        for (self.optional_args) |arg| {
            if (std.mem.eql(u8, arg.name, name)) return arg.expr;
        }
        return null;
    }
};

pub const StdlibFn = *const fn (CallMatch, *Scope) Error!void;
pub const NextFn = *const fn (*expression.Expression, *Scope) Error!void;
pub const HasNextFn = *const fn (*expression.Expression, *Scope) Error!void;
pub const PeekFn = *const fn (*expression.Expression, *Scope) Error!void;
