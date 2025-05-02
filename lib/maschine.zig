const std = @import("std");

const value = @import("value.zig");
const compiler = @import("compiler.zig");
const stdlib = @import("stdlib.zig");
const Scope = @import("Scope.zig");

const Error = error{
    NotImplemented,
    IllegalValue,
} || std.mem.Allocator.Error;

const Frame = struct {
    program: compiler.Program,
    stack_ptr: usize,
};

const Maschine = struct {
    registers: [std.math.maxInt(u8)]value.Value = undefined,
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
        const frame = &maschine.frame_stack.items[maschine.frame_stack.items.len - 1];
        const instruction = frame.program.instructions[frame.stack_ptr];
        try execute_instruction(&maschine, instruction);
        if (is_finished_frame(frame)) {
            _ = maschine.frame_stack.pop();
        }
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
    const current_frame = m.frame_stack.items.len - 1;
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
        .CallStd => {
            const addr = inst.argument.address;
            const name = stdlib.builtins.keys()[addr];
            const context = stdlib.builtins.get(name) orelse unreachable;
            std.debug.assert(m.registers[0] == .number);
            const size: usize = @intCast(m.registers[0].number.integer);
            var tmp: []value.Value = try m.value_stack.allocator.alloc(value.Value, size);
            defer m.value_stack.allocator.free(tmp);
            for (0..tmp.len) |index| {
                const v = m.value_stack.pop() orelse unreachable;
                tmp[tmp.len - index - 1] = v;
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
        .Push => {
            const regs = inst.argument.registers;
            const dest = regs.destination;
            try m.value_stack.append(m.registers[dest]);
        },
        .Pop => {
            const regs = inst.argument.registers;
            const dest = regs.destination;
            m.registers[dest] = m.value_stack.pop() orelse unreachable;
        },
        else => {
            std.log.err("not implemented: execution of instruction: {s}", .{@tagName(inst.op_code)});
            return Error.NotImplemented;
        },
    }
    m.frame_stack.items[current_frame].stack_ptr += 1;
}
