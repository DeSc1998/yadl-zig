const std = @import("std");

const value = @import("value.zig");
const compiler = @import("compiler.zig");
const stdlib = @import("stdlib.zig");
const Scope = @import("Scope.zig");

const Error = error{
    NotImplemented,
    IllegalValue,
    EmptyStack,
} || std.mem.Allocator.Error;

const Frame = struct {
    program: compiler.Program,
    stack_ptr: usize = 0,
};

const Maschine = struct {
    registers: [std.math.maxInt(u8) + 1]value.Value = undefined,
    function_table: []const compiler.Program,
    value_stack: std.ArrayList(value.Value),
    frame_stack: std.ArrayList(Frame),
    out: std.io.AnyWriter,
};

pub fn execute_source(source: compiler.CompiledSource, stdout: std.io.AnyWriter) Error!void {
    var frames = std.ArrayList(Frame).init(source.allocator);
    try frames.append(.{ .program = source.main_program, .stack_ptr = 0 });
    var maschine = Maschine{
        .function_table = source.functions,
        .frame_stack = frames,
        .value_stack = std.ArrayList(value.Value).init(source.allocator),
        .out = stdout,
    };

    while (!is_finished(&maschine)) {
        const frame = maschine.frame_stack.getLast();
        const instruction = frame.program.instructions[frame.stack_ptr];
        try execute_instruction(&maschine, instruction);
    }

    maschine.value_stack.deinit();
    maschine.frame_stack.deinit();
}

fn is_finished(m: *const Maschine) bool {
    const current_frame = m.frame_stack.getLastOrNull() orelse return true;
    const frame_count = m.frame_stack.items.len;
    return frame_count == 1 and is_finished_frame(&current_frame);
}

fn is_finished_frame(f: *const Frame) bool {
    return f.stack_ptr >= f.program.instructions.len;
}

fn execute_instruction(m: *Maschine, inst: compiler.Instruction) Error!void {
    var current_frame = m.frame_stack.items.len - 1;
    switch (inst.op_code) {
        .LoadStatic => {
            const addr = inst.argument.address;
            m.registers[7] = m.frame_stack.items[current_frame].program.static_memory[addr];
        },
        .Move => {
            const regs = inst.argument.registers;
            m.registers[regs.destination] = m.registers[regs.source_left];
        },
        .Mul => {
            const regs = inst.argument.registers;
            const left = m.registers[regs.source_left];
            const right = m.registers[regs.source_right];
            switch (left) {
                .number => |l| {
                    if (right != .number) {
                        std.log.err(
                            "can not multiply '{s}' and '{s}': implicit conversion not allowed",
                            .{ @tagName(left), @tagName(right) },
                        );
                        return Error.IllegalValue;
                    }
                    m.registers[regs.destination] = .{ .number = l.mul(right.number) };
                },
                else => |val| {
                    std.log.err(
                        "can not multiply left-side '{s}': implicit conversion not allowed",
                        .{@tagName(val)},
                    );
                    return Error.IllegalValue;
                },
            }
        },
        .Mod => {
            const regs = inst.argument.registers;
            const left = m.registers[regs.source_left];
            const right = m.registers[regs.source_right];
            switch (left) {
                .number => |l| {
                    if (right != .number) {
                        std.log.err(
                            "can not apply modulo to '{s}' and '{s}': implicit conversion not allowed",
                            .{ @tagName(left), @tagName(right) },
                        );
                        return Error.IllegalValue;
                    }
                    m.registers[regs.destination] = .{ .number = l.mod(right.number) };
                },
                else => |val| {
                    std.log.err(
                        "can not apply modulo to left-side '{s}': implicit conversion not allowed",
                        .{@tagName(val)},
                    );
                    return Error.IllegalValue;
                },
            }
        },
        .Div => {
            const regs = inst.argument.registers;
            const left = m.registers[regs.source_left];
            const right = m.registers[regs.source_right];
            switch (left) {
                .number => |l| {
                    if (right != .number) {
                        std.log.err(
                            "can not divide '{s}' and '{s}': implicit conversion not allowed",
                            .{ @tagName(left), @tagName(right) },
                        );
                        return Error.IllegalValue;
                    }
                    m.registers[regs.destination] = .{ .number = l.div(right.number) };
                },
                else => |val| {
                    std.log.err(
                        "can not divide left-side '{s}': implicit conversion not allowed",
                        .{@tagName(val)},
                    );
                    return Error.IllegalValue;
                },
            }
        },
        .Expo => {
            const regs = inst.argument.registers;
            const left = m.registers[regs.source_left];
            const right = m.registers[regs.source_right];
            switch (left) {
                .number => |l| {
                    if (right != .number) {
                        std.log.err(
                            "can not exponatiate '{s}' to '{s}': implicit conversion not allowed",
                            .{ @tagName(left), @tagName(right) },
                        );
                        return Error.IllegalValue;
                    }
                    m.registers[regs.destination] = .{ .number = l.expo(right.number) };
                },
                else => |val| {
                    std.log.err(
                        "can not exponatiate left-side '{s}': implicit conversion not allowed",
                        .{@tagName(val)},
                    );
                    return Error.IllegalValue;
                },
            }
        },
        .Add => {
            const regs = inst.argument.registers;
            const left = m.registers[regs.source_left];
            const right = m.registers[regs.source_right];
            switch (left) {
                .number => |l| {
                    if (right != .number) {
                        std.log.err(
                            "can not add '{s}' and '{s}': implicit conversion not allowed",
                            .{ @tagName(left), @tagName(right) },
                        );
                        return Error.IllegalValue;
                    }
                    m.registers[regs.destination] = .{ .number = l.add(right.number) };
                },
                .string => |l| {
                    if (right != .string) {
                        std.log.err(
                            "can not add '{s}' and '{s}': implicit conversion not allowed",
                            .{ @tagName(left), @tagName(right) },
                        );
                        return Error.IllegalValue;
                    }
                    const res = try std.mem.join(m.frame_stack.allocator, "", &.{ l, right.string });
                    m.registers[regs.destination] = .{ .string = res };
                },
                else => |val| {
                    std.log.err(
                        "can not add left-side '{s}': implicit conversion not allowed",
                        .{@tagName(val)},
                    );
                    return Error.IllegalValue;
                },
            }
        },
        .Sub => {
            const regs = inst.argument.registers;
            const left = m.registers[regs.source_left];
            const right = m.registers[regs.source_right];
            switch (left) {
                .number => |l| {
                    if (right != .number) {
                        std.log.err(
                            "can not subtract '{s}' and '{s}': implicit conversion not allowed",
                            .{ @tagName(left), @tagName(right) },
                        );
                        return Error.IllegalValue;
                    }
                    m.registers[regs.destination] = .{ .number = l.sub(right.number) };
                },
                else => |val| {
                    std.log.err(
                        "can not subtract left-side '{s}': implicit conversion not allowed",
                        .{@tagName(val)},
                    );
                    return Error.IllegalValue;
                },
            }
        },
        .Call => {
            const addr = inst.argument.address;
            const function = m.function_table[addr];
            try m.frame_stack.append(.{
                .program = function,
            });
            return;
        },
        .CallStd => {
            const addr = inst.argument.address;
            const name = stdlib.builtins.keys()[addr];
            const context = stdlib.builtins.get(name) orelse unreachable;
            std.debug.assert(m.registers[0] == .number);
            const size: usize = @intCast(m.registers[0].number.integer);
            const tmp: []value.Value = try m.value_stack.allocator.alloc(value.Value, size);
            defer m.value_stack.allocator.free(tmp);
            for (tmp) |*out| {
                out.* = m.value_stack.pop() orelse unreachable;
            }
            const match = stdlib.match_call_args(tmp, context.arity) catch return Error.IllegalValue;
            var scope = Scope.empty(m.frame_stack.allocator, m.out);
            context.function(match, &scope) catch return Error.IllegalValue;
            if (scope.result()) |result| {
                m.registers[0] = result;
            }
        },
        .CmpEq => {
            const regs = inst.argument.registers;
            const left = m.registers[regs.source_left];
            const right = m.registers[regs.source_right];
            m.registers[regs.destination] = .{ .boolean = left.eql(right) };
        },
        .CmpLess => {
            const regs = inst.argument.registers;
            const left = m.registers[regs.source_left];
            const right = m.registers[regs.source_right];
            if (left == .number and right == .number) {
                const result = left.number.sub(right.number);
                if (result == .integer) {
                    m.registers[regs.destination] = .{ .boolean = result.integer < 0 };
                } else {
                    m.registers[regs.destination] = .{ .boolean = result.float < 0 };
                }
            } else {
                std.log.err("unable to compare under less: {s} and {s}", .{ @tagName(left), @tagName(right) });
                return Error.IllegalValue;
            }
        },
        .Not => {
            const regs = inst.argument.registers;
            const left = m.registers[regs.source_left];
            std.debug.assert(left == .boolean);
            m.registers[regs.destination] = .{ .boolean = !left.boolean };
        },
        .And => {
            const regs = inst.argument.registers;
            const left = m.registers[regs.source_left];
            const right = m.registers[regs.source_right];
            std.debug.assert(left == .boolean);
            std.debug.assert(right == .boolean);
            m.registers[regs.destination] = .{ .boolean = left.boolean and right.boolean };
        },
        .Or => {
            const regs = inst.argument.registers;
            const left = m.registers[regs.source_left];
            const right = m.registers[regs.source_right];
            std.debug.assert(left == .boolean);
            std.debug.assert(right == .boolean);
            m.registers[regs.destination] = .{ .boolean = left.boolean or right.boolean };
        },
        .Push => {
            const regs = inst.argument.registers;
            const dest = regs.destination;
            try m.value_stack.append(m.registers[dest]);
        },
        .Pop => {
            const regs = inst.argument.registers;
            const dest = regs.destination;
            m.registers[dest] = m.value_stack.pop() orelse {
                const stack_ptr = m.frame_stack.items[current_frame].stack_ptr;
                std.log.err("stack was empty @ sp = {}, f = {}", .{
                    stack_ptr,
                    current_frame,
                });
                const stderr = std.io.getStdErr().writer();
                const base = if (stack_ptr >= 5) stack_ptr - 5 else 0;
                for (0..10) |index| {
                    const current = base + index;
                    const i = m.frame_stack.items[current_frame].program.instructions[current];
                    if (current == stack_ptr) {
                        stderr.print("------ current instruction -------\n", .{}) catch unreachable;
                    }
                    i.dump(stderr.any()) catch unreachable;
                    if (current == stack_ptr) {
                        stderr.print("----------------------------------\n", .{}) catch unreachable;
                    }
                }
                std.log.err("------------------------------", .{});
                return Error.EmptyStack;
            };
        },
        .AccessRead => {
            const regs = inst.argument.registers;
            const left = m.registers[regs.source_left];
            const right = m.registers[regs.source_right];

            switch (left) {
                .array => |elements| {
                    if (right != .number) {
                        std.log.err("indexing in array: index is not a number: {s}", .{@tagName(right)});
                        return Error.IllegalValue;
                    }
                    if (right.number != .integer) {
                        std.log.err("indexing in array: index is not an integer: {s}", .{@tagName(right.number)});
                        return Error.IllegalValue;
                    }
                    if (right.number.integer >= elements.len or right.number.integer < 0) {
                        std.log.err("indexing in array: index is out of bounds: index = {}, size = {}", .{ right.number.integer, elements.len });
                        return Error.IllegalValue;
                    }
                    m.registers[regs.destination] = elements[@intCast(right.number.integer)];
                },
                .dictionary => |dict| {
                    if (dict.entries.get(right)) |out| {
                        m.registers[regs.destination] = out;
                    } else {
                        m.registers[regs.destination] = .{ .none = null };
                    }
                },
                else => unreachable,
            }
        },
        .AccessWrite => {
            const regs = inst.argument.registers;
            const dest = m.registers[regs.destination];
            const left = m.registers[regs.source_left];
            const right = m.registers[regs.source_right];

            switch (dest) {
                .array => |elements| {
                    if (left != .number) {
                        std.log.err("indexing in array: index is not a number: {s}", .{@tagName(left)});
                        return Error.IllegalValue;
                    }
                    if (left.number != .integer) {
                        std.log.err("indexing in array: index is not an integer: {s}", .{@tagName(left.number)});
                        return Error.IllegalValue;
                    }
                    if (left.number.integer >= elements.len or left.number.integer < 0) {
                        std.log.err("indexing in array: index is out of bounds: index = {}, size = {}", .{ left.number.integer, elements.len });
                        return Error.IllegalValue;
                    }
                    const index: usize = @intCast(left.number.integer);
                    elements[index] = right;
                },
                .dictionary => |*dict| {
                    try dict.entries.put(left, right);
                },
                else => unreachable,
            }
        },
        .Return => {
            _ = m.frame_stack.pop();
            current_frame = m.frame_stack.items.len - 1;
        },
        .Jmp => {
            const addr = inst.argument.address;
            m.frame_stack.items[current_frame].stack_ptr = addr;
        },
        .JmpOnFalse => {
            const addr = inst.argument.address;
            const condition = m.registers[0];
            std.debug.assert(condition == .boolean);
            if (!condition.boolean) {
                m.frame_stack.items[current_frame].stack_ptr = addr;
            }
        },
        else => {
            std.log.err("not implemented: execution of instruction: {s}", .{@tagName(inst.op_code)});
            return Error.NotImplemented;
        },
    }
    m.frame_stack.items[current_frame].stack_ptr += 1;
}
