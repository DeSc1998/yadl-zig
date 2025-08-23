const std = @import("std");

const interpreter = @import("../interpreter.zig");
const maschine = @import("../maschine.zig");
const expression = @import("../expression.zig");
const Scope = @import("../Scope.zig");

pub const Error = std.mem.Allocator.Error || interpreter.Error;
pub const MaschineError = maschine.Error;

pub const Arity = struct {
    // NOTE: unnamed from the perspective of the call site
    unnamed_count: u32,
    has_variadics: bool = false,
};

pub const OptionalArg = struct {
    name: []const u8,
    expr: expression.Value,
};

pub const CallMatch = struct {
    unnamed_args: []expression.Value,
    var_args: ?[]expression.Value,

    pub fn init(
        unnamed_args: []expression.Value,
        var_args: ?[]expression.Value,
    ) CallMatch {
        return .{
            .unnamed_args = unnamed_args,
            .var_args = var_args,
        };
    }
};

pub const StdlibFn = *const fn (CallMatch, *Scope) Error!void;
pub const NextFn = *const fn ([]expression.Value, *Scope) Error!void;
pub const HasNextFn = *const fn ([]expression.Value, *Scope) Error!void;
pub const PeekFn = *const fn ([]expression.Value, *Scope) Error!void;

pub const IntrinsicFn = *const fn (*maschine.Maschine) MaschineError!void;
pub const IntrIterFn = *const fn ([]expression.Value, *maschine.Maschine) MaschineError!void;
