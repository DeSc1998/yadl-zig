const std = @import("std");
const Lexer = @import("lexer.zig");

const Error = error{
    Full,
    AllocationError,
};

const Self = @This();
const buffer_size: usize = 32;

tokens: [buffer_size]Lexer.Token = undefined,
has_been_written: bool = false,
read_index: usize = 0,
write_index: usize = 0,

fn maskLen(index: usize) usize {
    return index % buffer_size;
}

fn maskTwiceLen(index: usize) usize {
    return index % (buffer_size * 2);
}

pub fn isEmpty(self: Self) bool {
    return self.read_index == self.write_index;
}

pub fn isFull(self: Self) bool {
    return maskTwiceLen(self.write_index + buffer_size) == self.read_index;
}

pub fn len(self: Self) usize {
    const wrap_offset = 2 * buffer_size * @intFromBool(self.write_index < self.read_index);
    const adjusted_write_index = self.write_index + wrap_offset;
    return adjusted_write_index - self.read_index;
}

pub fn read(self: *Self) ?Lexer.Token {
    if (self.isEmpty()) {
        return null;
    }
    const tmp = self.tokens[maskLen(self.read_index)];
    self.read_index = maskTwiceLen(self.read_index + 1);
    return tmp;
}

pub fn peek(self: Self) ?Lexer.Token {
    return if (!self.isEmpty()) self.tokens[maskLen(self.read_index)] else null;
}

pub fn peekNext(self: Self) ?Lexer.Token {
    if (self.len() < 2)
        return null;
    return self.tokens[maskLen(self.read_index + 1)];
}

pub fn peekNextNext(self: Self) ?Lexer.Token {
    if (self.len() < 3)
        return null;
    return self.tokens[maskLen(self.read_index + 2)];
}

pub fn readPrevious(self: Self) ?Lexer.Token {
    if (!self.has_been_written) {
        return null;
    }
    return self.tokens[maskLen(self.read_index - 1)];
}

pub fn write(self: *Self, item: Lexer.Token) Error!void {
    if (self.isFull()) {
        return Error.Full;
    }
    self.tokens[maskLen(self.write_index)] = item;
    self.write_index = maskTwiceLen(self.write_index + 1);
    self.has_been_written = true;
}
