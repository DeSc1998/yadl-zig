const std = @import("std");

const Parser = @import("Parser.zig");
const Scope = @import("Scope.zig");
const statement = @import("statement.zig");
const expression = @import("expression.zig");
const value = @import("value.zig");
const stdlib = @import("stdlib.zig");

pub const Error = error{
    NotImplemented,
    UndefinedFunction,
    RedefinedFunction,
    NotEnoughArguments,
    ToManyArguments,
    UndefinedVariable,
    IllegalReturn,
    NonComptimeValue,
    ParserError,
} || std.mem.Allocator.Error;

pub const MajorCode = enum(u6) {
    // Register OpCodes
    // layout: (op_code, destination, source_left, source_right)
    Add,
    Sub,
    Mul,
    Div,
    Expo,
    Mod,

    Not, // NOTE: Unary Op, right register is ignored
    And,
    Or,

    CmpEq,
    CmpLess,

    /// `source_left` is accessed with `source_right`
    AccessRead,
    /// puts `source_right` in `destination` at index `source_left`
    AccessWrite,
    /// puts the contents of `destination` on the stack
    Push,
    /// removes the top element on the stack and puts it into `destination`
    Pop,
    /// Unary Op, `source_right` is ignored
    Move,
    /// call arguments are expected to be on the stack.
    /// first argument is on the top
    CallValue,

    /// as Register: reads at address `source_left`
    /// as Immidiate: reads the value `value` to `destination`
    Read,
    /// writes `source_left` at address `destination`
    Write,
    /// puts `source_right` at `source_left` (aka capture index)
    /// in the function pointer at `destination`
    Capture,
    /// puts `source_right` at `source_left` (aka capture index)
    /// in the function pointer at `destination`
    // ReadCapture,

    // Address OpCodes
    // layout: (op_code, address)
    /// NOTE: does not advance the stack pointer after jump
    Jmp,
    /// NOTE: does not advance the stack pointer after jump
    JmpOnFalse,

    // /// `address` is interpreted as size.
    // /// puts the returned address at `Compiler.var_offset - 1`
    // Allocate,

    /// call arguments are expected to be on the stack.
    /// first argument is on the top
    Call,
    /// call arguments are expected to be on the stack.
    /// first argument is on the top
    CallStd,
    /// Call to Intrinsic/buildin function:
    /// call arguments are expected to be on the stack.
    /// first argument is on the top
    CallIntr,
    Return,
};

pub const MinorCode = enum(u2) {
    Register,
    Immidiate,
    Address,
};

const OpCode = packed struct(u8) {
    major: MajorCode,
    minor: MinorCode,
};

pub fn is_address_opcode(op: OpCode) bool {
    return op.minor == .Address;
}

const ScopeKind = enum {
    Global,
    Local,
};

pub const Instruction = packed struct(u32) {
    op_code: OpCode,
    argument: packed union {
        registers: Registers,
        address: u24,
        immidiate: Immidiate,
    },

    const Registers = packed struct(u24) {
        destination: u8,
        source_left: u8,
        source_right: u8,
    };

    /// Reads and/or Writes to `destination`
    const Immidiate = packed struct(u24) {
        destination: u8,
        value: u16,
    };

    fn register(code: MajorCode, dest: u8, left: ?u8, right: ?u8) Instruction {
        return .{
            .op_code = .{ .major = code, .minor = .Register },
            .argument = .{ .registers = .{
                .destination = dest,
                .source_left = if (left) |l| l else 0,
                .source_right = if (right) |r| r else 0,
            } },
        };
    }

    fn immidiate(code: MajorCode, dest: u8, val: u16) Instruction {
        return .{
            .op_code = .{ .major = code, .minor = .Immidiate },
            .argument = .{ .immidiate = .{
                .destination = dest,
                .value = val,
            } },
        };
    }

    fn address(code: MajorCode, addr: u24) Instruction {
        return .{
            .op_code = .{ .major = code, .minor = .Address },
            .argument = .{ .address = addr },
        };
    }

    fn color_of(op_code: OpCode) std.io.tty.Color {
        const Color = std.io.tty.Color;
        return switch (op_code.major) {
            .Move => Color.yellow,
            .Add, .Sub, .Mul, .Mod, .Div, .Expo => Color.bright_cyan,
            .CmpEq, .CmpLess, .And, .Or, .Not => Color.bright_blue,
            .AccessRead, .AccessWrite, .Read, .Write => Color.magenta,
            .Call, .CallStd, .CallIntr, .CallValue => Color.green,
            .Jmp, .JmpOnFalse => Color.red,
            else => Color.white,
        };
    }

    fn boldness_of(op_code: OpCode) std.io.tty.Color {
        const Color = std.io.tty.Color;
        return if (is_address_opcode(op_code)) Color.bold else Color.dim;
    }

    pub fn dump(self: Instruction, file: std.fs.File, offset: usize) !void {
        if (!file.isTty()) {
            try self.dump_to_file(file, offset);
        } else {
            try self.dump_to_console(file, offset);
        }
    }

    fn dump_to_file(self: Instruction, file: std.fs.File, offset: usize) !void {
        const writer = file.writer();
        try writer.print(" 0x{X:0>6}", .{offset});
        if (is_address_opcode(self.op_code)) {
            const addr = self.argument.address;
            try writer.print(" {s:<10}", .{@tagName(self.op_code.major)});
            try writer.print(" 0x{X:0>6}", .{addr});
            if (self.op_code.major == .Jmp) {
                if (self.argument.address > offset) {
                    _ = try writer.write(" // end of positive if branch");
                } else {
                    _ = try writer.write(" // end of while loop");
                }
            } else if (self.op_code.major == .CallIntr) {
                const name = stdlib.builtins.keys()[self.argument.address];
                _ = try writer.print(" // Intrinsic: {s}", .{name});
            } else if (self.op_code.major == .CallStd) {
                const source = &(compiled_sources orelse unreachable).items[0];
                var iter = source.function_table.iterator();
                while (iter.next()) |entry| {
                    if (addr == entry.value_ptr.offset) {
                        _ = try writer.print(" // Std Function: {s}", .{entry.key_ptr.*});
                        break;
                    }
                }
            }
        } else {
            const regs = self.argument.registers;
            var tmp: [32]u8 = undefined;
            const name = try std.fmt.bufPrint(&tmp, "{s}{s}", .{
                @tagName(self.op_code.major),
                if (self.op_code.minor == .Immidiate) "Imm" else "",
            });
            try writer.print(" {s:<8}", .{name});
            switch (self.op_code.major) {
                .Move, .Not, .Read, .Write => try writer.print(" {} <- {}", .{
                    regs.destination,
                    regs.source_left,
                }),
                .Push, .Pop => try writer.print(" {}", .{regs.destination}),
                else => try writer.print(" {} <- {} {}", .{
                    regs.destination,
                    regs.source_left,
                    regs.source_right,
                }),
            }
        }
        _ = try writer.write("\n");
    }

    fn dump_to_console(self: Instruction, file: std.fs.File, offset: usize) !void {
        const tty_config = std.io.tty.detectConfig(file);
        const writer = file.writer();
        try writer.print(" 0x{X:0>6}", .{offset});
        if (is_address_opcode(self.op_code)) {
            const addr = self.argument.address;
            const color = color_of(self.op_code);
            const boldness = boldness_of(self.op_code);
            try std.io.tty.Config.setColor(tty_config, writer, color);
            try std.io.tty.Config.setColor(tty_config, writer, boldness);
            try writer.print(" {s:<10}", .{@tagName(self.op_code.major)});
            try std.io.tty.Config.setColor(tty_config, writer, .reset);
            try writer.print(" 0x{X:0>6}", .{addr});
            try std.io.tty.Config.setColor(tty_config, writer, .green);
            try std.io.tty.Config.setColor(tty_config, writer, .dim);
            if (self.op_code.major == .Jmp) {
                if (self.argument.address > offset) {
                    _ = try writer.write(" // end of positive if branch");
                } else {
                    _ = try writer.write(" // end of while loop");
                }
            } else if (self.op_code.major == .CallIntr) {
                const name = stdlib.builtins.keys()[self.argument.address];
                _ = try writer.print(" // Intrinsic: {s}", .{name});
            } else if (self.op_code.major == .CallStd) {
                const source = &(compiled_sources orelse unreachable).items[0];
                var iter = source.function_table.iterator();
                while (iter.next()) |entry| {
                    if (addr == entry.value_ptr.offset) {
                        _ = try writer.print(" // Std Function: {s}", .{entry.key_ptr.*});
                        break;
                    }
                }
            }
            try std.io.tty.Config.setColor(tty_config, writer, .reset);
        } else {
            const regs = self.argument.registers;
            const color = color_of(self.op_code);
            var tmp: [32]u8 = undefined;
            try std.io.tty.Config.setColor(tty_config, writer, color);
            const name = try std.fmt.bufPrint(&tmp, "{s}{s}", .{
                @tagName(self.op_code.major),
                if (self.op_code.minor == .Immidiate) "Imm" else "",
            });
            try writer.print(" {s:<8}", .{name});
            try std.io.tty.Config.setColor(tty_config, writer, .reset);
            switch (self.op_code.major) {
                .Move, .Not, .Read, .Write => try writer.print(" {} <- {}", .{
                    regs.destination,
                    regs.source_left,
                }),
                .Push, .Pop => try writer.print(" {}", .{regs.destination}),
                else => try writer.print(" {} <- {} {}", .{
                    regs.destination,
                    regs.source_left,
                    regs.source_right,
                }),
            }
        }
        _ = try writer.write("\n");
    }
};

pub const Program = struct {
    instructions: []const Instruction,
    memory: []value.Value = &.{},
};

pub const CaptureMap = std.StringHashMap(usize);

const FunctionData = struct {
    offset: u24,
    source_offset: usize,
    arity: expression.Arity,
    captures: ?CaptureMap = null,
};
const FunctionTable = std.StringHashMap(FunctionData);
const VariableTable = std.StringHashMap(usize);

pub const CompiledSource = struct {
    allocator: std.mem.Allocator,
    main_program: Program,
    functions: []const Program,
    function_table: FunctionTable,

    pub fn deinit(self: *CompiledSource) void {
        self.allocator.free(self.main_program.instructions);
        for (self.functions) |f| {
            self.allocator.free(f.instructions);
        }
        self.allocator.free(self.functions);
        self.function_table.deinit();
    }

    pub fn dump(self: CompiledSource, file: std.fs.File) !void {
        const writer = file.writer();
        for (self.functions, 0..) |f, offset| {
            var iter = self.function_table.iterator();
            var function_found = false;
            while (iter.next()) |entry| {
                if (entry.value_ptr.offset == offset) {
                    try writer.print("{s} @ 0x{X}:\n", .{ entry.key_ptr.*, offset });
                    function_found = true;
                    break;
                }
            }
            if (!function_found) {
                try writer.print("anonimous-function @ {}:\n", .{offset});
            }
            for (f.memory, 0..) |v, index| {
                try writer.print("  memory @ 0x{X}: {s} ", .{ index, @tagName(v) });
                var scope = Scope.empty(self.allocator, writer.any());
                stdlib.functions.printValue(v, &scope) catch unreachable;
                _ = writer.write("\n") catch unreachable;
            }
            for (f.instructions, 0..) |inst, index| {
                try inst.dump(file, index);
            }
            if (self.functions.len - 1 > offset)
                try writer.print("------------------\n", .{});
        }

        try writer.print("entry point:\n", .{});
        for (self.main_program.memory, 0..) |v, index| {
            try writer.print("memory @ 0x{X}: {s} ", .{ index, @tagName(v) });
            var scope = Scope.empty(self.allocator, writer.any());
            stdlib.functions.printValue(v, &scope) catch unreachable;
            _ = writer.write("\n") catch unreachable;
        }
        try writer.print("------------------\n", .{});
        for (self.main_program.instructions, 0..) |inst, index| {
            try inst.dump(file, index);
        }
    }
};

const Compiler = struct {
    root: ?*Compiler = null,
    main: std.ArrayList(Instruction),
    functions: std.ArrayList(Program),
    function_table: FunctionTable,
    var_table: VariableTable,
    static_mem: std.ArrayList(value.Value),
    stdlib: ?*CompiledSource = null,
    compiles_stdlib: bool = false,

    const load_address: u8 = 255;

    fn init(allocator: std.mem.Allocator) Compiler {
        var tmp = std.ArrayList(value.Value).init(allocator);
        tmp.append(value.Value{ .number = .{ .integer = 0 } }) catch @panic("OOM");
        return .{
            .main = std.ArrayList(Instruction).init(allocator),
            .functions = std.ArrayList(Program).init(allocator),
            .function_table = FunctionTable.init(allocator),
            .var_table = VariableTable.init(allocator),
            .static_mem = tmp,
        };
    }

    fn local(self: *Compiler) Compiler {
        var tmp = Compiler.init(self.main.allocator);
        tmp.root = self;
        tmp.stdlib = self.stdlib;
        tmp.compiles_stdlib = self.compiles_stdlib;
        return tmp;
    }

    fn get_function(self: *Compiler, name: []const u8) ?FunctionData {
        return self.function_table.get(name) orelse if (self.root) |p| p.get_function(name) else null;
    }

    fn get_stdlib_function(self: *Compiler, name: []const u8) ?FunctionData {
        if (self.stdlib) |lib| {
            return lib.function_table.get(name) orelse null;
        } else return null;
    }

    // fn get_variable(self: *Compiler, name: []const u8) ?usize {
    //     return self.var_table.get(name) orelse if (self.root) |p| p.get_variable(name) else null;
    // }

    fn is_local_function(self: *Compiler, name: []const u8) bool {
        return if (self.function_table.get(name)) |_| true else false;
    }

    fn global_function_offset(self: Compiler) u24 {
        const parent_count = if (self.root) |r|
            r.global_function_offset()
        else
            0;
        return parent_count + @as(u24, @truncate(self.functions.items.len));
    }
};

pub var compiled_stdlib: ?*CompiledSource = null;
pub var compiled_sources: ?std.ArrayList(CompiledSource) = null;

pub fn compile_stdlib(allocator: std.mem.Allocator) Error!*CompiledSource {
    if (compiled_sources) |sources| {
        std.debug.assert(sources.items.len > 0);
        return &sources.items[0];
    } else {
        const lib_source = @import("yadl-stdlib").source;
        var parser = Parser.init(lib_source, allocator);
        const statements = parser.parse() catch |err| {
            std.log.err("not implemented: handling of failed parsing: {}", .{err});
            return Error.ParserError;
        };
        var compiler = Compiler.init(allocator);
        compiler.compiles_stdlib = true;
        try compile_program(&compiler, statements);
        compiled_sources = std.ArrayList(CompiledSource).init(allocator);
        compiler.var_table.deinit();
        const tmp = try compiled_sources.?.addOne();
        tmp.* = .{
            .allocator = allocator,
            .main_program = .{
                .instructions = try compiler.main.toOwnedSlice(),
                .memory = try compiler.static_mem.toOwnedSlice(),
            },
            .functions = try compiler.functions.toOwnedSlice(),
            .function_table = compiler.function_table,
        };
        return tmp;
    }
}

pub fn compile_source(source: []const u8, allocator: std.mem.Allocator) Error!CompiledSource {
    var parser = Parser.init(source, allocator);
    const statements = parser.parse() catch |err| {
        std.log.err("not implemented: handling of failed parsing: {}", .{err});
        return Error.ParserError;
    };
    var compiler = Compiler.init(allocator);
    compiler.stdlib = try compile_stdlib(allocator);
    try compile_program(&compiler, statements);
    compiler.var_table.deinit();
    const sources = &(compiled_sources orelse unreachable);
    const tmp = try sources.addOne();
    tmp.* = .{
        .allocator = allocator,
        .main_program = .{
            .instructions = try compiler.main.toOwnedSlice(),
            .memory = try compiler.static_mem.toOwnedSlice(),
        },
        .functions = try compiler.functions.toOwnedSlice(),
        .function_table = compiler.function_table,
    };
    return tmp.*;
}

fn compile_program(compiler: *Compiler, statements: []const statement.Statement) Error!void {
    for (statements) |st| {
        try compile_statment(compiler, st, .Global);
    }
}

fn compile_function(
    compiler: *Compiler,
    func: expression.Function,
    func_slot: ?*Program,
) Error!FunctionData {
    var tmp = compiler.local();
    // NOTE: anything which is either local or does not need to be captured (i. e. stdlib functions)
    var locals = std.StringHashMap(?void).init(compiler.main.allocator);
    defer locals.deinit();
    var externals = std.ArrayList(expression.Identifier).init(compiler.main.allocator);
    for (func.arity.args) |arg| {
        try locals.put(arg.name, null);
    }
    if (func.arity.var_args) |var_args|
        try locals.put(var_args.name, null);
    for (stdlib.builtins.keys()) |key| {
        try locals.put(key, null);
    }
    if (compiled_sources) |ss| {
        for (ss.items) |source| {
            var keys = source.function_table.keyIterator();
            while (keys.next()) |key| {
                try locals.put(key.*, null);
            }
        }
    }
    var keys = compiler.function_table.keyIterator();
    while (keys.next()) |key| {
        try locals.put(key.*, null);
    }

    try externals_of_function(func, &externals, &locals);
    var captures = std.StringHashMap(usize).init(compiler.main.allocator);
    for (externals.items) |ext| {
        const offset = tmp.static_mem.items.len;
        try captures.put(ext.name, offset);
        try tmp.var_table.put(ext.name, offset);
        try tmp.static_mem.append(.{ .none = null });
    }
    try compile_function_arguments(&tmp, func.arity);
    for (func.body) |st| {
        try compile_statment(&tmp, st, .Local);
    }
    if (tmp.main.items[tmp.main.items.len - 1].op_code.major != .Return)
        try tmp.main.append(Instruction.address(.Return, 0));
    if (tmp.compiles_stdlib) {
        for (tmp.main.items) |*inst| {
            if (inst.op_code.major == .Call) {
                inst.op_code.major = .CallStd;
            }
        }
    }
    const prog = Program{
        .instructions = try tmp.main.toOwnedSlice(),
        .memory = try tmp.static_mem.toOwnedSlice(),
    };
    const tmp_funcs = try tmp.functions.toOwnedSlice();
    defer tmp.functions.allocator.free(tmp_funcs);
    try compiler.functions.appendSlice(tmp_funcs);
    if (func_slot) |slot| {
        slot.* = prog;
        return FunctionData{
            .offset = 0,
            .source_offset = 0,
            .arity = func.arity,
            .captures = captures,
        };
    } else {
        const offset: u24 = tmp.global_function_offset();
        try compiler.functions.append(prog);
        return FunctionData{
            .offset = offset,
            .source_offset = if (compiled_sources) |ss| ss.items.len else 0,
            .arity = func.arity,
            .captures = captures,
        };
    }
}

fn externals_of_function(
    function: expression.Function,
    externals: *std.ArrayList(expression.Identifier),
    locals: *std.StringHashMap(?void),
) !void {
    for (function.body) |stmt| {
        try externals_of_statement(stmt, externals, locals);
    }
}

fn externals_of_statement(
    stmt: statement.Statement,
    externals: *std.ArrayList(expression.Identifier),
    locals: *std.StringHashMap(?void),
) !void {
    switch (stmt) {
        .assignment => |ass| {
            try externals_of_expression(ass.value, externals, locals);
            try locals.put(ass.varName.name, null);
        },
        .functioncall => |fc| {
            try externals_of_expression(fc.func, externals, locals);
            for (fc.args) |*arg| {
                try externals_of_expression(arg, externals, locals);
            }
        },
        .if_statement => |i| {
            try externals_of_expression(i.ifBranch.condition, externals, locals);
            for (i.ifBranch.body) |st| {
                try externals_of_statement(st, externals, locals);
            }
            if (i.elseBranch) |branch| {
                for (branch) |st| {
                    try externals_of_statement(st, externals, locals);
                }
            }
        },
        .whileloop => |w| {
            try externals_of_expression(w.loop.condition, externals, locals);
            for (w.loop.body) |st| {
                try externals_of_statement(st, externals, locals);
            }
        },
        .@"return" => |r| {
            try externals_of_expression(r.value, externals, locals);
        },
        .struct_assignment => |sa| {
            try externals_of_expression(sa.access, externals, locals);
            try externals_of_expression(sa.value, externals, locals);
        },
    }
}

fn externals_of_expression(
    expr: *const expression.Expression,
    externals: *std.ArrayList(expression.Identifier),
    locals: *std.StringHashMap(?void),
) !void {
    switch (expr.*) {
        .identifier => |id| {
            // std.log.info("checking {s}: {s}", .{ @tagName(expr.*), id.name });
            if (!locals.contains(id.name)) {
                // std.log.info("'{s}' not found locally", .{id.name});
                try externals.append(id);
            }
        },
        .binary_op => |bin| {
            try externals_of_expression(bin.left, externals, locals);
            try externals_of_expression(bin.right, externals, locals);
        },
        .unary_op => |un| {
            try externals_of_expression(un.operant, externals, locals);
        },
        .functioncall => |fc| {
            try externals_of_expression(fc.func, externals, locals);
            for (fc.args) |*arg| {
                try externals_of_expression(arg, externals, locals);
            }
        },
        .struct_access => |sa| {
            try externals_of_expression(sa.strct, externals, locals);
            try externals_of_expression(sa.key, externals, locals);
        },
        .wrapped => |ex| {
            try externals_of_expression(ex, externals, locals);
        },
        else => {},
    }
}

fn compile_function_arguments(compiler: *Compiler, arity: value.Arity) Error!void {
    for (arity.args) |arg| {
        const addr = compiler.static_mem.items.len;
        try compiler.static_mem.append(value.Value{ .none = null });
        try compiler.var_table.put(arg.name, addr);
        try compiler.main.append(Instruction.address(.Pop, @intCast(addr)));
    }

    if (arity.var_args) |id| {
        const var_count = expression.Expression{ .value = .{ .number = .{ .integer = @intCast(arity.args.len) } } };
        const constant_two = expression.Expression{ .value = .{ .number = .{ .integer = 2 } } };
        // layout(0..4): [compare_res, tmp_array, var_arg_count]
        const compare_reg: u8 = 0;
        const tmp_array_reg: u8 = 1;
        const arg_count_reg: u8 = 2;
        // var_arg_count = total_var_count - named_var_count
        try compile_expression(compiler, &var_count, Compiler.load_address);
        try compiler.main.append(Instruction.register(.Sub, arg_count_reg, 0, Compiler.load_address));
        // tmp_array = []
        const empty_array = expression.Expression{ .value = .{ .array = &.{} } };
        try compile_expression(compiler, &empty_array, tmp_array_reg);

        const start_loop = @as(u24, @truncate(compiler.main.items.len));
        // while (var_arg_count != 0) {
        try compiler.main.append(Instruction.immidiate(.Read, 3, 0));
        try compiler.main.append(
            Instruction.register(.CmpEq, compare_reg, arg_count_reg, 3),
        );
        try compiler.main.append(Instruction.register(.Not, compare_reg, compare_reg, null));
        const jmp_index = @as(u24, @truncate(compiler.main.items.len));
        try compiler.main.append(Instruction.address(.JmpOnFalse, 0));
        // tmp_array = append(tmp_array, tmp_arg)
        try compiler.main.append(Instruction.register(.Push, tmp_array_reg, null, null));
        try compile_expression(compiler, &constant_two, 0);
        const addr = stdlib.builtins.getIndex("append") orelse unreachable;
        try compiler.main.append(Instruction.address(.CallIntr, @as(u24, @truncate(addr))));
        try compiler.main.append(Instruction.register(.Move, tmp_array_reg, 0, null));
        // var_arg_count -= 1
        const one = expression.Expression{ .value = .{ .number = .{ .integer = 1 } } };
        try compile_expression(compiler, &one, Compiler.load_address);
        try compiler.main.append(
            Instruction.register(.Sub, arg_count_reg, arg_count_reg, Compiler.load_address),
        );
        try compiler.main.append(Instruction.address(.Jmp, start_loop));
        const end_loop = @as(u24, @truncate(compiler.main.items.len));
        compiler.main.items[jmp_index].argument.address = end_loop;
        // }

        const var_addr = compiler.static_mem.items.len;
        try compiler.static_mem.append(value.Value{ .none = null });
        try compiler.var_table.put(id.name, var_addr);
        const address: expression.Expression = .{ .value = .{ .address = var_addr } };
        try compile_expression(compiler, &address, 0);
        try compiler.main.append(Instruction.register(.Write, 0, tmp_array_reg, null));
    }
}

fn compile_statment(compiler: *Compiler, st: statement.Statement, kind: ScopeKind) Error!void {
    return sw: switch (st) {
        .assignment => |a| {
            if (a.value.* == .value and a.value.value == .function) {
                if (compiler.function_table.get(a.varName.name)) |_| {
                    std.log.err(
                        "function '{s}' has already been defined in the current scope",
                        .{a.varName.name},
                    );
                    break :sw Error.RedefinedFunction;
                }
                const func = a.value.value.function;
                const addr: u24 = compiler.global_function_offset();
                try compiler.function_table.put(a.varName.name, .{
                    .offset = addr,
                    .source_offset = if (compiled_sources) |ss| ss.items.len else 0,
                    .arity = func.arity,
                });
                const func_slot = try compiler.functions.addOne();
                // std.log.info("compiling function: {s}", .{a.varName.name});
                const data = try compile_function(compiler, func, func_slot);
                if (data.captures) |cs| {
                    const tmp = compiler.function_table.getPtr(a.varName.name) orelse unreachable;
                    tmp.captures = cs;
                }
                return;
            }

            if (compiler.var_table.get(a.varName.name)) |addr| {
                if (addr <= std.math.maxInt(u16)) {
                    try compile_expression(compiler, a.value, 1);
                    try compiler.main.append(Instruction.immidiate(.Write, 1, @intCast(addr)));
                } else {
                    const address_value: expression.Expression = .{ .value = .{ .address = addr } };
                    try compile_expression(compiler, a.value, 1);
                    try compile_expression(compiler, &address_value, Compiler.load_address);
                    try compiler.main.append(Instruction.register(.Write, Compiler.load_address, 1, null));
                }
            } else {
                const addr: usize = compiler.static_mem.items.len;
                try compiler.static_mem.append(value.Value{ .none = null });
                try compiler.var_table.put(a.varName.name, addr);
                const address: expression.Expression = .{ .value = .{ .address = addr } };
                try compile_expression(compiler, a.value, 1);
                try compile_expression(compiler, &address, Compiler.load_address);
                try compiler.main.append(Instruction.register(.Write, Compiler.load_address, 1, null));
            }
        },
        .@"return" => |r| {
            if (kind == .Global) {
                std.log.err("return in global scope is not allowed", .{});
                break :sw Error.IllegalReturn;
            }
            try compile_expression(compiler, r.value, 0);
            try compiler.main.append(Instruction.address(.Return, 0));
        },
        .functioncall => |fc| compile_function_call(compiler, fc, 1),
        .struct_assignment => |sa| {
            const strukt = sa.access;
            const val = sa.value;
            std.debug.assert(strukt.* == .struct_access);
            try compile_expression(compiler, strukt.struct_access.strct, 0);
            try compile_expression(compiler, strukt.struct_access.key, 1);
            try compile_expression(compiler, val, 2);
            try compiler.main.append(Instruction.register(.AccessWrite, 0, 1, 2));
        },
        .if_statement => |branches| {
            const condition = branches.ifBranch.condition;
            const body = branches.ifBranch.body;
            try compile_expression(compiler, condition, 0);
            const negitive_jmp_index = compiler.main.items.len;
            try compiler.main.append(Instruction.address(.JmpOnFalse, 0));
            for (body) |stmt| {
                try compile_statment(compiler, stmt, kind);
            }
            if (branches.elseBranch) |elseB| {
                const finish_jmp_index = compiler.main.items.len;
                try compiler.main.append(Instruction.address(.Jmp, 0));
                const end_positive = @as(u24, @truncate(compiler.main.items.len));
                compiler.main.items[negitive_jmp_index].argument.address = end_positive;
                for (elseB) |stmt| {
                    try compile_statment(compiler, stmt, kind);
                }
                const end_if = @as(u24, @truncate(compiler.main.items.len));
                compiler.main.items[finish_jmp_index].argument.address = end_if;
            } else {
                const end_positive = @as(u24, @truncate(compiler.main.items.len));
                compiler.main.items[negitive_jmp_index].argument.address = end_positive;
            }
        },
        .whileloop => |branch| {
            const condition = branch.loop.condition;
            const body = branch.loop.body;
            const start_of_loop: u24 = @as(u24, @truncate(compiler.main.items.len));
            try compile_expression(compiler, condition, 0);
            const negitive_jmp_index = compiler.main.items.len;
            try compiler.main.append(Instruction.address(.JmpOnFalse, 0));
            for (body) |stmt| {
                try compile_statment(compiler, stmt, kind);
            }
            try compiler.main.append(Instruction.address(.Jmp, start_of_loop));
            const end_loop = @as(u24, @truncate(compiler.main.items.len));
            compiler.main.items[negitive_jmp_index].argument.address = end_loop;
        },
    };
}

fn compile_call_arguments(
    compiler: *Compiler,
    args: []const expression.Expression,
    target: u8,
    context: stdlib.FunctionContext,
) Error!void {
    if (context.arity.has_variadics and context.arity.unnamed_count > args.len or context.arity.unnamed_count > args.len) {
        return Error.NotEnoughArguments;
    }
    if (!context.arity.has_variadics and context.arity.unnamed_count < args.len) {
        return Error.ToManyArguments;
    }
    for (0..args.len) |rev_index| {
        try compile_expression(compiler, &args[args.len - 1 - rev_index], target);
        try compiler.main.append(Instruction.register(.Push, target, null, null));
    }
    const tmp = expression.Expression{ .value = .{ .number = .{ .integer = @intCast(args.len) } } };
    try compile_expression(compiler, &tmp, 0);
}

fn compile_function_call(compiler: *Compiler, fc: expression.FunctionCall, target: u8) Error!void {
    if (target != 0)
        try compiler.main.append(Instruction.register(.Push, 0, null, null));

    if (fc.func.* != .identifier) {
        // NOTE: it is assumed that the expression is a compiled function
        const context: stdlib.FunctionContext = .{
            .function = @ptrFromInt(std.math.maxInt(usize)), // NOTE: function ptr is not used here
            .arity = .{
                .unnamed_count = @truncate(fc.args.len),
                .has_variadics = false,
            },
        };
        if (target != 0) {
            try compile_expression(compiler, fc.func, target);
            try compile_call_arguments(compiler, fc.args, target + 1, context);
            try compiler.main.append(Instruction.register(.CallValue, 0, target, 0));
        } else {
            try compile_expression(compiler, fc.func, 1);
            try compile_call_arguments(compiler, fc.args, 2, context);
            try compiler.main.append(Instruction.register(.CallValue, 0, 1, 0));
        }
        return;
    }

    if (compiler.get_stdlib_function(fc.func.identifier.name)) |data| {
        const addr = data.offset;
        const context: stdlib.FunctionContext = .{
            .function = @ptrFromInt(std.math.maxInt(usize)), // NOTE: function ptr is not used here
            .arity = .{
                .unnamed_count = @truncate(data.arity.args.len),
                .has_variadics = if (data.arity.var_args) |_| true else false,
            },
        };
        try compile_call_arguments(compiler, fc.args, target, context);
        try compiler.main.append(Instruction.address(.CallStd, addr));
    } else if (stdlib.builtins.getIndex(fc.func.identifier.name)) |addr| {
        const context = stdlib.builtins.get(fc.func.identifier.name) orelse unreachable;
        try compile_call_arguments(compiler, fc.args, target, context);
        try compiler.main.append(Instruction.address(.CallIntr, @as(u24, @truncate(addr))));
    } else if (compiler.get_function(fc.func.identifier.name)) |data| {
        const addr = data.offset;
        try compile_call_arguments(compiler, fc.args, target, .{
            .function = @ptrFromInt(std.math.maxInt(usize)), // NOTE: function ptr is not used here
            .arity = .{
                .unnamed_count = @as(u32, @truncate(data.arity.args.len)),
                .has_variadics = if (data.arity.var_args) |_| true else false,
            },
        });
        try compiler.main.append(Instruction.address(.Call, addr));
    } else {
        // NOTE: for this branch we have no idea about the value that is called because it is not tracked
        const addr = compiler.var_table.get(fc.func.identifier.name) orelse {
            std.log.err("no function found with name: '{s}'", .{fc.func.identifier.name});
            return Error.UndefinedFunction;
        };
        try compile_call_arguments(compiler, fc.args, target, .{
            .function = @ptrFromInt(std.math.maxInt(usize)), // NOTE: function ptr is not used here
            .arity = .{
                .unnamed_count = @as(u32, @truncate(fc.args.len)),
                .has_variadics = false,
            },
        });
        try compiler.main.append(Instruction.immidiate(.Read, Compiler.load_address, @truncate(addr)));
        try compiler.main.append(Instruction.register(.CallValue, 0, Compiler.load_address, target));
    }
    if (target != 0) {
        try compiler.main.append(Instruction.register(.Move, target, 0, null));
        try compiler.main.append(Instruction.register(.Pop, 0, null, null));
    }
}

fn compile_expression(compiler: *Compiler, expr: *const expression.Expression, target: u8) Error!void {
    switch (expr.*) {
        .value => |v| try compile_value(compiler, v, target),
        .binary_op => |bin| {
            if (bin.op != .compare) {
                const left = target;
                const right = target + 1;
                try compile_expression(compiler, bin.left, left);
                try compile_expression(compiler, bin.right, right);
                try compile_binary_expression(compiler, bin.op, target, left, right);
            } else {
                const left = target + 1;
                const right = target + 2;
                try compile_expression(compiler, bin.left, left);
                try compile_expression(compiler, bin.right, right);
                try compile_binary_expression(compiler, bin.op, target, left, right);
            }
        },
        .unary_op => |un| {
            if (un.op == .arithmetic and un.op.arithmetic == expression.ArithmeticOps.Sub) {
                try compile_expression(compiler, un.operant, target);
                try compiler.main.append(Instruction.immidiate(.Move, target + 1, 0));
                try compiler.main.append(Instruction.register(.Sub, target, target + 1, target));
                return;
            } else if (un.op == .boolean and un.op.boolean == expression.BooleanOps.Not) {
                try compile_expression(compiler, un.operant, target);
                try compiler.main.append(Instruction.register(.Not, target, target, null));
                return;
            }
            unreachable;
        },
        .wrapped => |ex| try compile_expression(compiler, ex, target),
        .struct_access => |sa| {
            try compile_expression(compiler, sa.strct, target);
            try compile_expression(compiler, sa.key, target + 1);
            try compiler.main.append(Instruction.register(.AccessRead, target, target, target + 1));
        },
        .functioncall => |fc| try compile_function_call(compiler, fc, target),
        .identifier => |id| {
            if (compiler.var_table.get(id.name)) |addr| {
                if (addr <= std.math.maxInt(u16)) {
                    try compiler.main.append(Instruction.immidiate(.Read, target, @intCast(addr)));
                } else {
                    const address: expression.Expression = .{ .value = .{ .address = addr } };
                    try compile_expression(compiler, &address, Compiler.load_address);
                    try compiler.main.append(Instruction.register(.Read, target, Compiler.load_address, null));
                }
            } else if (compiler.get_function(id.name)) |data| {
                const offset: u24 = @as(u24, @truncate(compiler.static_mem.items.len));
                const fp = value.FunctionPointer{
                    .function_address = data.offset,
                    .source_address = if (compiled_sources) |ss| ss.items.len else 0,
                    .arity = data.arity,
                };
                try compiler.static_mem.append(.{ .function_pointer = fp });
                try compiler.main.append(Instruction.immidiate(.Read, target, @intCast(offset)));
            } else {
                std.log.err("undefined variable: {s}", .{id.name});
                return Error.UndefinedVariable;
            }
        },
        .array => |xs| {
            if (!all_comptime_values(xs.elements)) {
                std.log.err("array can not be evaluated at compile time", .{});
                return Error.NonComptimeValue;
            }
            const tmp: []value.Value = try compiler.main.allocator.alloc(value.Value, xs.elements.len);
            for (tmp, xs.elements) |*out, elem| {
                out.* = try eval_expression(compiler.main.allocator, elem);
            }
            const array = value.Value{ .array = tmp };
            const addr: u24 = @as(u24, @truncate(compiler.static_mem.items.len));
            try compiler.static_mem.append(array);
            try compiler.main.append(Instruction.immidiate(.Read, target, @intCast(addr)));
        },
        .dictionary => |dict| {
            if (!all_comptime_entry(dict.entries)) {
                std.log.err("dictionary can not be evaluated at compile time", .{});
                return Error.NonComptimeValue;
            }
            var tmp = try value.Dictionary.empty(compiler.main.allocator);
            for (dict.entries) |entry| {
                const key = try eval_expression(compiler.main.allocator, entry.key.*);
                const val = try eval_expression(compiler.main.allocator, entry.value.*);
                try tmp.dictionary.entries.put(key, val);
            }
            const addr: u24 = @as(u24, @truncate(compiler.static_mem.items.len));
            try compiler.static_mem.append(tmp);
            try compiler.main.append(Instruction.immidiate(.Read, target, @intCast(addr)));
        },
    }
}

fn compile_value(compiler: *Compiler, v: value.Value, target: u8) Error!void {
    const val = sw: switch (v) {
        .function => {
            const data = try compile_function(compiler, v.function, null);

            break :sw value.Value{ .function_pointer = .{
                .function_address = data.offset,
                .source_address = if (compiled_sources) |ss| ss.items.len else 0,
                .arity = v.function.arity,
                .captures = data.captures,
            } };
        },
        .number => |n| {
            if (n == .integer and n.integer <= std.math.maxInt(u16) and n.integer >= 0) {
                try compiler.main.append(
                    Instruction.immidiate(.Move, target, @intCast(n.integer)),
                );
                return;
            } else break :sw v;
        },
        else => |val| val,
    };

    for (compiler.static_mem.items, 0..) |tmp, index| {
        const addr = @as(u24, @truncate(index));
        if (tmp.eql(val)) {
            try compiler.main.append(Instruction.immidiate(.Read, target, @intCast(addr)));
            if (val == .function_pointer) try compile_captures(compiler, val.function_pointer, target);
            return;
        }
    }
    const addr: u24 = @as(u24, @truncate(compiler.static_mem.items.len));
    try compiler.static_mem.append(val);
    try compiler.main.append(Instruction.immidiate(.Read, target, @intCast(addr)));
    if (val == .function_pointer) try compile_captures(compiler, val.function_pointer, target);
}

fn compile_captures(compiler: *Compiler, fp: value.FunctionPointer, target: u8) !void {
    if (fp.captures) |captures| {
        var iter = captures.iterator();
        while (iter.next()) |entry| {
            const capture_addr = entry.value_ptr.*;
            const maybe_addr = compiler.var_table.get(entry.key_ptr.*);
            if (maybe_addr) |addr| {
                try compiler.main.append(Instruction.immidiate(.Read, target + 1, @intCast(addr)));
                try compiler.main.append(
                    Instruction.register(.Capture, target, target + 1, @intCast(capture_addr)),
                );
            } else {
                const data = compiler.get_function(entry.key_ptr.*) orelse {
                    std.log.err("no local value found for capture '{s}'", .{entry.key_ptr.*});
                    return Error.UndefinedVariable;
                };
                const tmp: value.Value = .{ .function_pointer = .{
                    .function_address = data.offset,
                    .source_address = data.source_offset,
                    .arity = data.arity,
                    .captures = data.captures,
                } };
                try compile_value(compiler, tmp, target + 1);
                try compiler.main.append(
                    Instruction.register(.Capture, target, target + 1, @intCast(capture_addr)),
                );
            }
        }
    }
}

fn eval_expression(alloc: std.mem.Allocator, expr: expression.Expression) !value.Value {
    switch (expr) {
        .value => |v| return v,
        .array => |array| {
            const tmp: []value.Value = try alloc.alloc(value.Value, array.elements.len);
            for (tmp, array.elements) |*out, elem| {
                out.* = try eval_expression(alloc, elem);
            }
            return .{ .array = tmp };
        },
        .dictionary => |dict| {
            var tmp = try value.Dictionary.empty(alloc);
            for (dict.entries) |entry| {
                const key = try eval_expression(alloc, entry.key.*);
                const val = try eval_expression(alloc, entry.value.*);
                try tmp.dictionary.entries.put(key, val);
            }
            return tmp;
        },
        else => unreachable,
    }
}

fn is_comptime_value(v: expression.Expression) bool {
    const is_value = v == .value;
    const is_comptime_array = v == .array and all_comptime_values(v.array.elements);
    const is_comptime_dict = v == .dictionary and all_comptime_entry(v.dictionary.entries);
    return is_value or is_comptime_array or is_comptime_dict;
}

fn all_comptime_values(values: []const expression.Expression) bool {
    for (values) |v| {
        if (!is_comptime_value(v)) {
            return false;
        }
    }
    return true;
}

fn all_comptime_entry(entries: []const expression.DictionaryEntry) bool {
    for (entries) |e| {
        if (!is_comptime_value(e.key.*) or !is_comptime_value(e.value.*)) {
            return false;
        }
    }
    return true;
}

fn arithmetic_op_to_instruction(op: expression.ArithmeticOps) MajorCode {
    return switch (op) {
        .Add => MajorCode.Add,
        .Div => MajorCode.Div,
        .Expo => MajorCode.Expo,
        .Mod => MajorCode.Mod,
        .Mul => MajorCode.Mul,
        .Sub => MajorCode.Sub,
    };
}

fn boolean_op_to_instruction(op: expression.BooleanOps) MajorCode {
    return switch (op) {
        .And => MajorCode.And,
        .Or => MajorCode.Or,
        .Not => MajorCode.Not,
    };
}

fn compile_binary_expression(
    compiler: *Compiler,
    op: expression.Operator,
    target: u8,
    left: u8,
    right: u8,
) Error!void {
    try switch (op) {
        .arithmetic => |a| compiler.main.append(
            Instruction.register(arithmetic_op_to_instruction(a), target, left, right),
        ),
        .boolean => |b| compiler.main.append(
            Instruction.register(boolean_op_to_instruction(b), target, left, right),
        ),
        .compare => |c| switch (c) {
            expression.CompareOps.Equal => compiler.main.append(
                Instruction.register(.CmpEq, target, left, right),
            ),
            expression.CompareOps.Less => compiler.main.append(
                Instruction.register(.CmpLess, target, left, right),
            ),
            expression.CompareOps.Greater => {
                try compiler.main.append(Instruction.register(.CmpEq, target, left, right));
                try compiler.main.append(Instruction.register(.CmpLess, left, left, right));
                try compiler.main.append(Instruction.register(.Or, target, target, left));
                try compiler.main.append(Instruction.register(.Not, target, target, null));
            },
            expression.CompareOps.GreaterEqual => {
                try compiler.main.append(Instruction.register(.CmpLess, target, left, right));
                try compiler.main.append(Instruction.register(.Not, target, target, null));
            },
            expression.CompareOps.LessEqual => {
                try compiler.main.append(Instruction.register(.CmpEq, target, left, right));
                try compiler.main.append(Instruction.register(.CmpLess, left, left, right));
                try compiler.main.append(Instruction.register(.And, target, target, left));
            },
            expression.CompareOps.NotEqual => {
                try compiler.main.append(Instruction.register(.CmpEq, target, left, right));
                try compiler.main.append(Instruction.register(.Not, target, target, null));
            },
        },
    };
}
