const std = @import("std");

const expression = @import("../expression.zig");
const statement = @import("../statement.zig");
const interpreter = @import("../interpreter.zig");
const data = @import("data.zig");
const Scope = @import("../Scope.zig");
const Expression = expression.Expression;
const Statement = statement.Statement;

pub const Error = @import("type.zig").Error;

fn exec_runtime_function(func: expression.Function, call_args: []Expression, scope: *Scope) Error!void {
    var local_scope = try Scope.init(scope.allocator, scope.out, scope, func.args, call_args);
    for (func.body) |st| {
        try interpreter.evalStatement(st, &local_scope);
    }
    const out = local_scope.result() orelse unreachable;
    scope.return_result = try out.clone(scope.allocator);
}

pub fn length(args: []const Expression, scope: *Scope) Error!void {
    switch (args[0]) {
        .array => |a| {
            scope.return_result = try expression.Number.init(
                scope.allocator,
                i64,
                @intCast(a.elements.len),
            );
        },
        .dictionary => |d| {
            scope.return_result = try expression.Number.init(
                scope.allocator,
                i64,
                @intCast(d.entries.len),
            );
        },
        else => |v| {
            std.debug.print("ERROR: unexpected case: {s}\n", .{@tagName(v)});
            return Error.InvalidExpressoinType;
        },
    }
}

pub fn _type(args: []const Expression, scope: *Scope) Error!void {
    const out = try scope.allocator.create(Expression);
    out.* = .{ .string = .{ .value = @tagName(args[0]) } };
    scope.return_result = out;
}

pub fn load_data(args: []const Expression, scope: *Scope) Error!void {
    const file_path = args[0];
    const data_format = args[1];
    std.debug.assert(file_path == .string);
    std.debug.assert(data_format == .string);
    if (std.mem.eql(u8, data_format.string.value, "lines")) {
        const lines = data.load_lines(file_path.string.value, scope.allocator) catch |err| {
            std.debug.print("ERROR: loading file failed: {}\n", .{err});
            return Error.NotImplemented;
        };
        defer scope.allocator.free(lines);
        const out = try scope.allocator.alloc(Expression, lines.len);
        for (lines, out) |line, *elem| {
            elem.* = .{ .string = .{ .value = line } };
        }
        const tmp = try scope.allocator.create(Expression);
        tmp.* = .{ .array = .{ .elements = out } };
        scope.return_result = tmp;
    } else if (std.mem.eql(u8, data_format.string.value, "json")) {
        scope.return_result = data.load_json(file_path.string.value, scope.allocator) catch |err| {
            std.debug.print("ERROR: loading file failed: {}\n", .{err});
            return Error.NotImplemented;
        };
    } else if (std.mem.eql(u8, data_format.string.value, "csv")) {
        scope.return_result = data.load_csv(file_path.string.value, scope.allocator) catch |err| {
            std.debug.print("ERROR: loading file failed: {}\n", .{err});
            return Error.NotImplemented;
        };
    } else return Error.NotImplemented;
}

const MAP_FN_INDEX = 1;
const MAP_DATA_INDEX = 0;
fn map_next(data_expr: *expression.Expression, scope: *Scope) Error!void {
    std.debug.assert(data_expr.* == .array);
    const local_data = data_expr.array.elements;
    std.debug.assert(local_data[MAP_DATA_INDEX] == .iterator);
    std.debug.assert(local_data[MAP_FN_INDEX] == .function);
    const tmp = try scope.allocator.alloc(Expression, 1);
    defer scope.allocator.free(tmp);
    const args = try scope.allocator.alloc(Expression, 1);
    defer scope.allocator.free(args);

    tmp[0] = local_data[MAP_DATA_INDEX];
    try iter_next(tmp, scope);
    args[0] = scope.result() orelse unreachable;
    const func = local_data[MAP_FN_INDEX].function;
    try exec_runtime_function(func, args, scope);
}

fn map_peek(data_expr: *expression.Expression, scope: *Scope) Error!void {
    std.debug.assert(data_expr.* == .array);
    const local_data = data_expr.array.elements;
    std.debug.assert(local_data[MAP_DATA_INDEX] == .iterator);
    std.debug.assert(local_data[MAP_FN_INDEX] == .function);
    const tmp = try scope.allocator.alloc(Expression, 1);
    defer scope.allocator.free(tmp);
    const args = try scope.allocator.alloc(Expression, 1);
    defer scope.allocator.free(args);

    tmp[0] = local_data[MAP_DATA_INDEX];
    try iter_peek(tmp, scope);
    args[0] = scope.result() orelse unreachable;
    const func = local_data[MAP_FN_INDEX].function;
    try exec_runtime_function(func, args, scope);
}

fn map_has_next(data_expr: *expression.Expression, scope: *Scope) Error!void {
    std.debug.assert(data_expr.* == .array);
    const local_data = data_expr.array.elements;
    std.debug.assert(local_data[MAP_DATA_INDEX] == .iterator);
    std.debug.assert(local_data[MAP_FN_INDEX] == .function);
    const tmp = try scope.allocator.alloc(Expression, 1);
    defer scope.allocator.free(tmp);
    tmp[0] = local_data[MAP_DATA_INDEX];
    try iter_has_next(tmp, scope);
}

pub fn map(args: []const Expression, scope: *Scope) Error!void {
    const elements = args[0];
    const callable = args[1];
    std.debug.assert(callable == .function);

    switch (elements) {
        .array => |a| {
            const out = try scope.allocator.alloc(Expression, a.elements.len);
            const func = callable.function;
            for (a.elements, out) |e, *t| {
                var call_args = try scope.allocator.alloc(Expression, 1);
                defer scope.allocator.free(call_args);
                call_args[0] = e;
                try exec_runtime_function(func, call_args, scope);
                if (scope.result()) |r| {
                    t.* = r;
                } else {
                    return Error.ValueNotFound;
                }
            }
            scope.return_result = try expression.Array.init(scope.allocator, out);
        },
        .iterator => {
            const tmp = try scope.allocator.alloc(Expression, 2);
            tmp[MAP_DATA_INDEX] = elements;
            tmp[MAP_FN_INDEX] = callable;
            const data_expr = try expression.Array.init(scope.allocator, tmp);
            scope.return_result = try expression.Iterator.initBuiltin(
                scope.allocator,
                &map_next,
                &map_has_next,
                &map_peek,
                data_expr,
            );
        },
        else => return Error.NotImplemented,
    }
}

const FLATTEN_DATA_INDEX = 0;
const FLATTEN_INTERMEDIATE_INDEX = 1;
fn flatten_iter_has_elements(iter: Expression, scope: *Scope) bool {
    if (iter == .iterator) {
        const ptr = &iter;
        iter_has_next(ptr[0..1], scope) catch return false;
        const tmp = scope.result() orelse unreachable;
        return tmp == .boolean and tmp.boolean.value;
    }

    return false;
}

fn flatten_next(data_expr: *expression.Expression, scope: *Scope) Error!void {
    std.debug.assert(data_expr.* == .array);
    const local_data = data_expr.array.elements;
    std.debug.assert(local_data[FLATTEN_DATA_INDEX] == .iterator);
    if (!flatten_iter_has_elements(local_data[FLATTEN_INTERMEDIATE_INDEX], scope)) {
        try iter_next(local_data[FLATTEN_DATA_INDEX .. FLATTEN_DATA_INDEX + 1], scope);
        const tmp = scope.result_ref() orelse unreachable;
        try default_iterator(tmp[0..1], scope);
        local_data[FLATTEN_INTERMEDIATE_INDEX] = scope.result() orelse unreachable;
    }
    try iter_next(local_data[FLATTEN_INTERMEDIATE_INDEX .. FLATTEN_INTERMEDIATE_INDEX + 1], scope);
}

fn flatten_peek(data_expr: *expression.Expression, scope: *Scope) Error!void {
    std.debug.assert(data_expr.* == .array);
    const local_data = data_expr.array.elements;
    std.debug.assert(local_data[FLATTEN_DATA_INDEX] == .iterator);
    if (!flatten_iter_has_elements(local_data[FLATTEN_INTERMEDIATE_INDEX], scope)) {
        try iter_next(local_data[FLATTEN_DATA_INDEX .. FLATTEN_DATA_INDEX + 1], scope);
        const tmp = scope.result_ref() orelse unreachable;
        try default_iterator(tmp[0..1], scope);
        local_data[FLATTEN_INTERMEDIATE_INDEX] = scope.result() orelse unreachable;
    }
    try iter_peek(local_data[FLATTEN_INTERMEDIATE_INDEX .. FLATTEN_INTERMEDIATE_INDEX + 1], scope);
}

fn flatten_has_next(data_expr: *expression.Expression, scope: *Scope) Error!void {
    std.debug.assert(data_expr.* == .array);
    const local_data = data_expr.array.elements;
    std.debug.assert(local_data[FLATTEN_DATA_INDEX] == .iterator);
    if (local_data[FLATTEN_INTERMEDIATE_INDEX] == .none) {
        try iter_has_next(local_data[FLATTEN_DATA_INDEX .. FLATTEN_DATA_INDEX + 1], scope);
    } else if (local_data[FLATTEN_INTERMEDIATE_INDEX] == .iterator) {
        try iter_has_next(local_data[FLATTEN_INTERMEDIATE_INDEX .. FLATTEN_INTERMEDIATE_INDEX + 1], scope);
        const tmp = scope.result() orelse unreachable;
        if (tmp == .boolean and !tmp.boolean.value) {
            try iter_has_next(local_data[FLATTEN_DATA_INDEX .. FLATTEN_DATA_INDEX + 1], scope);
        } else {
            scope.return_result = try tmp.clone(scope.allocator);
        }
    }
}

pub fn flatten(args: []const Expression, scope: *Scope) Error!void {
    const lists = args[0];
    switch (lists) {
        .array => |a| {
            const slices = a.elements;
            if (slices.len == 0) {
                const out = try scope.allocator.create(Expression);
                out.* = .{ .array = .{
                    .elements = &[0]Expression{},
                } };
                scope.return_result = out;
            }

            const total_len = blk: {
                var sum: usize = 0;
                for (slices) |slice| sum += if (slice == .array) slice.array.elements.len else 1;
                break :blk sum;
            };

            const buf = try scope.allocator.alloc(Expression, total_len);
            errdefer scope.allocator.free(buf);

            var buffer_index: usize = 0;
            for (slices) |elem| {
                if (elem == .array) {
                    for (elem.array.elements) |e| {
                        buf[buffer_index] = e;
                        buffer_index += 1;
                    }
                } else {
                    buf[buffer_index] = elem;
                    buffer_index += 1;
                }
            }

            // No need for shrink since buf is exactly the correct size.
            const out = try scope.allocator.create(Expression);
            out.* = .{ .array = .{
                .elements = buf,
            } };
            scope.return_result = out;
        },
        .iterator => {
            const tmp = try scope.allocator.alloc(Expression, 2);
            tmp[FLATTEN_DATA_INDEX] = lists;
            tmp[FLATTEN_INTERMEDIATE_INDEX] = .{ .none = null };
            const data_expr = try expression.Array.init(scope.allocator, tmp);
            scope.return_result = try expression.Iterator.initBuiltin(
                scope.allocator,
                &flatten_next,
                &flatten_has_next,
                &flatten_peek,
                data_expr,
            );
        },
        else => scope.return_result = try lists.clone(scope.allocator),
    }
}

pub fn flatmap(args: []const Expression, scope: *Scope) Error!void {
    const elements = args[0];
    const callable = args[1];
    std.debug.assert(callable == .function);
    switch (elements) {
        .array, .iterator => {
            try map(args, scope);
            const map_result = scope.result() orelse unreachable;
            try flatten(&[_]Expression{map_result}, scope);
        },
        else => return Error.NotImplemented,
    }
}

pub fn reduce(args: []const Expression, scope: *Scope) Error!void {
    const elements = args[0];
    const callable = args[1];
    std.debug.assert(callable == .function);
    if (callable.function.args.len != 2) {
        std.debug.print("ERROR: the provided function has {} arguments\n", .{callable.function.args.len});
        std.debug.print("   needed are {}\n", .{2});
        return Error.InvalidExpressoinType;
    }
    const func = callable.function;

    switch (elements) {
        .array => |a| {
            var acc = a.elements[0];
            for (a.elements[1..]) |e| {
                var call_args = try scope.allocator.alloc(Expression, 2);
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
            const out = try scope.allocator.create(Expression);
            out.* = acc;
            scope.return_result = out;
        },
        .iterator => {
            try iter_has_next(args[0..1], scope);
            var result = scope.result() orelse unreachable;
            std.debug.assert(result == .boolean);
            if (!result.boolean.value) {
                const tmp = try scope.allocator.create(Expression);
                tmp.* = .{ .none = null };
                scope.return_result = tmp;
                return;
            }
            try iter_next(args[0..1], scope);
            var acc = scope.result() orelse unreachable;
            try iter_has_next(args[0..1], scope);
            result = scope.result() orelse unreachable;
            std.debug.assert(result == .boolean);
            while (result.boolean.value) {
                try iter_next(args[0..1], scope);
                const e = scope.result() orelse unreachable;
                var call_args = try scope.allocator.alloc(Expression, 2);
                defer scope.allocator.free(call_args);
                call_args[0] = acc;
                call_args[1] = e;
                try exec_runtime_function(func, call_args, scope);
                if (scope.result()) |r| {
                    std.debug.print("INFO: reduce result type: {s}\n", .{@tagName(r)});
                    acc = r;
                } else {
                    return Error.ValueNotFound;
                }
                try iter_has_next(args[0..1], scope);
                result = scope.result() orelse unreachable;
            }
            scope.return_result = try acc.clone(scope.allocator);
        },
        else => return Error.NotImplemented,
    }
}

const GROUP_BY_FN_INDEX = 1;
const GROUP_BY_DATA_INDEX = 0;
const GROUP_BY_SEEN_INDEX = 2;
const GROUP_BY_TEMP_INDEX = 3;
fn group_by_next(data_expr: *expression.Expression, scope: *Scope) Error!void {
    std.debug.assert(data_expr.* == .array);
    const elements = data_expr.array.elements;
    std.debug.assert(elements[GROUP_BY_FN_INDEX] == .function);
    std.debug.assert(elements[GROUP_BY_DATA_INDEX] == .iterator);
    try iter_peek(elements[GROUP_BY_DATA_INDEX .. GROUP_BY_DATA_INDEX + 1], scope);
    elements[GROUP_BY_TEMP_INDEX] = scope.result() orelse unreachable;
    try exec_runtime_function(
        elements[GROUP_BY_FN_INDEX].function,
        elements[GROUP_BY_TEMP_INDEX .. GROUP_BY_TEMP_INDEX + 1],
        scope,
    );
    elements[GROUP_BY_TEMP_INDEX] = scope.result() orelse unreachable;
    try array_contains(elements[GROUP_BY_SEEN_INDEX .. GROUP_BY_SEEN_INDEX + 2], scope);
    var result = scope.result() orelse unreachable;
    while (result.boolean.value) {
        try iter_next(elements[GROUP_BY_DATA_INDEX .. GROUP_BY_DATA_INDEX + 1], scope);
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
        try elements[GROUP_BY_FN_INDEX].clone(scope.allocator),
        try elements[GROUP_BY_TEMP_INDEX].clone(scope.allocator),
        scope,
    );
    const filter_tmp = try scope.allocator.alloc(Expression, 2);
    const tmp_iter = try elements[GROUP_BY_DATA_INDEX].clone(scope.allocator);
    defer scope.allocator.destroy(tmp_iter);
    filter_tmp[0] = tmp_iter.*;
    filter_tmp[1] = filter_fn.*;
    try filter(filter_tmp, scope);
    const filter_iter = scope.result_ref() orelse unreachable;
    const entries = try scope.allocator.alloc(expression.DictionaryEntry, 2);
    entries[0] = .{
        .key = try expression.String.init(scope.allocator, "key"),
        .value = try elements[GROUP_BY_TEMP_INDEX].clone(scope.allocator),
    };
    entries[1] = .{
        .key = try expression.String.init(scope.allocator, "values"),
        .value = filter_iter,
    };
    try array_append(elements[GROUP_BY_SEEN_INDEX .. GROUP_BY_SEEN_INDEX + 2], scope);
    elements[GROUP_BY_SEEN_INDEX] = scope.result() orelse unreachable;
    try iter_next(elements[GROUP_BY_DATA_INDEX .. GROUP_BY_DATA_INDEX + 1], scope);
    scope.return_result = try expression.Dictionary.init(scope.allocator, entries);
}

fn equal_to_key(groupper: *Expression, key: *Expression, scope: *Scope) !*Expression {
    const tmp = try expression.Identifier.init(scope.allocator, "tmp");
    const id = try expression.Identifier.init(scope.allocator, "x");
    const bin = try expression.BinaryOp.init(
        scope.allocator,
        .{ .compare = .Equal },
        key,
        tmp,
    );
    const fn_call = try expression.FunctionCall.init(
        scope.allocator,
        groupper,
        id[0..1],
    );
    const args = try scope.allocator.alloc(expression.Identifier, 1);
    args[0] = .{ .name = "x" };
    const sts = try scope.allocator.alloc(Statement, 2);
    sts[0] = .{ .assignment = .{ .varName = tmp.identifier, .value = fn_call } };
    sts[1] = .{ .@"return" = .{ .value = bin } };
    return expression.Function.init(scope.allocator, args, sts);
}

fn group_by_peek(data_expr: *expression.Expression, scope: *Scope) Error!void {
    std.debug.assert(data_expr.* == .array);
    const elements = data_expr.array.elements;
    std.debug.assert(elements[GROUP_BY_FN_INDEX] == .function);
    std.debug.assert(elements[GROUP_BY_DATA_INDEX] == .iterator);
    try iter_peek(elements[GROUP_BY_DATA_INDEX .. GROUP_BY_DATA_INDEX + 1], scope);
    elements[GROUP_BY_TEMP_INDEX] = scope.result() orelse unreachable;
    try exec_runtime_function(
        elements[GROUP_BY_FN_INDEX].function,
        elements[GROUP_BY_TEMP_INDEX .. GROUP_BY_TEMP_INDEX + 1],
        scope,
    );
    elements[GROUP_BY_TEMP_INDEX] = scope.result() orelse unreachable;
    const filter_fn = try equal_to_key(
        try elements[GROUP_BY_FN_INDEX].clone(scope.allocator),
        try elements[GROUP_BY_TEMP_INDEX].clone(scope.allocator),
        scope,
    );
    const filter_tmp = try scope.allocator.alloc(Expression, 2);
    const tmp_iter = try elements[GROUP_BY_DATA_INDEX].clone(scope.allocator);
    defer scope.allocator.destroy(tmp_iter);
    filter_tmp[0] = tmp_iter.*;
    filter_tmp[1] = filter_fn.*;
    try filter(filter_tmp, scope);
    const filter_iter = scope.result_ref() orelse unreachable;
    const entries = try scope.allocator.alloc(expression.DictionaryEntry, 2);
    entries[0] = .{
        .key = try expression.String.init(scope.allocator, "key"),
        .value = try elements[GROUP_BY_TEMP_INDEX].clone(scope.allocator),
    };
    entries[1] = .{
        .key = try expression.String.init(scope.allocator, "values"),
        .value = filter_iter,
    };
    scope.return_result = try expression.Dictionary.init(scope.allocator, entries);
}

fn group_by_has_next(data_expr: *expression.Expression, scope: *Scope) Error!void {
    std.debug.assert(data_expr.* == .array);
    const elements = data_expr.array.elements;
    std.debug.assert(elements[GROUP_BY_FN_INDEX] == .function);
    std.debug.assert(elements[GROUP_BY_DATA_INDEX] == .iterator);
    const tmp_iter = try elements[GROUP_BY_DATA_INDEX].clone(scope.allocator);
    try iter_has_next(tmp_iter[0..1], scope);
    var result = scope.result() orelse unreachable;
    if (result == .boolean and !result.boolean.value) {
        scope.return_result = try expression.Boolean.init(scope.allocator, false);
        return;
    }
    try iter_peek(tmp_iter[0..1], scope);
    elements[GROUP_BY_TEMP_INDEX] = scope.result() orelse unreachable;
    try exec_runtime_function(
        elements[GROUP_BY_FN_INDEX].function,
        elements[GROUP_BY_TEMP_INDEX .. GROUP_BY_TEMP_INDEX + 1],
        scope,
    );
    elements[GROUP_BY_TEMP_INDEX] = scope.result() orelse unreachable;
    try array_contains(elements[GROUP_BY_SEEN_INDEX .. GROUP_BY_SEEN_INDEX + 2], scope);
    result = scope.result() orelse unreachable;
    while (result == .boolean and result.boolean.value) {
        try iter_has_next(tmp_iter[0..1], scope);
        result = scope.result() orelse unreachable;
        if (result == .boolean and !result.boolean.value) {
            scope.return_result = try expression.Boolean.init(scope.allocator, false);
            return;
        }
        try iter_next(tmp_iter[0..1], scope);
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

    scope.return_result = try expression.Boolean.init(scope.allocator, true);
}

pub fn group_by(args: []const Expression, scope: *Scope) Error!void {
    const elements = args[0];
    const callable = args[1];
    std.debug.assert(callable == .function);
    switch (elements) {
        .array => |a| {
            var out_map = std.StringHashMap(std.ArrayList(Expression)).init(scope.allocator);
            // TODO: hard coded slice size. May overfilled by 'callable' if it returns large arrays/dictionaries
            var buffer: [2048]u8 = undefined;
            var fixedStream = std.io.fixedBufferStream(&buffer);
            const writer = fixedStream.writer().any();
            for (a.elements) |elem| {
                fixedStream.reset();
                const call_args: []Expression = try scope.allocator.alloc(Expression, 1);
                defer scope.allocator.free(call_args);
                call_args[0] = elem;
                try exec_runtime_function(callable.function, call_args, scope);
                const result = scope.result() orelse return Error.ValueNotFound;
                var out_scope = Scope.empty(scope.allocator, writer);
                // NOTE: praying that only simple values are printed
                try interpreter.printValue(result, &out_scope);
                const written: []const u8 = fixedStream.getWritten();
                if (out_map.getPtr(written)) |value| {
                    try value.append(elem);
                } else {
                    var value = std.ArrayList(Expression).init(scope.allocator);
                    try value.append(elem);
                    const key = try scope.allocator.dupe(u8, written);
                    defer scope.allocator.free(written);
                    try out_map.put(key, value);
                }
            }

            var entries = std.ArrayList(expression.DictionaryEntry).init(scope.allocator);
            var iter = out_map.iterator();
            while (iter.next()) |entry| {
                // TODO: We may want to prefer the original value over it's string representation
                const key_str = try scope.allocator.dupe(u8, entry.key_ptr.*);
                const key = try expression.String.init(scope.allocator, key_str);
                const value_entries = try entry.value_ptr.toOwnedSlice();
                const value = try expression.Array.init(scope.allocator, value_entries);
                try entries.append(.{ .key = key, .value = value });
            }
            scope.return_result = try expression.Dictionary.init(scope.allocator, try entries.toOwnedSlice());
        },
        .iterator => {
            const tmp = try scope.allocator.alloc(Expression, 4);
            tmp[GROUP_BY_DATA_INDEX] = elements;
            tmp[GROUP_BY_FN_INDEX] = callable;
            tmp[GROUP_BY_SEEN_INDEX] = .{ .array = .{
                .elements = &[0]Expression{},
            } };
            const data_expr = try expression.Array.init(scope.allocator, tmp);
            scope.return_result = try expression.Iterator.initBuiltin(
                scope.allocator,
                &group_by_next,
                &group_by_has_next,
                &group_by_peek,
                data_expr,
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

fn check(context: Context, args: []const Expression, scope: *Scope) Error!void {
    const elements = args[0];
    const callable = args[1];

    std.debug.assert(callable == .function);
    if (callable.function.args.len != 1) {
        std.debug.print("ERROR: the provided function has {} arguments\n", .{callable.function.args.len});
        std.debug.print("   needed are {}\n", .{1});
        std.process.exit(1);
    }
    const func = callable.function;

    switch (elements) {
        .array => |a| {
            var acc: Context.OutType = context.initial;
            for (a.elements) |e| {
                var call_args = try scope.allocator.alloc(Expression, 1);
                defer scope.allocator.free(call_args);
                call_args[0] = e;
                try exec_runtime_function(func, call_args, scope);
                if (scope.result()) |r| {
                    if (r == .boolean) {
                        acc = context.operation(acc, r.boolean.value);
                    } else if (r != .boolean) {
                        std.debug.print("ERROR: returned value of function is not a boolean\n", .{});
                        return Error.InvalidExpressoinType;
                    }
                } else {
                    return Error.ValueNotFound;
                }
            }
            scope.return_result = switch (acc) {
                .boolean => |v| try expression.Boolean.init(scope.allocator, v),
                .number => |v| try expression.Number.init(scope.allocator, i64, v),
            };
        },
        .iterator => {
            var acc: Context.OutType = context.initial;
            const elems = try elements.clone(scope.allocator);
            defer expression.free(scope.allocator, elems);
            try iter_has_next(elems[0..1], scope);
            var condition = scope.result() orelse unreachable;
            var call_args = try scope.allocator.alloc(Expression, 1);
            defer scope.allocator.free(call_args);
            while (condition == .boolean and condition.boolean.value) {
                try iter_next(elems[0..1], scope);
                call_args[0] = scope.result() orelse unreachable;
                try exec_runtime_function(func, call_args, scope);
                if (scope.result()) |r| {
                    if (r == .boolean) {
                        acc = context.operation(acc, r.boolean.value);
                    } else if (r != .boolean) {
                        std.debug.print("ERROR: returned value of function is not a boolean\n", .{});
                        return Error.InvalidExpressoinType;
                    }
                } else {
                    return Error.ValueNotFound;
                }
                try iter_has_next(elems[0..1], scope);
                condition = scope.result() orelse unreachable;
            }
            scope.return_result = switch (acc) {
                .boolean => |v| try expression.Boolean.init(scope.allocator, v),
                .number => |v| try expression.Number.init(scope.allocator, i64, v),
            };
        },
        else => return Error.NotImplemented,
    }
}

pub fn count(args: []const Expression, scope: *Scope) Error!void {
    try check(Count_context, args, scope);
}

pub fn check_all(args: []const Expression, scope: *Scope) Error!void {
    try check(All_context, args, scope);
}

pub fn check_any(args: []const Expression, scope: *Scope) Error!void {
    try check(Any_context, args, scope);
}

pub fn check_none(args: []const Expression, scope: *Scope) Error!void {
    try check(None_context, args, scope);
}

const FILTER_FN_INDEX = 1;
const FILTER_DATA_INDEX = 0;
fn filter_next(data_expr: *expression.Expression, scope: *Scope) Error!void {
    std.debug.assert(data_expr.* == .array);
    const elements = data_expr.array.elements;
    std.debug.assert(elements[FILTER_FN_INDEX] == .function);
    std.debug.assert(elements[FILTER_DATA_INDEX] == .iterator);
    const iter = &elements[FILTER_DATA_INDEX];
    const func = elements[FILTER_FN_INDEX].function;
    try iter_has_next(iter[0..1], scope);
    var result = scope.result_ref() orelse unreachable;
    if (!result.boolean.value) {
        scope.return_result = result;
        return;
    }

    try iter_next(iter[0..1], scope);
    var out = scope.result_ref() orelse unreachable;
    try exec_runtime_function(func, out[0..1], scope);
    result = scope.result_ref() orelse unreachable;
    while (result.* == .boolean and !result.boolean.value) {
        try iter_has_next(iter[0..1], scope);
        result = scope.result_ref() orelse unreachable;
        if (!result.boolean.value) {
            const tmp = try scope.allocator.create(Expression);
            tmp.* = .{ .none = null };
            scope.return_result = tmp;
            return;
        }

        try iter_next(iter[0..1], scope);
        out = scope.result_ref() orelse unreachable;
        try exec_runtime_function(func, out[0..1], scope);
        result = scope.result_ref() orelse unreachable;
    }
    scope.return_result = out;
}

fn filter_peek(data_expr: *expression.Expression, scope: *Scope) Error!void {
    std.debug.assert(data_expr.* == .array);
    const elements = data_expr.array.elements;
    std.debug.assert(elements[FILTER_FN_INDEX] == .function);
    std.debug.assert(elements[FILTER_DATA_INDEX] == .iterator);
    const iter = &elements[FILTER_DATA_INDEX];
    const func = elements[FILTER_FN_INDEX].function;
    try iter_has_next(iter[0..1], scope);
    var result = scope.result_ref() orelse unreachable;
    if (!result.boolean.value) {
        scope.return_result = result;
        return;
    }

    try iter_peek(iter[0..1], scope);
    var out = scope.result_ref() orelse unreachable;
    try exec_runtime_function(func, out[0..1], scope);
    result = scope.result_ref() orelse unreachable;
    while (result.* == .boolean and !result.boolean.value) {
        try iter_next(iter[0..1], scope);
        try iter_has_next(iter[0..1], scope);
        result = scope.result_ref() orelse unreachable;
        if (!result.boolean.value) {
            const tmp = try scope.allocator.create(Expression);
            tmp.* = .{ .none = null };
            scope.return_result = tmp;
            return;
        }

        try iter_peek(iter[0..1], scope);
        out = scope.result_ref() orelse unreachable;
        try exec_runtime_function(func, out[0..1], scope);
        result = scope.result_ref() orelse unreachable;
    }
    scope.return_result = out;
}

fn filter_has_next(data_expr: *expression.Expression, scope: *Scope) Error!void {
    std.debug.assert(data_expr.* == .array);
    const elements = data_expr.array.elements;
    std.debug.assert(elements[FILTER_FN_INDEX] == .function);
    std.debug.assert(elements[FILTER_DATA_INDEX] == .iterator);
    const tmp_iter = try elements[FILTER_DATA_INDEX].clone(scope.allocator);
    const func = elements[FILTER_FN_INDEX].function;
    defer expression.free(scope.allocator, tmp_iter);
    try iter_has_next(tmp_iter[0..1], scope);
    var result = scope.result_ref() orelse unreachable;
    if (!result.boolean.value) {
        scope.return_result = result;
        return;
    }

    try iter_next(tmp_iter[0..1], scope);
    result = scope.result_ref() orelse unreachable;
    try exec_runtime_function(func, result[0..1], scope);
    result = scope.result_ref() orelse unreachable;
    while (result.* == .boolean and !result.boolean.value) {
        try iter_has_next(tmp_iter[0..1], scope);
        result = scope.result_ref() orelse unreachable;
        if (!result.boolean.value) {
            scope.return_result = result;
            return;
        }

        try iter_next(tmp_iter[0..1], scope);
        result = scope.result_ref() orelse unreachable;
        try exec_runtime_function(func, result[0..1], scope);
        result = scope.result_ref() orelse unreachable;
    }
    scope.return_result = result;
}

pub fn filter(args: []const Expression, scope: *Scope) Error!void {
    const elements = args[0];
    const callable = args[1];
    std.debug.assert(callable == .function);

    switch (elements) {
        .array => |a| {
            try count(args, scope);
            const element_count = (scope.result() orelse unreachable).number.integer;
            const tmp = try scope.allocator.alloc(Expression, @intCast(element_count));
            var current_index: usize = 0;
            const func = callable.function;
            for (a.elements) |e| {
                var call_args = try scope.allocator.alloc(Expression, 1);
                defer scope.allocator.free(call_args);
                call_args[0] = e;
                try exec_runtime_function(func, call_args, scope);
                if (scope.result()) |r| {
                    if (r == .boolean and r.boolean.value) {
                        tmp[current_index] = e;
                        current_index += 1;
                    }
                } else {
                    return Error.ValueNotFound;
                }
            }
            scope.return_result = try expression.Array.init(scope.allocator, tmp);
        },
        .iterator => {
            const tmp = try scope.allocator.alloc(Expression, 2);
            tmp[FILTER_DATA_INDEX] = elements;
            tmp[FILTER_FN_INDEX] = callable;
            const data_expr = try expression.Array.init(scope.allocator, tmp);
            scope.return_result = try expression.Iterator.initBuiltin(
                scope.allocator,
                &filter_next,
                &filter_has_next,
                &filter_peek,
                data_expr,
            );
        },
        else => return Error.NotImplemented,
    }
}

fn zip_next(data_expr: *expression.Expression, scope: *Scope) Error!void {
    std.debug.assert(data_expr.* == .array);
    const local_data = data_expr.array.elements;
    const out = try scope.allocator.alloc(Expression, local_data.len);
    for (local_data, 0..) |*iter, index| {
        try iter_next(iter[0..1], scope);
        const value = scope.result() orelse unreachable;
        out[index] = value;
    }
    scope.return_result = try expression.Array.init(scope.allocator, out);
}

fn zip_peek(data_expr: *expression.Expression, scope: *Scope) Error!void {
    std.debug.assert(data_expr.* == .array);
    const local_data = data_expr.array.elements;
    const out = try scope.allocator.alloc(Expression, local_data.len);
    for (local_data, 0..) |*iter, index| {
        try iter_peek(iter[0..1], scope);
        const value = scope.result() orelse unreachable;
        out[index] = value;
    }
    scope.return_result = try expression.Array.init(scope.allocator, out);
}

fn zip_has_next(data_expr: *expression.Expression, scope: *Scope) Error!void {
    std.debug.assert(data_expr.* == .array);
    const local_data = data_expr.array.elements;
    var all_true = true;
    for (local_data) |*iter| {
        try iter_has_next(iter[0..1], scope);
        const condition = scope.result() orelse unreachable;
        std.debug.assert(condition == .boolean);
        all_true = all_true and condition.boolean.value;
    }
    scope.return_result = try expression.Boolean.init(scope.allocator, all_true);
}

pub fn zip(args: []const Expression, scope: *Scope) Error!void {
    const left_elements = args[0];
    const right_elements = args[1];

    if (left_elements == .array and right_elements == .array) {
        const left = left_elements.array.elements;
        const right = right_elements.array.elements;
        const element_count = if (left.len < right.len) left.len else right.len;
        const tmp = try scope.allocator.alloc(Expression, element_count);
        for (left[0..element_count], right[0..element_count], tmp) |l, r, *t| {
            const out = try scope.allocator.alloc(Expression, 2);
            out[0] = l;
            out[1] = r;
            t.* = .{ .array = expression.Array{ .elements = out } };
        }
        scope.return_result = try expression.Array.init(scope.allocator, tmp);
        return;
    }

    if (left_elements == .iterator and right_elements == .iterator) {
        var tmp = std.ArrayList(Expression).init(scope.allocator);
        try tmp.appendSlice(args);
        const data_expr = try expression.Array.init(scope.allocator, try tmp.toOwnedSlice());
        scope.return_result = try expression.Iterator.initBuiltin(
            scope.allocator,
            &zip_next,
            &zip_has_next,
            &zip_peek,
            data_expr,
        );
        return;
    }

    return Error.NotImplemented;
}

fn swap(left: *Expression, right: *Expression) void {
    const tmp = left.*;
    left.* = right.*;
    right.* = tmp;
}

fn partition(elements: []Expression, binary_op: expression.Function, scope: *Scope) Error!usize {
    var pivot = elements.len - 1;
    var left: usize = 0;
    while (left < pivot) {
        var call_args = try scope.allocator.alloc(Expression, 2);
        defer scope.allocator.free(call_args);
        call_args[0] = elements[left];
        call_args[1] = elements[pivot];
        try exec_runtime_function(binary_op, call_args, scope);
        const result = scope.result() orelse return Error.ValueNotFound;
        if (result == .number and result.number.asFloat() == -1) {
            left += 1;
        } else if (result == .boolean and result.boolean.value) {
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

fn sort_impl(elements: []Expression, binary_op: expression.Function, scope: *Scope) Error!void {
    if (elements.len < 2) return;
    const partition_point = try partition(elements, binary_op, scope);
    const left: []Expression = elements[0..partition_point];
    const right: []Expression = elements[partition_point + 1 .. elements.len];
    try sort_impl(left, binary_op, scope);
    try sort_impl(right, binary_op, scope);
}

pub fn sort(args: []const Expression, scope: *Scope) Error!void {
    const elements = args[0];
    const callable = args[1];
    std.debug.assert(callable == .function);
    std.debug.assert(callable.function.args.len == 2);

    switch (elements) {
        .array => |a| {
            try sort_impl(a.elements, callable.function, scope);
            scope.return_result = try expression.Array.init(scope.allocator, a.elements);
        },
        else => |e| {
            std.debug.print("ERROR: `sort` is not defined for '{s}'\n", .{@tagName(e)});
            return Error.InvalidExpressoinType;
        },
    }
}

pub fn last(args: []const Expression, scope: *Scope) Error!void {
    const elements = args[0];
    const callback = args[1];
    const default_value = args[2];
    std.debug.assert(callback == .function);

    const func = callback.function;
    switch (elements) {
        .array => |a| {
            var iter = std.mem.reverseIterator(a.elements);
            while (iter.next()) |e| {
                var call_args = try scope.allocator.alloc(Expression, 1);
                defer scope.allocator.free(call_args);
                call_args[0] = e;
                try exec_runtime_function(func, call_args, scope);
                if (scope.result()) |r| {
                    if (r == .boolean and r.boolean.value) {
                        scope.return_result = try e.clone(scope.allocator);
                        return;
                    }
                } else {
                    return Error.ValueNotFound;
                }
            }
            scope.return_result = try default_value.clone(scope.allocator);
        },
        .iterator => {
            try iter_has_next(args[0..1], scope);
            var condition = scope.result() orelse unreachable;
            var result: ?*Expression = null;
            while (condition == .boolean and condition.boolean.value) {
                try iter_next(args[0..1], scope);
                const tmp = scope.result_ref() orelse unreachable;
                var call_args = try scope.allocator.alloc(Expression, 1);
                defer scope.allocator.free(call_args);
                call_args[0] = tmp.*;
                try exec_runtime_function(func, call_args, scope);
                if (scope.result()) |r| {
                    if (r == .boolean and r.boolean.value) {
                        if (result) |res| expression.free(scope.allocator, res);
                        result = tmp;
                    }
                } else {
                    return Error.ValueNotFound;
                }
                try iter_has_next(args[0..1], scope);
                condition = scope.result() orelse unreachable;
            }
            scope.return_result = if (result) |r| r else try default_value.clone(scope.allocator);
        },
        else => return Error.NotImplemented,
    }
}

pub fn first(args: []const Expression, scope: *Scope) Error!void {
    const elements = args[0];
    const callback = args[1];
    const default_value = args[2];
    std.debug.assert(callback == .function);

    const func = callback.function;
    switch (elements) {
        .array => |a| {
            for (a.elements) |e| {
                var call_args = try scope.allocator.alloc(Expression, 1);
                defer scope.allocator.free(call_args);
                call_args[0] = e;
                try exec_runtime_function(func, call_args, scope);
                if (scope.result()) |r| {
                    if (r == .boolean and r.boolean.value) {
                        scope.return_result = try e.clone(scope.allocator);
                        return;
                    }
                } else {
                    return Error.ValueNotFound;
                }
            }
            scope.return_result = try default_value.clone(scope.allocator);
        },
        .iterator => {
            const elems = &elements;
            try iter_has_next(elems[0..1], scope);
            var condition = scope.result() orelse unreachable;
            var call_args = try scope.allocator.alloc(Expression, 1);
            defer scope.allocator.free(call_args);
            while (condition == .boolean and condition.boolean.value) {
                try iter_next(elems[0..1], scope);
                const tmp = scope.result() orelse unreachable;
                call_args[0] = tmp;
                try exec_runtime_function(func, call_args, scope);
                if (scope.result()) |r| {
                    if (r == .boolean and r.boolean.value) {
                        scope.return_result = try tmp.clone(scope.allocator);
                        return;
                    }
                } else {
                    return Error.ValueNotFound;
                }
                try iter_has_next(elems[0..1], scope);
                condition = scope.result() orelse unreachable;
            }
            scope.return_result = try default_value.clone(scope.allocator);
        },
        else => return Error.NotImplemented,
    }
}

pub fn print3(args: []const Expression, scope: *Scope) Error!void {
    try interpreter.printValue(args[0], scope);
    _ = scope.out.write("\n") catch return Error.IOWrite;
}

const DEFAULT_INDEX = 1;
const DEFAULT_DATA_INDEX = 0;
fn default_next(data_expr: *Expression, scope: *Scope) Error!void {
    std.debug.assert(data_expr.* == .array);
    const local_data = data_expr.array.elements;
    switch (local_data[DEFAULT_DATA_INDEX]) {
        .array => |a| {
            std.debug.assert(local_data[DEFAULT_INDEX] == .number);
            std.debug.assert(local_data[DEFAULT_INDEX].number == .integer);
            const index = local_data[DEFAULT_INDEX];
            const i: usize = @intCast(index.number.integer);
            scope.return_result = try a.elements[i].clone(scope.allocator);
            local_data[DEFAULT_INDEX] = .{ .number = .{ .integer = @as(i64, @intCast(i)) + 1 } };
            expression.free_local(scope.allocator, index);
        },
        .dictionary => return Error.NotImplemented,
        else => return Error.InvalidExpressoinType,
    }
}

fn default_peek(data_expr: *Expression, scope: *Scope) Error!void {
    std.debug.assert(data_expr.* == .array);
    const local_data = data_expr.array.elements;
    switch (local_data[DEFAULT_DATA_INDEX]) {
        .array => |a| {
            std.debug.assert(local_data[DEFAULT_INDEX] == .number);
            std.debug.assert(local_data[DEFAULT_INDEX].number == .integer);
            const index = local_data[DEFAULT_INDEX];
            const i: usize = @intCast(index.number.integer);
            scope.return_result = try a.elements[i].clone(scope.allocator);
            expression.free_local(scope.allocator, index);
        },
        .dictionary => return Error.NotImplemented,
        else => return Error.InvalidExpressoinType,
    }
}

fn default_has_next(data_expr: *Expression, scope: *Scope) Error!void {
    std.debug.assert(data_expr.* == .array);
    const local_data = data_expr.array.elements;
    switch (local_data[DEFAULT_DATA_INDEX]) {
        .array => |a| {
            std.debug.assert(local_data[DEFAULT_INDEX] == .number);
            std.debug.assert(local_data[DEFAULT_INDEX].number == .integer);
            const n = local_data[DEFAULT_INDEX].number.integer;
            scope.return_result = try expression.Boolean.init(scope.allocator, a.elements.len > @as(usize, @intCast(n)));
        },
        .dictionary => return Error.NotImplemented,
        else => return Error.InvalidExpressoinType,
    }
}

pub fn default_iterator(args: []const Expression, scope: *Scope) Error!void {
    std.debug.assert(args.len == 1);
    switch (args[0]) {
        .iterator => {
            scope.return_result = try args[0].clone(scope.allocator);
        },
        .array => {
            const tmp = try scope.allocator.alloc(Expression, 2);
            tmp[DEFAULT_DATA_INDEX] = args[0];
            tmp[DEFAULT_INDEX] = .{ .number = .{ .integer = 0 } };
            const data_expr = try expression.Array.init(scope.allocator, tmp);
            scope.return_result = try expression.Iterator.initBuiltin(
                scope.allocator,
                &default_next,
                &default_has_next,
                &default_peek,
                data_expr,
            );
        },
        .dictionary => return Error.NotImplemented,
        else => return Error.InvalidExpressoinType,
    }
}

fn custom_iterator(args: []const Expression, scope: *Scope) Error!void {
    std.debug.assert(args.len == 3);
    if (args[0] != .function and args[1] != .function) {
        return Error.InvalidExpressoinType;
    }

    scope.return_result = try expression.Iterator.init(
        scope.allocator,
        args[0].function, // next function
        args[1].function, // has_next function
        try args[2].clone(scope.allocator), // data
    );
}

pub fn iterator(args: []const Expression, scope: *Scope) Error!void {
    const next_fn = args[0];
    const has_next_fn = args[1];
    const data_local = args[2];

    if (next_fn != .function and has_next_fn != .function) {
        return Error.InvalidExpressoinType;
    }

    scope.return_result = try expression.Iterator.init(
        scope.allocator,
        next_fn.function,
        has_next_fn.function,
        try data_local.clone(scope.allocator),
    );
}

pub fn iter_next(args: []const Expression, scope: *Scope) Error!void {
    const iter = args[0];
    std.debug.assert(iter == .iterator);

    switch (iter.iterator.next_fn) {
        .runtime => |f| {
            const tmp = try scope.allocator.alloc(Expression, 1);
            defer scope.allocator.free(tmp);
            tmp[0] = iter.iterator.data.*;
            var local = try Scope.init(scope.allocator, scope.out, scope, f.args, tmp);
            for (f.body) |st| {
                try interpreter.evalStatement(st, &local);
            }
            if (local.result_ref()) |res| {
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

pub fn iter_peek(args: []const Expression, scope: *Scope) Error!void {
    const iter = args[0];
    std.debug.assert(iter == .iterator);

    if (iter.iterator.peek_fn) |func| {
        switch (func) {
            .runtime => |f| {
                const tmp = try scope.allocator.alloc(Expression, 1);
                defer scope.allocator.free(tmp);
                tmp[0] = iter.iterator.data.*;
                try exec_runtime_function(f, iter.iterator.data[0..1], scope);
            },
            .builtin => |f| {
                try f(iter.iterator.data, scope);
            },
        }
    } else {
        const out = try scope.allocator.create(Expression);
        out.* = .{ .none = null };
        scope.return_result = out;
    }
}

pub fn iter_has_next(args: []const Expression, scope: *Scope) Error!void {
    const iter = args[0];
    std.debug.assert(iter == .iterator);

    switch (iter.iterator.has_next_fn) {
        .runtime => |f| {
            const tmp = try scope.allocator.alloc(Expression, 1);
            defer scope.allocator.free(tmp);
            tmp[0] = iter.iterator.data.*;
            var local = try Scope.init(scope.allocator, scope.out, scope, f.args, tmp);
            for (f.body) |st| {
                try interpreter.evalStatement(st, &local);
            }
            if (local.result_ref()) |res| {
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

pub fn array_append(args: []const Expression, scope: *Scope) Error!void {
    std.debug.assert(args.len == 2);
    std.debug.assert(args[0] == .array);

    const out = try scope.allocator.alloc(Expression, args[0].array.elements.len + 1);
    @memcpy(out[0..args[0].array.elements.len], args[0].array.elements);
    out[args[0].array.elements.len] = args[1];
    scope.return_result = try expression.Array.init(scope.allocator, out);
}

pub fn array_contains(args: []const Expression, scope: *Scope) Error!void {
    std.debug.assert(args.len == 2);
    std.debug.assert(args[0] == .array);

    for (args[0].array.elements) |elem| {
        if (elem.eql(args[1])) {
            scope.return_result = try expression.Boolean.init(scope.allocator, true);
            return;
        }
    }
    scope.return_result = try expression.Boolean.init(scope.allocator, false);
}
