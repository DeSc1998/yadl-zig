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
    switch (inst.op_code.major) {
        .Move => {
            if (inst.op_code.minor == .Immidiate) {
                const imm = inst.argument.immidiate;
                m.registers[imm.destination] = .{ .number = .{ .integer = imm.value } };
            } else {
                const regs = inst.argument.registers;
                m.registers[regs.destination] = m.registers[regs.source_left];
            }
        },
        .Mul, .Add, .Div, .Expo, .Mod, .Sub => try execute_arithmetic(m, inst),
        .Call => {
            const addr = inst.argument.address;
            const function = m.function_table[addr];
            try m.frame_stack.append(.{
                .program = function,
            });
            return;
        },
        .CallValue => {
            const regs = inst.argument.registers;
            const func = m.registers[regs.source_left];
            if (regs.source_right != 0)
                m.registers[0] = m.registers[regs.source_right];
            if (func != .function_pointer) {
                std.log.err("called value is not a compiled function: type was '{s}'", .{@tagName(func)});
                try print_trace(m);
                return Error.IllegalValue;
            }
            const pointer = func.function_pointer;
            const sources = compiler.compiled_sources orelse unreachable;
            const source = &sources.items[pointer.source_address];
            const program = source.functions[pointer.function_address];
            try m.frame_stack.append(.{
                .program = program,
            });
            return;
        },
        .CallStd => {
            const addr = inst.argument.address;
            const function = compiler.compiled_sources.?.items[0].functions[addr];
            try m.frame_stack.append(.{
                .program = function,
            });
            return;
        },
        .CallIntr => {
            const addr = inst.argument.address;
            const name = stdlib.intrinsics.keys()[addr];
            const context = stdlib.intrinsics.get(name) orelse unreachable;
            if (m.registers[0] != .number) {
                std.log.err("argument count is not a number: type was {s}", .{@tagName(m.registers[0])});
                try print_trace(m);
                return Error.IllegalValue;
            }
            const size: usize = @intCast(m.registers[0].number.integer);
            const tmp: []value.Value = try m.value_stack.allocator.alloc(value.Value, size);
            defer m.value_stack.allocator.free(tmp);
            var arg_index: usize = 0;
            for (tmp) |*out| {
                out.* = m.value_stack.pop() orelse {
                    std.log.err("stack was empty: tried reading argument at {} from variadic arguments", .{arg_index});
                    try print_trace(m);
                    unreachable;
                };
                arg_index += 1;
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
                const stack_ptr = m.frame_stack.items[current_frame].stack_ptr;
                std.log.err("Illegal compare less @ sp = {}, f = {}", .{
                    stack_ptr,
                    current_frame,
                });
                try print_trace(m);
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
            if (inst.op_code.minor == .Address) {
                const addr = inst.argument.address;
                const tmp = m.frame_stack.items[current_frame].program.memory[addr];
                try m.value_stack.append(tmp);
            } else {
                const regs = inst.argument.registers;
                const dest = regs.destination;
                try m.value_stack.append(m.registers[dest]);
            }
        },

        .Pop => {
            if (inst.op_code.minor == .Address) {
                const addr = inst.argument.address;
                const ptr = &m.frame_stack.items[current_frame].program.memory[addr];
                ptr.* = m.value_stack.pop() orelse {
                    const stack_ptr = m.frame_stack.items[current_frame].stack_ptr;
                    std.log.err("stack was empty @ sp = {}, f = {}", .{
                        stack_ptr,
                        current_frame,
                    });
                    try print_trace(m);
                    return Error.EmptyStack;
                };
            } else {
                const regs = inst.argument.registers;
                const dest = regs.destination;
                m.registers[dest] = m.value_stack.pop() orelse {
                    const stack_ptr = m.frame_stack.items[current_frame].stack_ptr;
                    std.log.err("stack was empty @ sp = {}, f = {}", .{
                        stack_ptr,
                        current_frame,
                    });
                    try print_trace(m);
                    return Error.EmptyStack;
                };
            }
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
            return;
        },
        .JmpOnFalse => {
            const addr = inst.argument.address;
            const condition = m.registers[0];
            std.debug.assert(condition == .boolean);
            if (!condition.boolean) {
                m.frame_stack.items[current_frame].stack_ptr = addr;
                return;
            }
        },
        .Write => {
            if (inst.op_code.minor == .Immidiate) {
                const imm = inst.argument.immidiate;
                m.frame_stack.items[current_frame].program.memory[imm.value] = m.registers[imm.destination];
            } else {
                const regs = inst.argument.registers;
                const dest = m.registers[regs.destination];
                const left = m.registers[regs.source_left];
                std.debug.assert(dest == .address);
                m.frame_stack.items[current_frame].program.memory[dest.address] = left;
            }
        },
        .Read => {
            if (inst.op_code.minor == .Immidiate) {
                const imm = inst.argument.immidiate;
                const tmp = m.frame_stack.items[current_frame].program.memory[imm.value];
                m.registers[imm.destination] = tmp;
            } else {
                const regs = inst.argument.registers;
                const left = m.registers[regs.source_left];
                std.debug.assert(left == .address);
                if (m.frame_stack.items[current_frame].program.memory.len > left.address) {
                    const tmp = m.frame_stack.items[current_frame].program.memory[left.address];
                    m.registers[regs.destination] = tmp;
                } else {
                    std.log.err("accessed out of bound: memory size: {}, address: {}", .{
                        m.frame_stack.items[current_frame].program.memory.len,
                        left.address,
                    });
                    try print_trace(m);
                    return Error.IllegalValue;
                }
            }
        },
        .Capture => {
            const reg = inst.argument.registers;
            const val = m.registers[reg.source_left];
            if (m.registers[reg.destination] != .function_pointer) {
                std.log.err("destination was not a function_pointer: was {s}", .{
                    @tagName(m.registers[reg.destination]),
                });
                try print_trace(m);
                return Error.IllegalValue;
            }
            const fp = m.registers[reg.destination].function_pointer;
            // if (fp.captures) |captures| {
            //     var iter = captures.valueIterator();
            //     while (iter.next()) |entry_value| {
            //         if (entry_value.addr == reg.source_right) {
            //             entry_value.val = val;
            //             break;
            //         }
            //     }
            // }
            const source = &(compiler.compiled_sources orelse unreachable).items[fp.source_address];
            const function = source.functions[fp.function_address];
            function.memory[reg.source_right] = val;
        },
    }
    m.frame_stack.items[current_frame].stack_ptr += 1;
}

fn op_name(code: compiler.MajorCode) []const u8 {
    return switch (code) {
        .Add => "add",
        .Sub => "subtract",
        .Mul => "multiply",
        .Div => "divide",
        .Expo => "exponatiate",
        .Mod => "modulo",
        else => unreachable,
    };
}

fn execute_arithmetic(m: *Maschine, inst: compiler.Instruction) Error!void {
    const regs = inst.argument.registers;
    const left = m.registers[regs.source_left];
    const right = m.registers[regs.source_right];
    const name = op_name(inst.op_code.major);
    switch (left) {
        .number => |l| {
            if (right != .number) {
                std.log.err(
                    "can not {s} '{s}' and '{s}': implicit conversion not allowed",
                    .{ name, @tagName(left), @tagName(right) },
                );
                try print_trace(m);
                return Error.IllegalValue;
            }
            if (inst.op_code.minor == .Register) {
                switch (inst.op_code.major) {
                    .Add => m.registers[regs.destination] = .{ .number = l.add(right.number) },
                    .Sub => m.registers[regs.destination] = .{ .number = l.sub(right.number) },
                    .Mul => m.registers[regs.destination] = .{ .number = l.mul(right.number) },
                    .Mod => m.registers[regs.destination] = .{ .number = l.mod(right.number) },
                    .Div => m.registers[regs.destination] = .{ .number = l.div(right.number) },
                    .Expo => m.registers[regs.destination] = .{ .number = l.expo(right.number) },
                    else => {
                        std.log.err("reached unreachable: code was {s}", .{@tagName(inst.op_code.major)});
                        unreachable;
                    },
                }
            } else if (inst.op_code.minor == .Immidiate) {
                std.log.err("todo: implement Immidiate path of {s}", .{@tagName(inst.op_code.major)});
                return Error.NotImplemented;
            }
        },
        .string => |l| {
            if (inst.op_code.major != .Add) {
                std.log.err("strings can only be added", .{});
                try print_trace(m);
                return Error.IllegalValue;
            }
            if (right != .string) {
                std.log.err(
                    "can not add '{s}' and '{s}': implicit conversion not allowed",
                    .{ @tagName(left), @tagName(right) },
                );
                try print_trace(m);
                return Error.IllegalValue;
            }
            const res = try std.mem.join(m.frame_stack.allocator, "", &.{ l, right.string });
            m.registers[regs.destination] = .{ .string = res };
        },
        else => |val| {
            std.log.err(
                "can not {s} left-side '{s}': implicit conversion not allowed",
                .{ name, @tagName(val) },
            );
            try print_trace(m);
            return Error.IllegalValue;
        },
    }
}

fn print_trace(m: *Maschine) !void {
    const frame = m.frame_stack.items[m.frame_stack.items.len - 1];
    const stack_ptr = frame.stack_ptr;
    const stderr = std.io.getStdErr();
    const writer = stderr.writer();
    const base = if (stack_ptr >= 5) stack_ptr - 5 else 0;
    const total_instructions = frame.program.instructions.len;
    const view_size: usize = @min(10, @max(total_instructions - base, 0));
    std.log.err("current stack ptr: {}, frame: {}, inst count: {}", .{
        frame.stack_ptr,
        m.frame_stack.items.len - 1,
        frame.program.instructions.len,
    });
    writer.print("---- instruction view -----------\n", .{}) catch unreachable;
    for (0..view_size) |index| {
        const current = base + index;
        const i = frame.program.instructions[current];
        if (current == stack_ptr) {
            writer.print("---- current instruction ----\n", .{}) catch unreachable;
        }
        i.dump(stderr, current) catch unreachable;
        if (current == stack_ptr) {
            writer.print("-----------------------------\n", .{}) catch unreachable;
        }
    }
    writer.print("---------------------------------\n", .{}) catch unreachable;
    writer.print("---- registers ------------------\n", .{}) catch unreachable;
    for (m.registers[0..16], 0..) |reg, index| {
        writer.print("reg@{}: {s} ", .{ index, @tagName(reg) }) catch unreachable;
        var scope = Scope.empty(m.frame_stack.allocator, writer.any());
        stdlib.functions.printValue(reg, &scope) catch unreachable;
        _ = stderr.write("\n") catch unreachable;
    }
    writer.print("---------------------------------\n", .{}) catch unreachable;
}
