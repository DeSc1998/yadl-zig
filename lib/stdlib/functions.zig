const std = @import("std");

const Parser = @import("../Parser.zig");
const expression = @import("../expression.zig");
const statement = @import("../statement.zig");
const interpreter = @import("../interpreter.zig");
const libtype = @import("type.zig");
const data = @import("data.zig");
const conversions = @import("conversions.zig");
const Scope = @import("../Scope.zig");
const Expression = expression.Expression;
const Value = expression.Value;
const ValueMap = expression.ValueMap;
const Statement = statement.Statement;

pub const Error = @import("type.zig").Error;

fn exec_runtime_function(func: expression.Function, call_args: []Value, scope: *Scope) Error!void {
    const match = @import("../stdlib.zig").match_runtime_call_args(call_args, func.arity) catch return Error.ArityMismatch;
    var local_scope = try Scope.fromCallMatch(scope.allocator, scope.out, scope, func.arity, match);
    for (func.body) |st| {
        try interpreter.evalStatement(st, &local_scope);
    }
    const out = local_scope.result() orelse unreachable;
    scope.return_result = out;
}

pub fn length(args: libtype.CallMatch, scope: *Scope) Error!void {
    switch (args.unnamed_args[0]) {
        .array => |elements| {
            scope.return_result =
                .{ .number = .{ .integer = @intCast(elements.len) } };
        },
        .dictionary => |d| {
            scope.return_result =
                .{ .number = .{ .integer = @intCast(d.entries.count()) } };
        },
        else => |v| {
            std.debug.print("ERROR: unexpected case: {s}\n", .{@tagName(v)});
            return Error.InvalidExpressoinType;
        },
    }
}

pub fn _type(args: libtype.CallMatch, scope: *Scope) Error!void {
    std.log.info("in type: was '{s}'", .{@tagName(args.unnamed_args[0])});
    scope.return_result =
        .{ .string = @tagName(args.unnamed_args[0]) };
}

pub fn load_data(args: libtype.CallMatch, scope: *Scope) Error!void {
    const file_path = args.unnamed_args[0];
    const data_format = args.unnamed_args[1];
    std.debug.assert(file_path == .string);
    std.debug.assert(data_format == .string);
    if (std.mem.eql(u8, data_format.string, "lines")) {
        const lines = data.load_lines(file_path.string, scope.allocator) catch |err| {
            std.debug.print("ERROR: loading file failed: {}\n", .{err});
            return Error.NotImplemented;
        };
        defer scope.allocator.free(lines);
        const out = try scope.allocator.alloc(Value, lines.len);
        for (lines, out) |line, *elem| {
            elem.* = .{ .string = line };
        }
        scope.return_result = .{ .array = out };
    } else if (std.mem.eql(u8, data_format.string, "json")) {
        scope.return_result = data.load_json(file_path.string, scope.allocator) catch |err| {
            std.debug.print("ERROR: loading file '{s}' failed: {}\n", .{ file_path.string, err });
            return Error.NotImplemented;
        };
    } else if (std.mem.eql(u8, data_format.string, "csv")) {
        scope.return_result = data.load_csv(file_path.string, scope.allocator) catch |err| {
            std.debug.print("ERROR: loading file '{s}' failed: {}\n", .{ file_path.string, err });
            return Error.NotImplemented;
        };
    } else if (std.mem.eql(u8, data_format.string, "chars")) {
        const dir = std.fs.cwd();
        const file = dir.openFile(file_path.string, .{}) catch |err| {
            std.debug.print("ERROR: loading file '{s}' failed: {}\n", .{ file_path.string, err });
            return Error.NotImplemented;
        };
        const stat = file.stat() catch return Error.IOWrite;
        const chars = file.readToEndAlloc(scope.allocator, stat.size) catch return Error.OutOfMemory;
        scope.return_result = .{ .string = chars };
    } else return Error.FormatNotSupportted;
}

const MAP_FN_INDEX = 1;
const MAP_DATA_INDEX = 0;
fn map_next(iter_data: []Value, scope: *Scope) Error!void {
    std.debug.assert(iter_data[MAP_DATA_INDEX] == .iterator);
    std.debug.assert(iter_data[MAP_FN_INDEX] == .function);
    const tmp = try scope.allocator.alloc(Value, 1);
    defer scope.allocator.free(tmp);
    const args = try scope.allocator.alloc(Value, 1);
    defer scope.allocator.free(args);

    tmp[0] = iter_data[MAP_DATA_INDEX];
    try iter_next(libtype.CallMatch.init(tmp, null, null), scope);
    args[0] = scope.result() orelse unreachable;
    const func = iter_data[MAP_FN_INDEX].function;
    try exec_runtime_function(func, args, scope);
}

fn map_peek(iter_data: []Value, scope: *Scope) Error!void {
    std.debug.assert(iter_data[MAP_DATA_INDEX] == .iterator);
    std.debug.assert(iter_data[MAP_FN_INDEX] == .function);
    const tmp = try scope.allocator.alloc(Value, 1);
    defer scope.allocator.free(tmp);
    const args = try scope.allocator.alloc(Value, 1);
    defer scope.allocator.free(args);

    tmp[0] = iter_data[MAP_DATA_INDEX];
    try iter_peek(libtype.CallMatch.init(tmp, null, null), scope);
    const result = scope.result() orelse unreachable;
    args[0] = result;
    const func = iter_data[MAP_FN_INDEX].function;
    try exec_runtime_function(func, args, scope);
}

fn map_has_next(iter_data: []Value, scope: *Scope) Error!void {
    std.debug.assert(iter_data[MAP_DATA_INDEX] == .iterator);
    std.debug.assert(iter_data[MAP_FN_INDEX] == .function);
    const tmp = try scope.allocator.alloc(Value, 1);
    defer scope.allocator.free(tmp);
    tmp[0] = iter_data[MAP_DATA_INDEX];
    try iter_has_next(libtype.CallMatch.init(tmp, null, null), scope);
}

pub fn map(args: libtype.CallMatch, scope: *Scope) Error!void {
    const elements = args.unnamed_args[0];
    const callable = args.unnamed_args[1];
    std.debug.assert(callable == .function);

    switch (elements) {
        .array => |a| {
            const out = try scope.allocator.alloc(Value, a.len);
            const func = callable.function;
            for (a, out) |e, *t| {
                var call_args = try scope.allocator.alloc(Value, 1);
                defer scope.allocator.free(call_args);
                call_args[0] = e;
                try exec_runtime_function(func, call_args, scope);
                if (scope.result()) |r| {
                    t.* = r;
                } else {
                    return Error.ValueNotFound;
                }
            }
            scope.return_result = .{ .array = out };
        },
        .iterator => {
            const tmp = try scope.allocator.alloc(Value, 2);
            tmp[MAP_DATA_INDEX] = elements;
            tmp[MAP_FN_INDEX] = callable;
            const out = expression.Iterator.initBuiltin(
                &map_next,
                &map_has_next,
                &map_peek,
                tmp,
            );
            scope.return_result = out;
        },
        else => return Error.NotImplemented,
    }
}

const FLATTEN_DATA_INDEX = 0;
const FLATTEN_INTERMEDIATE_INDEX = 1;
fn flatten_iter_has_elements(iter: Value, scope: *Scope) bool {
    if (iter == .iterator) {
        var tmp_array = [1]Value{iter};
        iter_has_next(libtype.CallMatch.init(tmp_array[0..1], null, null), scope) catch return false;
        const tmp = scope.result() orelse unreachable;
        return tmp == .boolean and tmp.boolean;
    }

    return false;
}

fn flatten_next(data_expr: []Value, scope: *Scope) Error!void {
    std.debug.assert(data_expr[FLATTEN_DATA_INDEX] == .iterator);
    if (!flatten_iter_has_elements(data_expr[FLATTEN_INTERMEDIATE_INDEX], scope)) {
        try iter_next(
            libtype.CallMatch.init(data_expr[FLATTEN_DATA_INDEX .. FLATTEN_DATA_INDEX + 1], null, null),
            scope,
        );
        const result = scope.result() orelse unreachable;
        var tmp: [1]Value = .{result};
        try default_iterator(libtype.CallMatch.init(&tmp, null, null), scope);
        data_expr[FLATTEN_INTERMEDIATE_INDEX] = scope.result() orelse unreachable;
    }
    try iter_next(
        libtype.CallMatch.init(
            data_expr[FLATTEN_INTERMEDIATE_INDEX .. FLATTEN_INTERMEDIATE_INDEX + 1],
            null,
            null,
        ),
        scope,
    );
}

fn flatten_peek(data_expr: []Value, scope: *Scope) Error!void {
    std.debug.assert(data_expr[FLATTEN_DATA_INDEX] == .iterator);
    if (!flatten_iter_has_elements(data_expr[FLATTEN_INTERMEDIATE_INDEX], scope)) {
        try iter_next(
            libtype.CallMatch.init(data_expr[FLATTEN_DATA_INDEX .. FLATTEN_DATA_INDEX + 1], null, null),
            scope,
        );
        const result = scope.result() orelse unreachable;
        var tmp: [1]Value = .{result};
        try default_iterator(libtype.CallMatch.init(&tmp, null, null), scope);
        data_expr[FLATTEN_INTERMEDIATE_INDEX] = scope.result() orelse unreachable;
    }
    try iter_peek(
        libtype.CallMatch.init(
            data_expr[FLATTEN_INTERMEDIATE_INDEX .. FLATTEN_INTERMEDIATE_INDEX + 1],
            null,
            null,
        ),
        scope,
    );
}

fn flatten_has_next(data_expr: []Value, scope: *Scope) Error!void {
    std.debug.assert(data_expr[FLATTEN_DATA_INDEX] == .iterator);
    if (data_expr[FLATTEN_INTERMEDIATE_INDEX] == .none) {
        try iter_has_next(
            libtype.CallMatch.init(data_expr[FLATTEN_DATA_INDEX .. FLATTEN_DATA_INDEX + 1], null, null),
            scope,
        );
    } else if (data_expr[FLATTEN_INTERMEDIATE_INDEX] == .iterator) {
        try iter_has_next(
            libtype.CallMatch.init(
                data_expr[FLATTEN_INTERMEDIATE_INDEX .. FLATTEN_INTERMEDIATE_INDEX + 1],
                null,
                null,
            ),
            scope,
        );
        const tmp = scope.result() orelse unreachable;
        if (tmp == .boolean and !tmp.boolean) {
            try iter_has_next(
                libtype.CallMatch.init(data_expr[FLATTEN_DATA_INDEX .. FLATTEN_DATA_INDEX + 1], null, null),
                scope,
            );
        } else {
            scope.return_result = tmp;
        }
    }
}

pub fn flatten(args: libtype.CallMatch, scope: *Scope) Error!void {
    const lists = args.unnamed_args[0];
    switch (lists) {
        .array => |a| {
            const slices = a;
            if (slices.len == 0) {
                scope.return_result = .{ .array = ([0]Value{})[0..] };
            }

            const total_len = blk: {
                var sum: usize = 0;
                for (slices) |slice| sum += if (slice == .array) slice.array.len else 1;
                break :blk sum;
            };

            const buf = try scope.allocator.alloc(Value, total_len);
            errdefer scope.allocator.free(buf);

            var buffer_index: usize = 0;
            for (slices) |elem| {
                if (elem == .array) {
                    for (elem.array) |e| {
                        buf[buffer_index] = e;
                        buffer_index += 1;
                    }
                } else {
                    buf[buffer_index] = elem;
                    buffer_index += 1;
                }
            }

            // No need for shrink since buf is exactly the correct size.
            scope.return_result = .{ .array = buf };
        },
        .iterator => {
            const tmp = try scope.allocator.alloc(Value, 2);
            tmp[FLATTEN_DATA_INDEX] = lists;
            tmp[FLATTEN_INTERMEDIATE_INDEX] = .{ .none = null };
            scope.return_result = expression.Iterator.initBuiltin(
                &flatten_next,
                &flatten_has_next,
                &flatten_peek,
                tmp,
            );
        },
        else => scope.return_result = try lists.clone(),
    }
}

pub fn flatmap(args: libtype.CallMatch, scope: *Scope) Error!void {
    const elements = args.unnamed_args[0];
    const callable = args.unnamed_args[1];
    std.debug.assert(callable == .function);
    switch (elements) {
        .array, .iterator => {
            try map(args, scope);
            const map_result = scope.result() orelse unreachable;
            var tmp_array = [1]Value{map_result};
            try flatten(libtype.CallMatch.init(&tmp_array, null, null), scope);
        },
        else => return Error.NotImplemented,
    }
}

pub fn reduce(args: libtype.CallMatch, scope: *Scope) Error!void {
    const elements = args.unnamed_args[0];
    const callable = args.unnamed_args[1];
    std.debug.assert(callable == .function);
    if (callable.function.arity.args.len != 2) {
        std.debug.print("ERROR: the provided function has {} arguments\n", .{callable.function.arity.args.len});
        std.debug.print("   needed are {}\n", .{2});
        return Error.InvalidExpressoinType;
    }
    const func = callable.function;

    switch (elements) {
        .array => |a| {
            var acc = a[0];
            for (a[1..]) |e| {
                var call_args = try scope.allocator.alloc(Value, 2);
                call_args[0] = acc;
                call_args[1] = e;
                try exec_runtime_function(func, call_args, scope);
                if (scope.result()) |r| {
                    acc = r;
                } else {
                    return Error.ValueNotFound;
                }
                scope.allocator.free(call_args);
            }
            scope.return_result = acc;
        },
        .iterator => {
            try iter_has_next(args, scope);
            var result = scope.result() orelse unreachable;
            std.debug.assert(result == .boolean);
            if (!result.boolean) {
                scope.return_result = .{ .none = null };
                return;
            }
            try iter_next(args, scope);
            var acc = scope.result() orelse unreachable;
            try iter_has_next(args, scope);
            result = scope.result() orelse unreachable;
            std.debug.assert(result == .boolean);
            while (result.boolean) {
                try iter_next(args, scope);
                const e = scope.result() orelse unreachable;
                var call_args = try scope.allocator.alloc(Value, 2);
                defer scope.allocator.free(call_args);
                call_args[0] = acc;
                call_args[1] = e;
                try exec_runtime_function(func, call_args, scope);
                if (scope.result()) |r| {
                    acc = r;
                } else {
                    return Error.ValueNotFound;
                }
                try iter_has_next(args, scope);
                result = scope.result() orelse unreachable;
            }
            scope.return_result = try acc.clone();
        },
        else => return Error.NotImplemented,
    }
}

const GROUP_BY_FN_INDEX = 1;
const GROUP_BY_DATA_INDEX = 0;
const GROUP_BY_SEEN_INDEX = 2;
const GROUP_BY_TEMP_INDEX = 3;
fn group_by_next(data_expr: []Value, scope: *Scope) Error!void {
    const elements = data_expr;
    std.debug.assert(elements[GROUP_BY_FN_INDEX] == .function);
    std.debug.assert(elements[GROUP_BY_DATA_INDEX] == .iterator);
    try iter_peek(
        libtype.CallMatch.init(elements[GROUP_BY_DATA_INDEX .. GROUP_BY_DATA_INDEX + 1], null, null),
        scope,
    );
    elements[GROUP_BY_TEMP_INDEX] = scope.result() orelse unreachable;
    try exec_runtime_function(
        elements[GROUP_BY_FN_INDEX].function,
        elements[GROUP_BY_TEMP_INDEX .. GROUP_BY_TEMP_INDEX + 1],
        scope,
    );
    elements[GROUP_BY_TEMP_INDEX] = scope.result() orelse unreachable;
    try array_contains(elements[GROUP_BY_SEEN_INDEX .. GROUP_BY_SEEN_INDEX + 2], scope);
    var result = scope.result() orelse unreachable;
    while (result.boolean) {
        try iter_next(
            libtype.CallMatch.init(elements[GROUP_BY_DATA_INDEX .. GROUP_BY_DATA_INDEX + 1], null, null),
            scope,
        );
        elements[GROUP_BY_TEMP_INDEX] = scope.result() orelse unreachable;
        try exec_runtime_function(
            elements[GROUP_BY_FN_INDEX].function,
            elements[GROUP_BY_TEMP_INDEX .. GROUP_BY_TEMP_INDEX + 1],
            scope,
        );
        elements[GROUP_BY_TEMP_INDEX] = scope.result() orelse unreachable;
        try array_contains(elements[GROUP_BY_SEEN_INDEX .. GROUP_BY_SEEN_INDEX + 2], scope);
        result = scope.result() orelse unreachable;
    }

    const filter_fn = try equal_to_key(
        elements[GROUP_BY_FN_INDEX],
        elements[GROUP_BY_TEMP_INDEX],
        scope,
    );
    const filter_tmp = try scope.allocator.alloc(Value, 2);
    const tmp_iter = try elements[GROUP_BY_DATA_INDEX].clone();
    filter_tmp[0] = tmp_iter;
    filter_tmp[1] = filter_fn;
    try filter(libtype.CallMatch.init(filter_tmp, null, null), scope);
    const filter_iter = scope.result() orelse unreachable;
    var entries = ValueMap.init(scope.allocator);
    try entries.put(.{ .string = "key" }, try elements[GROUP_BY_TEMP_INDEX].clone());
    try entries.put(.{ .string = "value" }, filter_iter);
    try array_append(elements[GROUP_BY_SEEN_INDEX .. GROUP_BY_SEEN_INDEX + 2], scope);
    elements[GROUP_BY_SEEN_INDEX] = scope.result() orelse unreachable;
    try iter_next(
        libtype.CallMatch.init(elements[GROUP_BY_DATA_INDEX .. GROUP_BY_DATA_INDEX + 1], null, null),
        scope,
    );
    scope.return_result = .{ .dictionary = .{ .entries = entries } };
}

fn equal_to_key(groupper: Value, key: Value, scope: *Scope) !expression.Value {
    const tmp = try expression.Identifier.init(scope.allocator, "tmp");
    const id = try expression.Identifier.init(scope.allocator, "x");
    var tmp_key: Expression = .{ .value = key };
    const tmp_group: Expression = .{ .value = groupper };
    const bin = try expression.BinaryOp.init(
        scope.allocator,
        .{ .compare = .Equal },
        &tmp_key,
        tmp,
    );
    const fn_call = try expression.FunctionCall.init(
        scope.allocator,
        &tmp_group,
        id[0..1],
    );
    const args = try scope.allocator.alloc(expression.Identifier, 1);
    args[0] = .{ .name = "x" };
    const arity = expression.Function.Arity{ .args = args };
    const sts = try scope.allocator.alloc(Statement, 2);
    sts[0] = .{ .assignment = .{ .varName = tmp.identifier, .value = fn_call } };
    sts[1] = .{ .@"return" = .{ .value = bin } };
    return expression.Function.init(arity, sts);
}

fn group_by_peek(data_expr: []Value, scope: *Scope) Error!void {
    const elements = data_expr;
    std.debug.assert(elements[GROUP_BY_FN_INDEX] == .function);
    std.debug.assert(elements[GROUP_BY_DATA_INDEX] == .iterator);
    try iter_peek(
        libtype.CallMatch.init(elements[GROUP_BY_DATA_INDEX .. GROUP_BY_DATA_INDEX + 1], null, null),
        scope,
    );
    elements[GROUP_BY_TEMP_INDEX] = scope.result() orelse unreachable;
    try exec_runtime_function(
        elements[GROUP_BY_FN_INDEX].function,
        elements[GROUP_BY_TEMP_INDEX .. GROUP_BY_TEMP_INDEX + 1],
        scope,
    );
    elements[GROUP_BY_TEMP_INDEX] = scope.result() orelse unreachable;
    const filter_fn = try equal_to_key(
        try elements[GROUP_BY_FN_INDEX].clone(),
        try elements[GROUP_BY_TEMP_INDEX].clone(),
        scope,
    );
    const filter_tmp = try scope.allocator.alloc(Value, 2);
    const tmp_iter = try elements[GROUP_BY_DATA_INDEX].clone();
    filter_tmp[0] = tmp_iter;
    filter_tmp[1] = filter_fn;
    try filter(libtype.CallMatch.init(filter_tmp, null, null), scope);
    const filter_iter = scope.result() orelse unreachable;
    var entries = ValueMap.init(scope.allocator);
    try entries.put(.{ .string = "key" }, try elements[GROUP_BY_TEMP_INDEX].clone());
    try entries.put(.{ .string = "value" }, filter_iter);
    scope.return_result = .{ .dictionary = .{ .entries = entries } };
}

fn group_by_has_next(data_expr: []Value, scope: *Scope) Error!void {
    const elements = data_expr;
    std.debug.assert(elements[GROUP_BY_FN_INDEX] == .function);
    std.debug.assert(elements[GROUP_BY_DATA_INDEX] == .iterator);
    const tmp_iter = try elements[GROUP_BY_DATA_INDEX].clone();
    var tmp_args: [1]Value = .{tmp_iter};
    try iter_has_next(libtype.CallMatch.init(&tmp_args, null, null), scope);
    var result = scope.result() orelse unreachable;
    if (result == .boolean and !result.boolean) {
        scope.return_result = .{ .boolean = false };
        return;
    }
    try iter_peek(libtype.CallMatch.init(&tmp_args, null, null), scope);
    elements[GROUP_BY_TEMP_INDEX] = scope.result() orelse unreachable;
    try exec_runtime_function(
        elements[GROUP_BY_FN_INDEX].function,
        elements[GROUP_BY_TEMP_INDEX .. GROUP_BY_TEMP_INDEX + 1],
        scope,
    );
    elements[GROUP_BY_TEMP_INDEX] = scope.result() orelse unreachable;
    try array_contains(elements[GROUP_BY_SEEN_INDEX .. GROUP_BY_SEEN_INDEX + 2], scope);
    result = scope.result() orelse unreachable;
    while (result == .boolean and result.boolean) {
        try iter_has_next(libtype.CallMatch.init(&tmp_args, null, null), scope);
        result = scope.result() orelse unreachable;
        if (result == .boolean and !result.boolean) {
            scope.return_result = .{ .boolean = false };
            return;
        }
        try iter_next(libtype.CallMatch.init(&tmp_args, null, null), scope);
        elements[GROUP_BY_TEMP_INDEX] = scope.result() orelse unreachable;
        try exec_runtime_function(
            elements[GROUP_BY_FN_INDEX].function,
            elements[GROUP_BY_TEMP_INDEX .. GROUP_BY_TEMP_INDEX + 1],
            scope,
        );
        elements[GROUP_BY_TEMP_INDEX] = scope.result() orelse unreachable;
        try array_contains(elements[GROUP_BY_SEEN_INDEX .. GROUP_BY_SEEN_INDEX + 2], scope);
        result = scope.result() orelse unreachable;
    }

    scope.return_result = .{ .boolean = true };
}

pub fn group_by(args: libtype.CallMatch, scope: *Scope) Error!void {
    const elements = args.unnamed_args[0];
    const callable = args.unnamed_args[1];
    std.debug.assert(callable == .function);
    switch (elements) {
        .array => |a| {
            var out_map = ValueMap.init(scope.allocator);
            // TODO: hard coded slice size. May overfilled by 'callable' if it returns large arrays/dictionaries
            var buffer: [2048]u8 = undefined;
            var fixedStream = std.io.fixedBufferStream(&buffer);
            const writer = fixedStream.writer().any();
            for (a) |elem| {
                fixedStream.reset();
                const call_args = try scope.allocator.alloc(Value, 1);
                defer scope.allocator.free(call_args);
                call_args[0] = elem;
                try exec_runtime_function(callable.function, call_args, scope);
                const result = scope.result() orelse return Error.ValueNotFound;
                var out_scope = Scope.empty(scope.allocator, writer);
                // NOTE: praying that only simple values are printed
                try printValue(result, &out_scope);
                const written = .{ .string = try scope.allocator.dupe(u8, fixedStream.getWritten()) };
                if (out_map.getPtr(written)) |value| {
                    const tmp = value.array;
                    const new = try scope.allocator.alloc(Value, tmp.len + 1);
                    @memcpy(new[0..tmp.len], tmp);
                    new[tmp.len] = elem;
                    value.* = .{ .array = new };
                    scope.allocator.free(tmp);
                } else {
                    const new = try scope.allocator.alloc(Value, 1);
                    new[0] = elem;
                    try out_map.put(written, .{ .array = new });
                }
            }

            scope.return_result = .{ .dictionary = .{ .entries = out_map } };
        },
        .iterator => {
            const tmp = try scope.allocator.alloc(Value, 4);
            tmp[GROUP_BY_DATA_INDEX] = elements;
            tmp[GROUP_BY_FN_INDEX] = callable;
            tmp[GROUP_BY_SEEN_INDEX] = .{ .array = &[0]Value{} };
            scope.return_result = expression.Iterator.initBuiltin(
                &group_by_next,
                &group_by_has_next,
                &group_by_peek,
                tmp,
            );
        },
        else => |e| {
            std.debug.print("ERROR: unable to group: '{s}' has no elements or is a single value\n", .{@tagName(e)});
            return Error.InvalidExpressoinType;
        },
    }
}

const Context = struct {
    operation: *const fn (OutType, bool) OutType,
    initial: OutType,

    const OutType = union(enum) {
        number: i64,
        boolean: bool,
    };
};

fn count_op(acc: Context.OutType, value: bool) Context.OutType {
    std.debug.assert(acc == .number);
    return .{ .number = acc.number + @intFromBool(value) };
}
const Count_context: Context = .{
    .operation = &count_op,
    .initial = .{ .number = 0 },
};

fn check_all_op(acc: Context.OutType, value: bool) Context.OutType {
    std.debug.assert(acc == .boolean);
    return .{ .boolean = acc.boolean and value };
}
const All_context: Context = .{
    .operation = &check_all_op,
    .initial = .{ .boolean = true },
};

fn check_any_op(acc: Context.OutType, value: bool) Context.OutType {
    std.debug.assert(acc == .boolean);
    return .{ .boolean = acc.boolean or value };
}
const Any_context: Context = .{
    .operation = &check_any_op,
    .initial = .{ .boolean = false },
};

fn check_none_op(acc: Context.OutType, value: bool) Context.OutType {
    std.debug.assert(acc == .boolean);
    return .{ .boolean = acc.boolean and !value };
}
const None_context: Context = .{
    .operation = &check_none_op,
    .initial = .{ .boolean = true },
};

fn check(context: Context, args: libtype.CallMatch, scope: *Scope) Error!void {
    const elements = args.unnamed_args[0];
    const callable = args.unnamed_args[1];

    std.debug.assert(callable == .function);
    if (callable.function.arity.args.len != 1) {
        std.debug.print("ERROR: the provided function has {} arguments\n", .{callable.function.arity.args.len});
        std.debug.print("   needed are {}\n", .{1});
        std.process.exit(1);
    }
    const func = callable.function;

    switch (elements) {
        .array => |a| {
            var acc: Context.OutType = context.initial;
            for (a) |e| {
                var call_args = try scope.allocator.alloc(Value, 1);
                defer scope.allocator.free(call_args);
                call_args[0] = e;
                try exec_runtime_function(func, call_args, scope);
                if (scope.result()) |r| {
                    if (r == .boolean) {
                        acc = context.operation(acc, r.boolean);
                    } else if (r != .boolean) {
                        std.debug.print("ERROR: returned value of function is not a boolean\n", .{});
                        return Error.InvalidExpressoinType;
                    }
                } else {
                    return Error.ValueNotFound;
                }
            }
            scope.return_result = switch (acc) {
                .boolean => |v| .{ .boolean = v },
                .number => |v| .{ .number = .{ .integer = v } },
            };
        },
        .iterator => {
            var acc: Context.OutType = context.initial;
            const elems = try elements.clone();
            var tmp_args: [1]Value = .{elems};
            try iter_has_next(libtype.CallMatch.init(&tmp_args, null, null), scope);
            var condition = scope.result() orelse unreachable;
            var call_args = try scope.allocator.alloc(Value, 1);
            defer scope.allocator.free(call_args);
            while (condition == .boolean and condition.boolean) {
                try iter_next(libtype.CallMatch.init(&tmp_args, null, null), scope);
                call_args[0] = scope.result() orelse unreachable;
                try exec_runtime_function(func, call_args, scope);
                if (scope.result()) |r| {
                    if (r == .boolean) {
                        acc = context.operation(acc, r.boolean);
                    } else if (r != .boolean) {
                        std.debug.print("ERROR: returned value of function is not a boolean\n", .{});
                        return Error.InvalidExpressoinType;
                    }
                } else {
                    return Error.ValueNotFound;
                }
                try iter_has_next(libtype.CallMatch.init(&tmp_args, null, null), scope);
                condition = scope.result() orelse unreachable;
            }
            scope.return_result = switch (acc) {
                .boolean => |v| .{ .boolean = v },
                .number => |v| .{ .number = .{ .integer = v } },
            };
        },
        else => return Error.NotImplemented,
    }
}

pub fn count(args: libtype.CallMatch, scope: *Scope) Error!void {
    try check(Count_context, args, scope);
}

pub fn check_all(args: libtype.CallMatch, scope: *Scope) Error!void {
    try check(All_context, args, scope);
}

pub fn check_any(args: libtype.CallMatch, scope: *Scope) Error!void {
    try check(Any_context, args, scope);
}

pub fn check_none(args: libtype.CallMatch, scope: *Scope) Error!void {
    try check(None_context, args, scope);
}

const FILTER_FN_INDEX = 1;
const FILTER_DATA_INDEX = 0;
fn filter_next(data_expr: []Value, scope: *Scope) Error!void {
    const elements = data_expr;
    std.debug.assert(elements[FILTER_FN_INDEX] == .function);
    std.debug.assert(elements[FILTER_DATA_INDEX] == .iterator);
    const iter = elements[FILTER_DATA_INDEX];
    var tmp_args: [1]Value = .{iter};
    const func = elements[FILTER_FN_INDEX].function;
    try iter_has_next(libtype.CallMatch.init(&tmp_args, null, null), scope);
    var result = scope.result() orelse unreachable;
    if (!result.boolean) {
        scope.return_result = result;
        return;
    }

    try iter_next(libtype.CallMatch.init(&tmp_args, null, null), scope);
    var out = scope.result() orelse unreachable;
    tmp_args = .{out};
    try exec_runtime_function(func, &tmp_args, scope);
    result = scope.result() orelse unreachable;
    while (result == .boolean and !result.boolean) {
        tmp_args = .{iter};
        try iter_has_next(libtype.CallMatch.init(&tmp_args, null, null), scope);
        result = scope.result() orelse unreachable;
        if (!result.boolean) {
            scope.return_result = .{ .none = null };
            return;
        }

        try iter_next(libtype.CallMatch.init(&tmp_args, null, null), scope);
        out = scope.result() orelse unreachable;
        tmp_args = .{out};
        try exec_runtime_function(func, &tmp_args, scope);
        result = scope.result() orelse unreachable;
    }
    scope.return_result = out;
}

fn filter_peek(data_expr: []Value, scope: *Scope) Error!void {
    const elements = data_expr;
    std.debug.assert(elements[FILTER_FN_INDEX] == .function);
    std.debug.assert(elements[FILTER_DATA_INDEX] == .iterator);
    var iter: [1]Value = .{elements[FILTER_DATA_INDEX]};
    var tmp_args: [1]Value = iter;
    const func = elements[FILTER_FN_INDEX].function;
    try iter_has_next(libtype.CallMatch.init(&iter, null, null), scope);
    var result = scope.result() orelse unreachable;
    if (!result.boolean) {
        scope.return_result = result;
        return;
    }

    try iter_peek(libtype.CallMatch.init(&tmp_args, null, null), scope);
    tmp_args = .{scope.result() orelse unreachable};
    try exec_runtime_function(func, &tmp_args, scope);
    result = scope.result() orelse unreachable;
    while (result == .boolean and !result.boolean) {
        try iter_next(libtype.CallMatch.init(&iter, null, null), scope);
        try iter_has_next(libtype.CallMatch.init(&iter, null, null), scope);
        result = scope.result() orelse unreachable;
        if (!result.boolean) {
            scope.return_result = .{ .none = null };
            return;
        }

        try iter_peek(libtype.CallMatch.init(&iter, null, null), scope);
        tmp_args = .{scope.result() orelse unreachable};
        try exec_runtime_function(func, &tmp_args, scope);
        result = scope.result() orelse unreachable;
    }
    scope.return_result = tmp_args[0];
}

fn filter_has_next(data_expr: []Value, scope: *Scope) Error!void {
    const elements = data_expr;
    std.debug.assert(elements[FILTER_FN_INDEX] == .function);
    std.debug.assert(elements[FILTER_DATA_INDEX] == .iterator);
    var iter: [1]Value = .{elements[FILTER_DATA_INDEX]};
    var tmp_args: [1]Value = undefined;
    const func = elements[FILTER_FN_INDEX].function;
    try iter_has_next(libtype.CallMatch.init(&iter, null, null), scope);
    var result = scope.result() orelse unreachable;
    if (!result.boolean) {
        scope.return_result = result;
        return;
    }

    try iter_next(libtype.CallMatch.init(&iter, null, null), scope);
    tmp_args = .{scope.result() orelse unreachable};
    try exec_runtime_function(func, &tmp_args, scope);
    result = scope.result() orelse unreachable;
    while (result == .boolean and !result.boolean) {
        try iter_has_next(libtype.CallMatch.init(&iter, null, null), scope);
        result = scope.result() orelse unreachable;
        if (!result.boolean) {
            scope.return_result = result;
            return;
        }

        try iter_next(libtype.CallMatch.init(&iter, null, null), scope);
        tmp_args = .{scope.result() orelse unreachable};
        try exec_runtime_function(func, &tmp_args, scope);
        result = scope.result() orelse unreachable;
    }
    scope.return_result = result;
}

pub fn filter(args: libtype.CallMatch, scope: *Scope) Error!void {
    const elements = args.unnamed_args[0];
    const callable = args.unnamed_args[1];
    std.debug.assert(callable == .function);

    switch (elements) {
        .array => |a| {
            try count(args, scope);
            const element_count = (scope.result() orelse unreachable).number.integer;
            const tmp = try scope.allocator.alloc(Value, @intCast(element_count));
            var current_index: usize = 0;
            const func = callable.function;
            for (a) |e| {
                var call_args = try scope.allocator.alloc(Value, 1);
                defer scope.allocator.free(call_args);
                call_args[0] = e;
                try exec_runtime_function(func, call_args, scope);
                if (scope.result()) |r| {
                    if (r == .boolean and r.boolean) {
                        tmp[current_index] = e;
                        current_index += 1;
                    }
                } else {
                    return Error.ValueNotFound;
                }
            }
            scope.return_result = .{ .array = tmp };
        },
        .iterator => {
            const tmp = try scope.allocator.alloc(Value, 2);
            tmp[FILTER_DATA_INDEX] = elements;
            tmp[FILTER_FN_INDEX] = callable;
            scope.return_result = expression.Iterator.initBuiltin(
                &filter_next,
                &filter_has_next,
                &filter_peek,
                tmp,
            );
        },
        else => return Error.NotImplemented,
    }
}

fn zip_next(data_expr: []Value, scope: *Scope) Error!void {
    const local_data = data_expr;
    const out = try scope.allocator.alloc(Value, local_data.len);
    for (local_data, 0..) |*iter, index| {
        try iter_next(libtype.CallMatch.init(iter[0..1], null, null), scope);
        const value = scope.result() orelse unreachable;
        out[index] = value;
    }
    scope.return_result = .{ .array = out };
}

fn zip_peek(data_expr: []Value, scope: *Scope) Error!void {
    const local_data = data_expr;
    const out = try scope.allocator.alloc(Value, local_data.len);
    for (local_data, 0..) |*iter, index| {
        try iter_peek(libtype.CallMatch.init(iter[0..1], null, null), scope);
        const value = scope.result() orelse unreachable;
        out[index] = value;
    }
    scope.return_result = .{ .array = out };
}

fn zip_has_next(data_expr: []Value, scope: *Scope) Error!void {
    const local_data = data_expr;
    var all_true = true;
    for (local_data) |*iter| {
        try iter_has_next(libtype.CallMatch.init(iter[0..1], null, null), scope);
        const condition = scope.result() orelse unreachable;
        std.debug.assert(condition == .boolean);
        all_true = all_true and condition.boolean;
    }
    scope.return_result = .{ .boolean = all_true };
}

pub fn zip(args: libtype.CallMatch, scope: *Scope) Error!void {
    const left_elements = args.unnamed_args[0];
    const right_elements = args.unnamed_args[1];

    if (left_elements == .array and right_elements == .array) {
        const left = left_elements.array;
        const right = right_elements.array;
        const element_count = if (left.len < right.len) left.len else right.len;
        const tmp = try scope.allocator.alloc(Value, element_count);
        for (left[0..element_count], right[0..element_count], tmp) |l, r, *t| {
            const out = try scope.allocator.alloc(Value, 2);
            out[0] = l;
            out[1] = r;
            t.* = .{ .array = out };
        }
        scope.return_result = .{ .array = tmp };
        return;
    }

    if (left_elements == .iterator and right_elements == .iterator) {
        scope.return_result = expression.Iterator.initBuiltin(
            &zip_next,
            &zip_has_next,
            &zip_peek,
            args.unnamed_args,
        );
        return;
    }

    return Error.NotImplemented;
}

fn swap(left: *Value, right: *Value) void {
    const tmp = left.*;
    left.* = right.*;
    right.* = tmp;
}

fn partition(elements: []Value, binary_op: expression.Function, scope: *Scope) Error!usize {
    var pivot = elements.len - 1;
    var left: usize = 0;
    while (left < pivot) {
        var call_args = try scope.allocator.alloc(Value, 2);
        defer scope.allocator.free(call_args);
        call_args[0] = elements[left];
        call_args[1] = elements[pivot];
        try exec_runtime_function(binary_op, call_args, scope);
        const result = scope.result() orelse return Error.ValueNotFound;
        if (result == .number and result.number.asFloat() == -1) {
            left += 1;
        } else if (result == .boolean and result.boolean) {
            left += 1;
        } else if (result != .number and result != .boolean) {
            return Error.InvalidExpressoinType;
        } else {
            swap(&elements[left], &elements[pivot]);
            if (left != pivot - 1)
                swap(&elements[pivot - 1], &elements[left]);
            pivot -= 1;
        }
    }
    return pivot;
}

fn sort_impl(elements: []Value, binary_op: expression.Function, scope: *Scope) Error!void {
    if (elements.len < 2) return;
    const partition_point = try partition(elements, binary_op, scope);
    const left = elements[0..partition_point];
    const right = elements[partition_point + 1 .. elements.len];
    try sort_impl(left, binary_op, scope);
    try sort_impl(right, binary_op, scope);
}

pub fn sort(args: libtype.CallMatch, scope: *Scope) Error!void {
    const elements = args.unnamed_args[0];
    const callable = args.unnamed_args[1];
    std.debug.assert(callable == .function);
    std.debug.assert(callable.function.arity.args.len == 2);

    switch (elements) {
        .array => |a| {
            try sort_impl(a, callable.function, scope);
            scope.return_result = .{ .array = a };
        },
        else => |e| {
            std.debug.print("ERROR: `sort` is not defined for '{s}'\n", .{@tagName(e)});
            return Error.InvalidExpressoinType;
        },
    }
}

pub fn last(args: libtype.CallMatch, scope: *Scope) Error!void {
    const elements = args.unnamed_args[0];
    const callback = args.unnamed_args[1];
    const default_value = args.unnamed_args[2];
    std.debug.assert(callback == .function);

    const func = callback.function;
    switch (elements) {
        .array => |a| {
            var iter = std.mem.reverseIterator(a);
            while (iter.next()) |e| {
                var call_args = try scope.allocator.alloc(Value, 1);
                defer scope.allocator.free(call_args);
                call_args[0] = e;
                try exec_runtime_function(func, call_args, scope);
                if (scope.result()) |r| {
                    if (r == .boolean and r.boolean) {
                        scope.return_result = try e.clone();
                        return;
                    }
                } else {
                    return Error.ValueNotFound;
                }
            }
            scope.return_result = try default_value.clone();
        },
        .iterator => {
            try iter_has_next(args, scope);
            var condition = scope.result() orelse unreachable;
            var result: ?Value = null;
            while (condition == .boolean and condition.boolean) {
                try iter_next(args, scope);
                const tmp = scope.result() orelse unreachable;
                var call_args = try scope.allocator.alloc(Value, 1);
                defer scope.allocator.free(call_args);
                call_args[0] = tmp;
                try exec_runtime_function(func, call_args, scope);
                if (scope.result()) |r| {
                    if (r == .boolean and r.boolean) {
                        result = tmp;
                    }
                } else {
                    return Error.ValueNotFound;
                }
                try iter_has_next(args, scope);
                condition = scope.result() orelse unreachable;
            }
            scope.return_result = if (result) |r| r else try default_value.clone();
        },
        else => return Error.NotImplemented,
    }
}

pub fn first(args: libtype.CallMatch, scope: *Scope) Error!void {
    const elements = args.unnamed_args[0];
    const callback = args.unnamed_args[1];
    const default_value = args.unnamed_args[2];
    std.debug.assert(callback == .function);

    const func = callback.function;
    switch (elements) {
        .array => |items| {
            for (items) |e| {
                var call_args = try scope.allocator.alloc(Value, 1);
                defer scope.allocator.free(call_args);
                call_args[0] = e;
                try exec_runtime_function(func, call_args, scope);
                if (scope.result()) |r| {
                    if (r == .boolean and r.boolean) {
                        scope.return_result = try e.clone();
                        return;
                    }
                } else {
                    return Error.ValueNotFound;
                }
            }
            scope.return_result = try default_value.clone();
        },
        .iterator => {
            var elems = [1]Value{elements};
            try iter_has_next(libtype.CallMatch.init(elems[0..1], null, null), scope);
            var condition = scope.result() orelse unreachable;
            var call_args = try scope.allocator.alloc(Value, 1);
            defer scope.allocator.free(call_args);
            while (condition == .boolean and condition.boolean) {
                try iter_next(libtype.CallMatch.init(elems[0..1], null, null), scope);
                const tmp = scope.result() orelse unreachable;
                call_args[0] = tmp;
                try exec_runtime_function(func, call_args, scope);
                if (scope.result()) |r| {
                    if (r == .boolean and r.boolean) {
                        scope.return_result = try tmp.clone();
                        return;
                    }
                } else {
                    return Error.ValueNotFound;
                }
                try iter_has_next(libtype.CallMatch.init(elems[0..1], null, null), scope);
                condition = scope.result() orelse unreachable;
            }
            scope.return_result = try default_value.clone();
        },
        else => return Error.NotImplemented,
    }
}

pub fn print(args: libtype.CallMatch, scope: *Scope) Error!void {
    if (args.var_args) |vars| {
        var has_printed = false;
        for (vars) |*value| {
            if (has_printed) {
                scope.out.print(" ", .{}) catch return Error.IOWrite;
            } else has_printed = true;
            try printValue(value.*, scope);
        }
        scope.out.print("\n", .{}) catch return Error.IOWrite;
    } else {
        scope.out.print("\n", .{}) catch return Error.IOWrite;
    }
}

pub fn write(args: libtype.CallMatch, scope: *Scope) Error!void {
    if (args.var_args) |vars| {
        var has_printed = false;
        for (vars) |*value| {
            if (has_printed) {
                scope.out.print(" ", .{}) catch return Error.IOWrite;
            } else has_printed = true;
            try printValue(value.*, scope);
        }
    }
}

fn printValue(value: Value, scope: *Scope) Error!void {
    switch (value) {
        .number => |n| {
            if (n == .float) {
                scope.out.print("{d}", .{n.float}) catch return Error.IOWrite;
            } else scope.out.print("{d}", .{n.integer}) catch return Error.IOWrite;
        },
        .boolean => |v| {
            scope.out.print("{}", .{v}) catch return Error.IOWrite;
        },
        .string => |v| {
            scope.out.print("{s}", .{v}) catch return Error.IOWrite;
        },
        .array => |vs| {
            scope.out.print("[", .{}) catch return Error.IOWrite;
            var has_printed = false;
            for (vs) |val| {
                if (has_printed) {
                    scope.out.print(", ", .{}) catch return Error.IOWrite;
                } else has_printed = true;
                try printValue(val, scope);
            }
            scope.out.print("]", .{}) catch return Error.IOWrite;
        },
        .dictionary => |vs| {
            _ = scope.out.write("{") catch return Error.IOWrite;
            var has_printed = false;
            var iter = vs.entries.iterator();
            while (iter.next()) |val| {
                if (has_printed) {
                    _ = scope.out.write(", ") catch return Error.IOWrite;
                } else has_printed = true;
                try printValue(val.key_ptr.*, scope);
                _ = scope.out.write(": ") catch return Error.IOWrite;
                const v = vs.entries.get(val.key_ptr.*) orelse unreachable;
                try printValue(v, scope);
            }
            _ = scope.out.write("}") catch return Error.IOWrite;
        },
        .formatted_string => |f| {
            try evalFormattedString(f, scope);
            const string = scope.result() orelse unreachable;
            std.debug.assert(string == .string);
            scope.out.print("{s}", .{string.string}) catch return Error.IOWrite;
        },
        .iterator => {
            scope.out.print("<{s}>", .{@tagName(value)}) catch return Error.IOWrite;
        },
        .none => _ = scope.out.write("none") catch return Error.IOWrite,
        else => |v| {
            std.debug.print("TODO: printing of value: {s}\n", .{@tagName(v)});
            return Error.NotImplemented;
        },
    }
}

fn checkCurlyParenBalance(string: []const u8) Error!void {
    var depth: usize = 0;
    var was_open_last = false;
    for (string) |char| {
        if (char == '{' and !was_open_last) {
            depth += 1;
            was_open_last = true;
        }

        if (char == '}' and depth > 0 and was_open_last) {
            depth -= 1;
            was_open_last = false;
        } else if (char == '}' and depth == 0) {
            return Error.MalformedFormattedString;
        }
    }
    if (depth != 0) {
        return Error.MalformedFormattedString;
    }
}

fn evalFormattedString(string: []const u8, scope: *Scope) Error!void {
    try checkCurlyParenBalance(string);
    var splitter = std.mem.splitAny(u8, string, "{}");
    var is_inner_expr = false;
    var acc = std.ArrayList([]const u8).init(scope.allocator);
    defer acc.deinit();
    while (splitter.next()) |part| {
        if (is_inner_expr) {
            var parser = Parser.init(part, scope.allocator);
            const value = parser.parseExpression(0) catch
                return Error.MalformedFormattedString;

            try interpreter.evalExpression(value, scope);
            const result = scope.result() orelse unreachable;
            var tmp_array = [1]Value{result};
            try conversions.toString(
                libtype.CallMatch.init(tmp_array[0..1], null, null),
                scope,
            );
            const str = scope.result() orelse unreachable;
            std.debug.assert(str == .string);
            try acc.append(str.string);
        } else {
            try acc.append(part);
        }
        is_inner_expr = !is_inner_expr;
    }
    const tmp = try std.mem.join(scope.allocator, "", acc.items);
    scope.return_result = .{ .string = tmp };
}

pub fn string_trim(args: libtype.CallMatch, scope: *Scope) Error!void {
    std.debug.assert(args.unnamed_args[0] == .string);
    if (args.unnamed_args[0].string.len == 0) return;

    const string = args.unnamed_args[0].string;
    var front_index: usize = 0;
    var back_index: usize = string.len - 1;
    while (std.ascii.isWhitespace(string[front_index])) : (front_index += 1) {}
    while (std.ascii.isWhitespace(string[back_index])) : (back_index -= 1) {}
    const size = back_index - front_index + 1;
    if (size > 0) {
        const out = try scope.allocator.alloc(u8, size);
        for (out, string[front_index .. back_index + 1]) |*tmp, value| {
            tmp.* = value;
        }
        scope.return_result = .{ .string = out };
    } else {
        scope.return_result = .{ .string = "" };
    }
}

pub fn string_split(args: libtype.CallMatch, scope: *Scope) Error!void {
    std.debug.assert(args.unnamed_args[0] == .string);
    std.debug.assert(args.unnamed_args[1] == .string);
    if (args.unnamed_args[1].string.len == 0) {
        scope.return_result = try args.unnamed_args[0].clone();
        return;
    }
    var iter = std.mem.splitSequence(
        u8,
        args.unnamed_args[0].string,
        args.unnamed_args[1].string,
    );
    var out = std.ArrayList(Value).init(scope.allocator);
    while (iter.next()) |str| {
        const tmp = .{ .string = str };
        try out.append(tmp);
    }
    scope.return_result = .{ .array = try out.toOwnedSlice() };
}

pub fn string_count(args: libtype.CallMatch, scope: *Scope) Error!void {
    std.debug.assert(args.unnamed_args[0] == .string);
    std.debug.assert(args.unnamed_args[1] == .string);
    const source = args.unnamed_args[0].string;
    const needle = args.unnamed_args[1].string;
    if (needle.len > 0) {
        const out: i64 = @truncate(@as(i128, std.mem.count(u8, source, needle)));
        scope.return_result = .{ .number = .{ .integer = out } };
    } else scope.return_result = .{ .number = .{ .integer = 0 } };
}

pub fn string_repeat(args: libtype.CallMatch, scope: *Scope) Error!void {
    std.debug.assert(args.unnamed_args[0] == .string);
    std.debug.assert(args.unnamed_args[1] == .number);
    const reps = args.unnamed_args[1].number;
    const source = args.unnamed_args[0].string;
    if (reps != .integer) {
        std.log.err("in 'repeat': can not repeat a string in a fractional amount", .{});
        return Error.InvalidExpressoinType;
    }
    const repeats = @as(usize, @intCast(reps.integer));
    const out = try scope.allocator.alloc(u8, repeats * source.len);
    for (0..repeats) |index| {
        const start = index * source.len;
        const end = (index + 1) * source.len;
        @memcpy(out[start..end], source);
    }
    scope.return_result = .{ .string = out };
}

pub fn string_starts_with(args: libtype.CallMatch, scope: *Scope) Error!void {
    std.debug.assert(args.unnamed_args[0] == .string);
    std.debug.assert(args.unnamed_args[1] == .string);
    scope.return_result = .{ .boolean = std.mem.startsWith(
        u8,
        args.unnamed_args[0].string,
        args.unnamed_args[1].string,
    ) };
}

pub fn string_ends_with(args: libtype.CallMatch, scope: *Scope) Error!void {
    std.debug.assert(args.unnamed_args[0] == .string);
    std.debug.assert(args.unnamed_args[1] == .string);
    scope.return_result = .{ .boolean = std.mem.endsWith(
        u8,
        args.unnamed_args[0].string,
        args.unnamed_args[1].string,
    ) };
}

const DEFAULT_INDEX = 1;
const DEFAULT_DATA_INDEX = 0;
fn default_next(data_expr: []Value, scope: *Scope) Error!void {
    const local_data = data_expr;
    switch (local_data[DEFAULT_DATA_INDEX]) {
        .array => |a| {
            std.debug.assert(local_data[DEFAULT_INDEX] == .number);
            std.debug.assert(local_data[DEFAULT_INDEX].number == .integer);
            const index = local_data[DEFAULT_INDEX];
            const i: usize = @intCast(index.number.integer);
            scope.return_result = try a[i].clone();
            local_data[DEFAULT_INDEX] = .{ .number = .{ .integer = @as(i64, @intCast(i)) + 1 } };
        },
        .dictionary => return Error.NotImplemented,
        else => return Error.InvalidExpressoinType,
    }
}

fn default_peek(data_expr: []Value, scope: *Scope) Error!void {
    const local_data = data_expr;
    switch (local_data[DEFAULT_DATA_INDEX]) {
        .array => |a| {
            std.debug.assert(local_data[DEFAULT_INDEX] == .number);
            std.debug.assert(local_data[DEFAULT_INDEX].number == .integer);
            const index = local_data[DEFAULT_INDEX];
            const i: usize = @intCast(index.number.integer);
            scope.return_result = try a[i].clone();
        },
        .dictionary => return Error.NotImplemented,
        else => return Error.InvalidExpressoinType,
    }
}

fn default_has_next(data_expr: []Value, scope: *Scope) Error!void {
    const local_data = data_expr;
    switch (local_data[DEFAULT_DATA_INDEX]) {
        .array => |a| {
            std.debug.assert(local_data[DEFAULT_INDEX] == .number);
            std.debug.assert(local_data[DEFAULT_INDEX].number == .integer);
            const n = local_data[DEFAULT_INDEX].number.integer;
            scope.return_result = .{ .boolean = a.len > @as(usize, @intCast(n)) };
        },
        .dictionary => return Error.NotImplemented,
        else => return Error.InvalidExpressoinType,
    }
}

pub fn default_iterator(args: libtype.CallMatch, scope: *Scope) Error!void {
    std.debug.assert(args.unnamed_args.len == 1);
    switch (args.unnamed_args[0]) {
        .iterator => {
            scope.return_result = try args.unnamed_args[0].clone();
        },
        .array => {
            const tmp = try scope.allocator.alloc(Value, 2);
            tmp[DEFAULT_DATA_INDEX] = args.unnamed_args[0];
            tmp[DEFAULT_INDEX] = .{ .number = .{ .integer = 0 } };
            scope.return_result = expression.Iterator.initBuiltin(
                &default_next,
                &default_has_next,
                &default_peek,
                tmp,
            );
        },
        .dictionary => return Error.NotImplemented,
        else => return Error.InvalidExpressoinType,
    }
}

fn custom_iterator(args: libtype.CallMatch, scope: *Scope) Error!void {
    std.debug.assert(args.unnamed_args.len == 3);
    if (args.unnamed_args[0] != .function and args.unnamed_args[1] != .function) {
        return Error.InvalidExpressoinType;
    }

    scope.return_result = try expression.Iterator.init(
        scope.allocator,
        args.unnamed_args[0].function, // next function
        args.unnamed_args[1].function, // has_next function
        try args.unnamed_args[2].clone(scope.allocator), // data
    );
}

pub fn iterator(args: libtype.CallMatch, scope: *Scope) Error!void {
    const next_fn = args.unnamed_args[0];
    const has_next_fn = args.unnamed_args[1];

    if (next_fn != .function and has_next_fn != .function) {
        return Error.InvalidExpressoinType;
    }

    scope.return_result = expression.Iterator.init(
        next_fn.function,
        has_next_fn.function,
        null,
        args.unnamed_args[2..3],
    );
}

pub fn iter_next(args: libtype.CallMatch, scope: *Scope) Error!void {
    const iter = args.unnamed_args[0];
    std.debug.assert(iter == .iterator);

    switch (iter.iterator.next_fn) {
        .runtime => |f| {
            try exec_runtime_function(f, iter.iterator.data, scope);
            if (scope.result()) |res| {
                scope.return_result = res;
            } else {
                return Error.ValueNotFound;
            }
        },
        .builtin => |f| {
            try f(iter.iterator.data, scope);
        },
    }
}

pub fn iter_peek(args: libtype.CallMatch, scope: *Scope) Error!void {
    const iter = args.unnamed_args[0];
    std.debug.assert(iter == .iterator);

    if (iter.iterator.peek_fn) |func| {
        switch (func) {
            .runtime => |f| {
                try exec_runtime_function(f, iter.iterator.data, scope);
            },
            .builtin => |f| {
                try f(iter.iterator.data, scope);
            },
        }
    } else {
        scope.return_result = .{ .none = null };
    }
}

pub fn iter_has_next(args: libtype.CallMatch, scope: *Scope) Error!void {
    const iter = args.unnamed_args[0];
    std.debug.assert(iter == .iterator);

    switch (iter.iterator.has_next_fn) {
        .runtime => |f| {
            try exec_runtime_function(f, iter.iterator.data, scope);
            if (scope.result()) |res| {
                scope.return_result = res;
            } else {
                return Error.ValueNotFound;
            }
        },
        .builtin => |f| {
            try f(iter.iterator.data, scope);
        },
    }
}

pub fn array_append(args: []const Value, scope: *Scope) Error!void {
    std.debug.assert(args.len == 2);
    std.debug.assert(args[0] == .array);

    const out = try scope.allocator.alloc(Value, args[0].array.len + 1);
    @memcpy(out[0..args[0].array.len], args[0].array);
    out[args[0].array.len] = args[1];
    scope.return_result = .{ .array = out };
}

pub fn array_contains(args: []const Value, scope: *Scope) Error!void {
    std.debug.assert(args.len == 2);
    std.debug.assert(args[0] == .array);

    for (args[0].array) |elem| {
        if (elem.eql(args[1])) {
            scope.return_result = .{ .boolean = true };
            return;
        }
    }
    scope.return_result = .{ .boolean = false };
}

pub fn save_data(args: libtype.CallMatch, scope: *Scope) Error!void {
    const user_data = args.unnamed_args[0];
    const file_path = args.unnamed_args[1];
    const data_format = args.unnamed_args[2];
    std.debug.assert(file_path == .string);
    std.debug.assert(data_format == .string);
    const cwd = std.fs.cwd();
    var buffer: [128]u8 = undefined;
    const formatted_name = std.fmt.bufPrint(&buffer, "{s}.{s}", .{ file_path.string, data_format.string }) catch {
        std.debug.print("ERROR: filename is to large\n", .{});
        return Error.IOWrite;
    };
    var file = cwd.createFile(formatted_name, .{}) catch |err| {
        scope.out.print("ERROR: failed to create/open file '{s}': {}", .{ formatted_name, err }) catch return Error.IOWrite;
        return Error.IOWrite;
    };
    defer file.close();
    if (std.mem.eql(u8, data_format.string, "json")) {
        save_as_json(file.writer().any(), user_data) catch |err| {
            std.debug.print("ERROR: loading file failed: {}\n", .{err});
            return Error.IOWrite;
        };
        _ = file.write("\n\n") catch return Error.IOWrite;
    } else if (std.mem.eql(u8, data_format.string, "csv")) {
        var expr_map = ValueMap.init(scope.allocator);
        defer expr_map.deinit();
        save_as_csv(file.writer().any(), user_data, &expr_map) catch |err| {
            std.debug.print("ERROR: loading file failed: {}\n", .{err});
            return Error.IOWrite;
        };
        _ = file.write("\n\n") catch return Error.IOWrite;
    } else return Error.FormatNotSupportted;
}

fn save_as_json(writer: std.io.AnyWriter, expr: Value) !void {
    _ = switch (expr) {
        .none => try writer.write("null"),
        .number => |n| {
            switch (n) {
                .integer => |int| try writer.print("{}", .{int}),
                .float => |fl| try writer.print("{d}", .{fl}),
            }
        },
        .boolean => |value| try writer.print("{}", .{value}),
        .string => |value| try writer.print("\"{s}\"", .{value}),
        .dictionary => |dict| {
            _ = try writer.write("{\n");
            var has_written = false;
            var iter = dict.entries.iterator();
            while (iter.next()) |entry| {
                if (has_written) {
                    _ = try writer.write(",\n");
                } else has_written = true;
                try save_as_json(writer, entry.key_ptr.*);
                _ = try writer.write(": ");
                try save_as_json(writer, entry.value_ptr.*);
            }
            _ = try writer.write("\n");
            _ = try writer.write("}\n");
        },
        .array => |array| {
            _ = try writer.write("[");
            for (array[0 .. array.len - 1]) |entry| {
                try save_as_json(writer, entry);
                _ = try writer.write(", ");
            }
            const entry = array[array.len - 1];
            try save_as_json(writer, entry);
            _ = try writer.write("]");
        },
        else => return Error.InvalidExpressoinType,
    };
}

fn save_as_csv(writer: std.io.AnyWriter, expr: Value, expr_map: *ValueMap) !void {
    switch (expr) {
        .array => |elems| {
            if (elems.len > 0 and elems[0] == .dictionary) {
                try save_csv_header(writer, elems[0], expr_map);
                _ = try writer.write("\n");
            }
            for (elems) |entry| {
                try save_csv_entry(writer, entry, expr_map);
                _ = try writer.write("\n");
            }
        },
        .dictionary => {
            try save_csv_header(writer, expr, expr_map);
            _ = try writer.write("\n");
            try save_csv_dictionary(writer, expr, expr_map);
        },
        else => try save_csv_simple_entry(writer, expr),
    }
}

fn save_csv_entry(writer: std.io.AnyWriter, expr: Value, expr_map: *ValueMap) !void {
    switch (expr) {
        .array => |elems| {
            var has_printed = false;
            for (elems) |entry| {
                if (has_printed) {
                    _ = try writer.write(", ");
                } else has_printed = true;
                try save_csv_simple_entry(writer, entry);
            }
        },
        .dictionary => try save_csv_dictionary(writer, expr, expr_map),
        else => try save_csv_simple_entry(writer, expr),
    }
}

fn save_csv_simple_entry(writer: std.io.AnyWriter, expr: Value) !void {
    _ = switch (expr) {
        .none => try writer.print("\"{s}\"", .{"null"}),
        .string => |str| try writer.print("\"{s}\"", .{str}),
        .boolean => |value| try writer.print("{}", .{value}),
        .number => |n| {
            switch (n) {
                .float => |f| try writer.print("{d}", .{f}),
                .integer => |i| try writer.print("{}", .{i}),
            }
        },
        else => return Error.InvalidExpressoinType,
    };
}
fn save_csv_header(writer: std.io.AnyWriter, expr: Value, expr_map: *ValueMap) !void {
    std.debug.assert(expr == .dictionary);
    const entries = expr.dictionary.entries;
    if (entries.count() > 0) {
        var iter = entries.iterator();
        while (iter.next()) |entry| {
            try expr_map.put(entry.key_ptr.*, entry.value_ptr.*);
        }
    } else return;
    var has_printed = false;
    var iter = expr_map.keyIterator();
    while (iter.next()) |entry| {
        if (has_printed) {
            _ = try writer.write(", ");
        } else has_printed = true;
        var alloc = std.heap.GeneralPurposeAllocator(.{}){};
        var scope = Scope.empty(alloc.allocator(), writer);
        try printValue(entry.*, &scope);
    }
}

fn save_csv_dictionary(writer: std.io.AnyWriter, expr: Value, expr_map: *ValueMap) !void {
    std.debug.assert(expr == .dictionary);
    const entries = expr.dictionary.entries;
    var iter = entries.iterator();
    while (iter.next()) |entry| {
        try expr_map.put(entry.key_ptr.*, entry.value_ptr.*);
    }
    var has_printed = false;
    var out_iter = expr_map.keyIterator();
    while (out_iter.next()) |entry| {
        if (has_printed) {
            _ = try writer.write(", ");
        } else has_printed = true;
        const value = expr_map.get(entry.*) orelse unreachable;
        try save_csv_simple_entry(writer, value);
    }
}
