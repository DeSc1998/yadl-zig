const std = @import("std");

const Parser = @import("Parser.zig");
const statement = @import("statement.zig");
const expression = @import("expression.zig");
const value = @import("value.zig");
const stdlib = @import("stdlib.zig");

pub const Error = error{
    NotImplemented,
    UndefinedFunction,
    NotEnoughArguments,
    ToManyArguments,
    UndefinedVariable,
    IllegalReturn,
    NonComptimeValue,
    ParserError,
} || std.mem.Allocator.Error;

const OpCode = enum(u8) {
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

    AccessRead, // NOTE: `source_left` is accessed with `source_right`
    AccessWrite, // NOTE: puts `source_right` in `destination` at index `source_left`
    Push, // NOTE: puts the contents of `destination` on the stack
    Pop, // NOTE: removes the top element on the stack and puts it into `destination`
    Move, // NOTE: Unary Op, right register is ignored

    // Address OpCodes
    // layout: (op_code, address)
    JmpOnTrue,
    JmpOnFalse,

    LoadStatic, // NOTE: loads value at `address` from static memory into register 7

    Call, // NOTE: call arguments are expected to be on the stack
    CallStd, // NOTE: call arguments are expected to be on the stack
    Return,
};

pub fn is_address_opcode(op: OpCode) bool {
    return switch (op) {
        .Return, .JmpOnFalse, .JmpOnTrue, .LoadStatic, .Call, .CallStd => true,
        else => false,
    };
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
    },

    const Registers = packed struct(u24) {
        destination: u8,
        source_left: u8,
        source_right: u8,
    };

    fn register(code: OpCode, dest: u8, left: ?u8, right: ?u8) Instruction {
        return .{
            .op_code = code,
            .argument = .{ .registers = .{
                .destination = dest,
                .source_left = if (left) |l| l else 0,
                .source_right = if (right) |r| r else 0,
            } },
        };
    }

    fn address(code: OpCode, addr: u24) Instruction {
        return .{
            .op_code = code,
            .argument = .{ .address = addr },
        };
    }

    pub fn dump(self: Instruction, writer: std.io.AnyWriter) !void {
        if (is_address_opcode(self.op_code)) {
            const addr = self.argument.address;
            try writer.print(" {s:<10} {}\n", .{ @tagName(self.op_code), addr });
        } else {
            const regs = self.argument.registers;
            switch (self.op_code) {
                .Move, .Not => try writer.print(" {s:<6} {} <- {}\n", .{
                    @tagName(self.op_code),
                    regs.destination,
                    regs.source_left,
                }),
                .Push, .Pop => try writer.print(" {s:<6} {}\n", .{
                    @tagName(self.op_code),
                    regs.destination,
                }),
                else => try writer.print(" {s:<6} {} <- {} {}\n", .{
                    @tagName(self.op_code),
                    regs.destination,
                    regs.source_left,
                    regs.source_right,
                }),
            }
        }
    }
};

pub const Program = struct {
    instructions: []const Instruction,
    static_memory: []const value.Value = &.{},
};

const FunctionData = struct { offset: u24, arity: expression.Function.Arity };
const FunctionTable = std.StringHashMap(FunctionData);
const VariableTable = std.StringHashMap(u8);

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
};

const Compiler = struct {
    root: ?*Compiler = null,
    main: std.ArrayList(Instruction),
    functions: std.ArrayList(Program),
    function_table: FunctionTable,
    var_table: VariableTable,
    static_mem: std.ArrayList(value.Value),

    const var_offset: u8 = 8;

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
        return tmp;
    }
};

pub fn compile_source(source: []const u8, allocator: std.mem.Allocator) Error!CompiledSource {
    var parser = Parser.init(source, allocator);
    const statements = parser.parse() catch |err| {
        std.log.err("not implemented: handling of failed parsing: {}", .{err});
        return Error.ParserError;
    };
    var compiler = Compiler.init(allocator);
    try compile_program(&compiler, statements);
    compiler.var_table.deinit();
    return .{
        .allocator = allocator,
        .main_program = .{
            .instructions = try compiler.main.toOwnedSlice(),
            .static_memory = try compiler.static_mem.toOwnedSlice(),
        },
        .functions = try compiler.functions.toOwnedSlice(),
        .function_table = compiler.function_table,
    };
}

fn compile_program(compiler: *Compiler, statements: []const statement.Statement) Error!void {
    for (statements) |st| {
        try compile_statment(compiler, st, .Global);
    }
}

fn compile_function(compiler: *Compiler, func: expression.Function) Error!u24 {
    var tmp = compiler.local();
    for (func.body) |st| {
        try compile_statment(&tmp, st, .Local);
    }
    const prog = Program{
        .instructions = try tmp.main.toOwnedSlice(),
        .static_memory = try tmp.static_mem.toOwnedSlice(),
    };
    const offset: u24 = compiler.functions.items.len;
    try compiler.functions.append(prog);
    return offset;
}

fn compile_statment(compiler: *Compiler, st: statement.Statement, kind: ScopeKind) Error!void {
    return sw: switch (st) {
        .assignment => |a| {
            if (compiler.var_table.get(a.varName.name)) |reg| {
                try compile_expression(compiler, a.value, 0);
                try compiler.main.append(Instruction.register(.Move, reg, 0, null));
            } else {
                const reg = @as(u8, @truncate(compiler.var_table.count())) + Compiler.var_offset;
                try compiler.var_table.put(a.varName.name, reg);
                try compile_expression(compiler, a.value, reg);
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
        .functioncall => |fc| compile_function_call(compiler, fc, 0),
        .struct_assignment => |sa| {
            const strukt = sa.access;
            const val = sa.value;
            std.debug.assert(strukt.* == .struct_access);
            try compile_expression(compiler, strukt.struct_access.strct, 0);
            try compile_expression(compiler, strukt.struct_access.key, 1);
            try compile_expression(compiler, val, 2);
            try compiler.main.append(Instruction.register(.AccessWrite, 0, 1, 2));
        },
        else => {
            std.log.err("not implemented: compiling statemant kind: {s}", .{@tagName(st)});
            break :sw Error.NotImplemented;
        },
    };
}

fn compile_call_arguments(
    compiler: *Compiler,
    args: []const expression.Expression,
    context: stdlib.FunctionContext,
) Error!void {
    if (context.arity.has_variadics and context.arity.unnamed_count > args.len or context.arity.unnamed_count > args.len) {
        return Error.NotEnoughArguments;
    }
    if (!context.arity.has_variadics and context.arity.unnamed_count < args.len) {
        return Error.ToManyArguments;
    }
    for (args) |*arg| {
        try compile_expression(compiler, arg, 0);
        try compiler.main.append(Instruction.register(.Push, 0, null, null));
    }
    const tmp = expression.Expression{ .value = .{ .number = .{ .integer = @intCast(args.len) } } };
    try compile_expression(compiler, &tmp, 0);
}

fn compile_function_call(compiler: *Compiler, fc: expression.FunctionCall, target: u8) Error!void {
    if (fc.func.* != .identifier) {
        std.log.err("not implemented: function call, non identifier case ", .{});
        return Error.NotImplemented;
    }

    if (stdlib.builtins.getIndex(fc.func.identifier.name)) |addr| {
        const context = stdlib.builtins.get(fc.func.identifier.name) orelse unreachable;
        try compile_call_arguments(compiler, fc.args, context);
        try compiler.main.append(Instruction.address(.CallStd, @as(u24, @truncate(addr))));
    } else {
        const data = compiler.function_table.get(fc.func.identifier.name) orelse return Error.UndefinedFunction;
        const addr = data.offset;
        try compile_call_arguments(compiler, fc.args, .{
            .function = @ptrFromInt(std.math.maxInt(usize)), // NOTE: function ptr is not used here
            .arity = .{
                .unnamed_count = @as(u32, @truncate(data.arity.args.len)),
                .has_variadics = if (data.arity.var_args) |_| true else false,
            },
        });
        try compiler.main.append(Instruction.address(.Call, addr));
    }
    if (target != 0) {
        try compiler.main.append(Instruction.register(.Move, target, 0, null));
    }
}

fn compile_expression(compiler: *Compiler, expr: *const expression.Expression, target: u8) Error!void {
    switch (expr.*) {
        .value => |v| {
            for (compiler.static_mem.items, 0..) |val, index| {
                const addr = @as(u24, @truncate(index));
                if (val.eql(v)) {
                    try compiler.main.append(Instruction.address(.LoadStatic, addr));
                    if (target != 7) try compiler.main.append(Instruction.register(.Move, target, 7, null));
                    return;
                }
            }
            const addr: u24 = @as(u24, @truncate(compiler.static_mem.items.len));
            try compiler.static_mem.append(v);
            try compiler.main.append(Instruction.address(.LoadStatic, addr));
            if (target != 7) try compiler.main.append(Instruction.register(.Move, target, 7, null));
        },
        .binary_op => |bin| {
            const left = target;
            const right = if (target == 6) Compiler.var_offset + @as(u8, @truncate(compiler.var_table.count())) else target + 1;
            try compile_expression(compiler, bin.left, left);
            try compile_expression(compiler, bin.right, right);
            try compile_binary_expression(compiler, bin.op, target, left, right);
        },
        .unary_op => |un| {
            if (un.op == .arithmetic and un.op.arithmetic == expression.ArithmeticOps.Sub) {
                try compile_expression(compiler, un.operant, target);
                try compiler.main.append(Instruction.address(.LoadStatic, 0));
                try compiler.main.append(Instruction.register(.Sub, target, 7, target));
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
            if (compiler.var_table.get(id.name)) |reg| {
                try compiler.main.append(Instruction.register(.Move, target, reg, null));
            } else {
                std.log.err("undefined variable '{s}'", .{id.name});
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
            try compiler.main.append(Instruction.address(.LoadStatic, addr));
            if (target != 7) try compiler.main.append(Instruction.register(.Move, target, 7, null));
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
            try compiler.main.append(Instruction.address(.LoadStatic, addr));
            if (target != 7) try compiler.main.append(Instruction.register(.Move, target, 7, null));
        },
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

fn arithmetic_op_to_instruction(op: expression.ArithmeticOps) OpCode {
    return switch (op) {
        .Add => OpCode.Add,
        .Div => OpCode.Div,
        .Expo => OpCode.Expo,
        .Mod => OpCode.Mod,
        .Mul => OpCode.Mul,
        .Sub => OpCode.Sub,
    };
}

fn boolean_op_to_instruction(op: expression.BooleanOps) OpCode {
    return switch (op) {
        .And => OpCode.And,
        .Or => OpCode.Or,
        .Not => OpCode.Not,
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
                try compiler.main.append(Instruction.register(.And, target, target, left));
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
