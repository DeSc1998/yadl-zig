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

pub fn match_call_args(exprs: []expression.Value, arity: libtype.Arity) MatchError!libtype.CallMatch {
    // TODO: add support for optional arguments and variadic arguments
    if (exprs.len > arity.unnamed_count and !arity.has_variadics) return MatchError.TooManyArguments;
    if (exprs.len < arity.unnamed_count) return MatchError.NotEnoughArguments;
    return .{
        .unnamed_args = exprs[0..arity.unnamed_count],
        .optional_args = &[0]libtype.OptionalArg{},
        .var_args = if (arity.has_variadics) exprs[arity.unnamed_count..] else null,
    };
}

pub fn match_runtime_call_args(exprs: []expression.Value, arity: expression.Function.Arity) MatchError!libtype.CallMatch {
    // TODO: add support for optional arguments and variadic arguments
    const has_variadics = if (arity.var_args) |_| true else false;
    if (exprs.len > arity.args.len and !has_variadics) return MatchError.TooManyArguments;
    if (exprs.len < arity.args.len) return MatchError.NotEnoughArguments;
    return .{
        .unnamed_args = exprs[0..arity.args.len],
        .optional_args = &[0]libtype.OptionalArg{},
        .var_args = if (has_variadics) exprs[arity.args.len..] else null,
    };
}

const mappings = .{
    .{ "len", FunctionContext{ .function = &functions.length, .arity = .{ .unnamed_count = 1 } } },
    .{ "last", FunctionContext{ .function = &functions.last, .arity = .{ .unnamed_count = 3 } } },
    .{ "first", FunctionContext{ .function = &functions.first, .arity = .{ .unnamed_count = 3 } } },
    .{ "type", FunctionContext{ .function = &functions._type, .arity = .{ .unnamed_count = 1 } } },
    // conversions
    .{ "bool", FunctionContext{ .function = &conversions.toBoolean, .arity = .{ .unnamed_count = 1 } } },
    .{ "number", FunctionContext{ .function = &conversions.toNumber, .arity = .{ .unnamed_count = 1 } } },
    .{ "as_int", FunctionContext{ .function = &conversions.asInterger, .arity = .{ .unnamed_count = 1 } } },
    .{ "string", FunctionContext{ .function = &conversions.toString, .arity = .{ .unnamed_count = 1 } } },
    // string ops
    .{ "trim", FunctionContext{ .function = &functions.string_trim, .arity = .{ .unnamed_count = 1 } } },
    .{ "split", FunctionContext{ .function = &functions.string_split, .arity = .{ .unnamed_count = 2 } } },
    .{ "repeat", FunctionContext{ .function = &functions.string_repeat, .arity = .{ .unnamed_count = 2 } } },
    .{ "count_substring", FunctionContext{ .function = &functions.string_count, .arity = .{ .unnamed_count = 2 } } },
    .{ "starts_with", FunctionContext{ .function = &functions.string_starts_with, .arity = .{ .unnamed_count = 2 } } },
    .{ "ends_with", FunctionContext{ .function = &functions.string_ends_with, .arity = .{ .unnamed_count = 2 } } },
    // data stream functions
    .{ "map", FunctionContext{ .function = &functions.map, .arity = .{ .unnamed_count = 2 } } },
    // NOTE: do function uses map. This might not be intended
    .{ "do", FunctionContext{ .function = &functions.map, .arity = .{ .unnamed_count = 2 } } },
    .{ "flatmap", FunctionContext{ .function = &functions.flatmap, .arity = .{ .unnamed_count = 2 } } },
    .{ "zip", FunctionContext{ .function = &functions.zip, .arity = .{ .unnamed_count = 2 } } },
    .{ "flatten", FunctionContext{ .function = &functions.flatten, .arity = .{ .unnamed_count = 1 } } },
    .{ "reduce", FunctionContext{ .function = &functions.reduce, .arity = .{ .unnamed_count = 2 } } },
    .{ "group_by", FunctionContext{ .function = &functions.group_by, .arity = .{ .unnamed_count = 2 } } },
    .{ "count", FunctionContext{ .function = &functions.count, .arity = .{ .unnamed_count = 2 } } },
    .{ "check_all", FunctionContext{ .function = &functions.check_all, .arity = .{ .unnamed_count = 2 } } },
    .{ "check_any", FunctionContext{ .function = &functions.check_any, .arity = .{ .unnamed_count = 2 } } },
    .{ "check_none", FunctionContext{ .function = &functions.check_none, .arity = .{ .unnamed_count = 2 } } },
    .{ "filter", FunctionContext{ .function = &functions.filter, .arity = .{ .unnamed_count = 2 } } },
    .{ "load", FunctionContext{ .function = &functions.load_data, .arity = .{ .unnamed_count = 2 } } },
    .{ "save", FunctionContext{ .function = &functions.save_data, .arity = .{ .unnamed_count = 3 } } },
    .{ "sort", FunctionContext{ .function = &functions.sort, .arity = .{ .unnamed_count = 2 } } },
    // iterator functions
    .{ "iterator", FunctionContext{ .function = &functions.iterator, .arity = .{ .unnamed_count = 3 } } },
    .{ "default_iterator", FunctionContext{ .function = &functions.default_iterator, .arity = .{ .unnamed_count = 1 } } },
    .{ "next", FunctionContext{ .function = &functions.iter_next, .arity = .{ .unnamed_count = 1 } } },
    .{ "peek", FunctionContext{ .function = &functions.iter_peek, .arity = .{ .unnamed_count = 1 } } },
    .{ "has_next", FunctionContext{ .function = &functions.iter_has_next, .arity = .{ .unnamed_count = 1 } } },

    .{ "append", FunctionContext{ .function = &functions.append, .arity = .{ .unnamed_count = 2 } } },

    .{ "print", FunctionContext{ .function = &functions.print, .arity = .{ .unnamed_count = 0, .has_variadics = true } } },
    .{ "write", FunctionContext{ .function = &functions.write, .arity = .{ .unnamed_count = 0, .has_variadics = true } } },
};
pub const builtins = std.static_string_map.StaticStringMap(FunctionContext).initComptime(mappings);
