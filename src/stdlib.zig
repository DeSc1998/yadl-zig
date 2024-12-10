const std = @import("std");

const expression = @import("expression.zig");
pub const libtype = @import("stdlib/type.zig");
const functions = @import("stdlib/functions.zig");
pub const conversions = @import("stdlib/conversions.zig");
const Scope = @import("Scope.zig");

pub const Error = error{
    NotImplemented,
    FunctionNotFound,
    BuiltinsNotInitialized,
} || std.mem.Allocator.Error;

const EvalError = libtype.Error;

const Expression = expression.Expression;

pub const FunctionContext = struct {
    function: libtype.StdlibFn,
    arity: libtype.Arity,
};

pub const MatchError = error{
    NotEnoughArguments,
    TooManyArguments,
    MissplacedArguments,
};

pub fn match_call_args(exprs: []const Expression, arity: libtype.Arity) MatchError!libtype.CallMatch {
    // TODO: add support for optional arguments and variadic arguments
    if (exprs.len > arity.unnamed_count and !arity.has_variadics) return MatchError.TooManyArguments;
    if (exprs.len < arity.unnamed_count) return MatchError.NotEnoughArguments;
    return .{
        .unnamed_args = exprs[0..arity.unnamed_count],
        .optional_args = &[0]libtype.OptionalArg{},
        .var_args = if (arity.has_variadics) exprs[arity.unnamed_count..] else null,
    };
}

const mappings = .{
    .{ "len", .{ .function = &functions.length, .arity = .{ .unnamed_count = 1 } } },
    .{ "last", .{ .function = &functions.last, .arity = .{ .unnamed_count = 3 } } },
    .{ "first", .{ .function = &functions.first, .arity = .{ .unnamed_count = 3 } } },
    .{ "type", .{ .function = &functions._type, .arity = .{ .unnamed_count = 1 } } },
    // conversions
    .{ "bool", .{ .function = &conversions.toBoolean, .arity = .{ .unnamed_count = 1 } } },
    .{ "number", .{ .function = &conversions.toNumber, .arity = .{ .unnamed_count = 1 } } },
    .{ "string", .{ .function = &conversions.toString, .arity = .{ .unnamed_count = 1 } } },
    // data stream functions
    .{ "map", .{ .function = &functions.map, .arity = .{ .unnamed_count = 2 } } },
    // NOTE: do function uses map. This might not be intended
    .{ "do", .{ .function = &functions.map, .arity = .{ .unnamed_count = 2 } } },
    .{ "flatmap", .{ .function = &functions.flatmap, .arity = .{ .unnamed_count = 2 } } },
    .{ "zip", .{ .function = &functions.zip, .arity = .{ .unnamed_count = 2 } } },
    .{ "flatten", .{ .function = &functions.flatten, .arity = .{ .unnamed_count = 1 } } },
    .{ "reduce", .{ .function = &functions.reduce, .arity = .{ .unnamed_count = 2 } } },
    .{ "groupBy", .{ .function = &functions.group_by, .arity = .{ .unnamed_count = 2 } } },
    .{ "count", .{ .function = &functions.count, .arity = .{ .unnamed_count = 2 } } },
    .{ "check_all", .{ .function = &functions.check_all, .arity = .{ .unnamed_count = 2 } } },
    .{ "check_any", .{ .function = &functions.check_any, .arity = .{ .unnamed_count = 2 } } },
    .{ "check_none", .{ .function = &functions.check_none, .arity = .{ .unnamed_count = 2 } } },
    .{ "filter", .{ .function = &functions.filter, .arity = .{ .unnamed_count = 2 } } },
    .{ "load", .{ .function = &functions.load_data, .arity = .{ .unnamed_count = 2 } } },
    .{ "sort", .{ .function = &functions.sort, .arity = .{ .unnamed_count = 2 } } },
    // iterator functions
    .{ "iterator", .{ .function = &functions.iterator, .arity = .{ .unnamed_count = 3 } } },
    .{ "default_iterator", .{ .function = &functions.default_iterator, .arity = .{ .unnamed_count = 1 } } },
    .{ "next", .{ .function = &functions.iter_next, .arity = .{ .unnamed_count = 1 } } },
    .{ "peek", .{ .function = &functions.iter_peek, .arity = .{ .unnamed_count = 1 } } },
    .{ "has_next", .{ .function = &functions.iter_has_next, .arity = .{ .unnamed_count = 1 } } },

    // TODO: We may want to remove this one
    .{ "print3", .{ .function = &functions.print3, .arity = .{ .unnamed_count = 1 } } },
    .{ "print", .{ .function = &functions.print, .arity = .{ .unnamed_count = 0, .has_variadics = true } } },
};
pub const builtins = std.static_string_map.StaticStringMap(FunctionContext).initComptime(mappings);
