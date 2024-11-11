const std = @import("std");

const expression = @import("expression.zig");
const libtype = @import("stdlib/type.zig");
const functions = @import("stdlib/functions.zig");
pub const conversions = @import("stdlib/conversions.zig");
const Scope = @import("scope.zig");

pub const Error = error{
    NotImplemented,
    FunctionNotFound,
    BuiltinsNotInitialized,
} || std.mem.Allocator.Error;

const EvalError = libtype.Error;

const Expression = expression.Expression;

pub const FunctionContext = struct {
    function: libtype.StdlibFn,
    arity: u32,
};

const mappings = .{
    .{ "len", .{ .function = &functions.length, .arity = 1 } },
    .{ "last", .{ .function = &functions.last, .arity = 3 } },
    .{ "first", .{ .function = &functions.first, .arity = 3 } },
    .{ "type", .{ .function = &functions._type, .arity = 1 } },
    // conversions
    .{ "bool", .{ .function = &conversions.toBoolean, .arity = 1 } },
    .{ "number", .{ .function = &conversions.toNumber, .arity = 1 } },
    .{ "string", .{ .function = &conversions.toString, .arity = 1 } },
    // data stream functions
    .{ "map", .{ .function = &functions.map, .arity = 2 } },
    .{ "do", .{ .function = &functions.map, .arity = 2 } }, // NOTE: uses map. This might not be intended
    .{ "flatmap", .{ .function = &functions.flatmap, .arity = 2 } },
    .{ "zip", .{ .function = &functions.zip, .arity = 2 } },
    .{ "flatten", .{ .function = &functions.flatten, .arity = 1 } },
    .{ "reduce", .{ .function = &functions.reduce, .arity = 2 } },
    .{ "groupBy", .{ .function = &functions.group_by, .arity = 2 } },
    .{ "count", .{ .function = &functions.count, .arity = 2 } },
    .{ "check_all", .{ .function = &functions.check_all, .arity = 2 } },
    .{ "check_any", .{ .function = &functions.check_any, .arity = 2 } },
    .{ "check_none", .{ .function = &functions.check_none, .arity = 2 } },
    .{ "filter", .{ .function = &functions.filter, .arity = 2 } },
    .{ "load", .{ .function = &functions.load_data, .arity = 2 } },
    .{ "sort", .{ .function = &functions.sort, .arity = 2 } },
    // iterator functions
    .{ "iterator", .{ .function = &functions.iterator, .arity = 3 } },
    .{ "default_iterator", .{ .function = &functions.default_iterator, .arity = 1 } },
    .{ "next", .{ .function = &functions.iter_next, .arity = 1 } },
    .{ "has_next", .{ .function = &functions.iter_has_next, .arity = 1 } },

    // TODO: We may want to remove this one
    .{ "print3", .{ .function = &functions.print3, .arity = 1 } },
};
pub const builtins = std.static_string_map.StaticStringMap(FunctionContext).initComptime(mappings);
