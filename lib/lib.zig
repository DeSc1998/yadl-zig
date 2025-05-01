const std = @import("std");

pub const Parser = @import("Parser.zig");
pub const Scope = @import("Scope.zig");

pub const statement = @import("statement.zig");
pub const expression = @import("expression.zig");
pub const interpreter = @import("interpreter.zig");

pub usingnamespace @import("compiler.zig");
pub usingnamespace @import("maschine.zig");
