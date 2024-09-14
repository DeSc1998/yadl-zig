const std = @import("std");

pub const Error = error{
    UnexpectedCharacter,
    EndOfFile,
    NotImplemented,
    UnknownError,
} || std.mem.Allocator.Error;

pub const TokenKind = enum {
    Identifier,
    Number,
    Boolean,
    String,

    Operator,
    ArgSep,
    KeyValueSep,
    OpenParen, // NOTE: refers to all of: { [ (
    CloseParen, // NOTE: refers to all of: } ] )
    LambdaArrow,
    Newline,

    Keyword,

    Unknown,
};

pub const Token = struct {
    chars: []const u8,
    index: usize,
    kind: TokenKind,
    line: u64,
    column: u64,
};

pub const CharRange = struct {
    first: u8,
    last: u8,

    pub fn init(first: u8, last: u8) @This() {
        return .{ .first = first, .last = last };
    }
};

// lexer internals
data: []const u8,
current_position: u64,

const Self = @This();

pub fn init(input: []const u8) Self {
    return .{
        .data = input,
        .current_position = 0,
    };
}

pub fn reset(self: *Self) void {
    self.current_position = 0;
}

fn anyOf(char: u8, chars: []const u8) bool {
    for (chars) |c| {
        if (c == char) {
            return true;
        }
    }
    return false;
}

fn anyOfRange(char: u8, range: CharRange) bool {
    return char <= range.last and char >= range.first;
}

// Identifier
fn isInitialIdentifierChar(c: u8) bool {
    return anyOfRange(c, CharRange.init('a', 'z')) or anyOfRange(c, CharRange.init('A', 'Z'));
}

fn isIdentifierChar(c: u8) bool {
    return isInitialIdentifierChar(c) or isDecimalDigit(c) or c == '_';
}

fn lexLineComment(self: *Self) Error!Token {
    _ = self.readChar() catch unreachable; // ignore '/'
    const char = try self.readChar();
    if (char == '/') {
        while (self.peekChar()) |c| {
            if (c == '\n') {
                return self.nextToken();
            }
            _ = self.readChar() catch unreachable;
        } else |err| {
            if (err != Error.EndOfFile)
                return err;
        }
    }

    return Error.EndOfFile;
}

fn lexIdentifier(self: *Self) Error!Token {
    const pos = self.current_position;
    const c = try self.readChar();
    if (!isInitialIdentifierChar(c)) {
        self.current_position = pos;
        return Error.UnexpectedCharacter;
    }

    while (self.readChar()) |char| {
        if (!isIdentifierChar(char)) {
            self.current_position -= 1;
            return self.newToken(self.data[pos..self.current_position], TokenKind.Identifier);
        }
    } else |err| {
        if (err == Error.EndOfFile)
            return self.newToken(self.data[pos..self.current_position], TokenKind.Identifier);

        return err;
    }
}

// Number
pub const NumberPrefix = enum { Decimal, Binary, Octal, Hexadecimal };

fn isDecimalDigit(c: u8) bool {
    return anyOfRange(c, CharRange.init('0', '9'));
}

fn isOctalDigit(c: u8) bool {
    return anyOfRange(c, CharRange.init('0', '7'));
}

fn isBinaryDigit(c: u8) bool {
    return anyOfRange(c, CharRange.init('0', '1'));
}

fn isHexDigit(c: u8) bool {
    return isDecimalDigit(c) or anyOfRange(c, CharRange.init('a', 'f')) or anyOfRange(c, CharRange.init('A', 'F'));
}

fn numberPrefix(self: *Self) Error!NumberPrefix {
    const zero = try self.readChar();

    if (zero != '0') {
        return Error.UnexpectedCharacter;
    }

    return switch (try self.readChar()) {
        'x' => .Hexadecimal,
        'o' => .Octal,
        'b' => .Binary,
        else => Error.UnexpectedCharacter,
    };
}

fn digits(self: *Self, prefix: NumberPrefix) Error!void {
    while (self.peekChar()) |char| {
        switch (prefix) {
            .Decimal => {
                if (!isDecimalDigit(char))
                    return;
            },
            .Octal => {
                if (!isOctalDigit(char))
                    return;
            },
            .Hexadecimal => {
                if (!isHexDigit(char))
                    return;
            },
            .Binary => {
                if (!isBinaryDigit(char))
                    return;
            },
        }
        _ = try self.readChar();
    } else |err| {
        if (err == Error.EndOfFile)
            return;
        return err;
    }
}

fn lexNumber(self: *Self) Error!Token {
    const pos = self.current_position;
    const prefix = self.numberPrefix() catch |err| b: {
        if (err != Error.UnexpectedCharacter)
            return err;
        break :b .Decimal;
    };

    if (prefix == .Decimal) {
        self.current_position = pos;
    }

    try self.digits(prefix);
    if (self.peekChar() catch null) |char| {
        if (char == '.') {
            _ = try self.readChar();
            try self.digits(prefix);
        }
    }

    return self.newToken(self.data[pos..self.current_position], .Number);
}

// Keywords
const keywords = [_][]const u8{
    "if",
    "elif",
    "else",
    "while",
    "return",
};

fn lexKeyword(self: *Self) Error!Token {
    return self.lexAnyOf(&keywords, .Keyword);
}

// Booleans
const bool_constants = [_][]const u8{
    "true",
    "false",
};

fn lexBoolean(self: *Self) Error!Token {
    return self.lexAnyOf(&bool_constants, .Boolean);
}

const StringBorder = enum {
    SingleQuote,
    DoubleQuote,
};

fn expectStringBorder(self: *Self, borderType: ?StringBorder) Error!StringBorder {
    const quote = try self.peekChar();
    if (borderType) |b| {
        if (checkStringBorder(quote, b)) {
            _ = self.readChar() catch unreachable;
            return b;
        } else {
            return Error.UnexpectedCharacter;
        }
    } else {
        if (quote == '\'') {
            _ = self.readChar() catch unreachable;
            return .SingleQuote;
        } else if (quote == '"') {
            _ = self.readChar() catch unreachable;
            return .DoubleQuote;
        } else {
            return Error.UnexpectedCharacter;
        }
    }
}

fn checkStringBorder(char: u8, borderType: StringBorder) bool {
    return char == '\'' and borderType == .SingleQuote or char == '\"' and borderType == .DoubleQuote;
}

// String
fn lexString(self: *Self) Error!Token {
    const pos = self.current_position;
    const leftQuote = try self.expectStringBorder(null);
    while (self.peekChar()) |char| {
        if (checkStringBorder(char, leftQuote))
            break;

        if (char == '\n')
            return Error.UnexpectedCharacter;

        _ = self.readChar() catch unreachable;
    } else |err| {
        return err;
    }

    _ = self.expectStringBorder(leftQuote) catch |err| {
        self.current_position = pos;
        return err;
    };
    return self.newToken(self.data[pos + 1 .. self.current_position - 1], .String);
}

// Operator
const arithmetic_operators = [_][]const u8{
    "+",
    "-",
    "*",
    "/",
    "^",
    "%",
};
const boolean_operators = [_][]const u8{
    "and",
    "or",
    "not",
};
const compare_operators = [_][]const u8{
    "==",
    "!=",
    "<=",
    ">=",
    "<",
    ">",
};

fn lexOperator(self: *Self) Error!Token {
    return self.lexAnyOf(&arithmetic_operators, .Operator) catch self.lexAnyOf(&compare_operators, .Operator) catch self.lexAnyOf(&[_][]const u8{"="}, .Operator);
}

fn lexBooleanOperator(self: *Self) Error!Token {
    const pos = self.current_position;
    const tmp = try self.lexAnyOf(&boolean_operators, .Operator);
    const char = try self.peekChar();
    if (!isIdentifierChar(char)) {
        return tmp;
    } else {
        self.current_position = pos;
        return Error.UnexpectedCharacter;
    }
}

fn lexLambdaArrow(self: *Self) Error!Token {
    return self.lexAnyOf(&[_][]const u8{"=>"}, .LambdaArrow);
}

fn lexAnyOf(self: *Self, strings: []const []const u8, kind: TokenKind) Error!Token {
    const pos = self.current_position;
    for (strings) |str| {
        if (pos + str.len >= self.data.len)
            continue;
        const canditate = self.data[pos .. pos + str.len];
        if (std.mem.eql(u8, canditate, str)) {
            self.current_position += str.len;
            return self.newToken(str, kind);
        }
    }
    return Error.UnexpectedCharacter;
}

pub fn countNewlines(self: Self) u64 {
    return std.mem.count(u8, self.data[0..self.current_position], "\n") + 1;
}

pub fn currentColumn(self: Self) u64 {
    var pos = self.current_position - 1;
    while (self.data[pos] != '\n' and pos > 0) : (pos -= 1) {}
    return self.current_position - pos;
}

fn newToken(self: Self, chars: []const u8, kind: TokenKind) Token {
    const line = self.countNewlines();
    const column = self.currentColumn() - chars.len;
    return .{
        .chars = chars,
        .index = self.current_position - chars.len,
        .kind = kind,
        .line = line,
        .column = if (line != 1) column else column + 1,
    };
}

fn skipOne(self: *Self) Error!void {
    _ = try self.readChar();
}

/// skips whitespce excluding newlines
fn skipWhitespce(self: *Self) Error!void {
    var current_char = try self.peekChar();
    while (std.ascii.isWhitespace(current_char) and !(current_char == '\n')) {
        self.skipOne() catch unreachable;
        current_char = try self.peekChar();
    }
}

fn readChar(self: *Self) Error!u8 {
    if (self.data.len > self.current_position) {
        const c = self.data[self.current_position];
        self.current_position += 1;
        return c;
    } else {
        return Error.EndOfFile;
    }
}

fn peekChar(self: *Self) Error!u8 {
    if (self.data.len > self.current_position) {
        return self.data[self.current_position];
    } else {
        return Error.EndOfFile;
    }
}

fn isCommentBegin(chars: []const u8) bool {
    if (chars.len < 2) return false;
    return std.mem.eql(u8, chars[0..2], "//") or std.mem.eql(u8, chars[0..2], "/*");
}

pub fn nextToken(self: *Self) Error!Token {
    try self.skipWhitespce();
    const char = try self.peekChar();

    const pos = self.current_position;
    if (char == ',') {
        self.skipOne() catch unreachable;
        return self.newToken(self.data[pos..self.current_position], .ArgSep);
    } else if (anyOf(char, "ft")) {
        return self.lexBoolean() catch self.lexIdentifier();
    } else if (char == '\n') {
        self.skipOne() catch unreachable;
        return self.newToken(self.data[pos..self.current_position], .Newline);
    } else if (char == ':') {
        self.skipOne() catch unreachable;
        return self.newToken(self.data[pos..self.current_position], .KeyValueSep);
    } else if (isCommentBegin(self.data[self.current_position..])) {
        return self.lexLineComment();
    } else if (char == '\'' or char == '"') {
        return self.lexString();
    } else if (anyOf(char, "({[")) {
        self.skipOne() catch unreachable;
        return self.newToken(self.data[pos..self.current_position], .OpenParen);
    } else if (anyOf(char, ")}]")) {
        self.skipOne() catch unreachable;
        return self.newToken(self.data[pos..self.current_position], .CloseParen);
    } else if (anyOf(char, "iewr")) {
        return self.lexKeyword() catch self.lexIdentifier();
    } else if (anyOf(char, "aon")) {
        return self.lexBooleanOperator() catch self.lexIdentifier();
    } else if (isInitialIdentifierChar(char)) {
        return self.lexIdentifier();
    } else if (isDecimalDigit(char)) {
        return self.lexNumber();
    } else {
        return self.lexLambdaArrow() catch self.lexOperator();
    }
}

pub fn allTokens(self: *Self, tokens: *std.ArrayList(Token)) Error!void {
    while (self.nextToken()) |token| {
        tokens.append(token) catch {
            return Error.MemoryFailure;
        };
    } else |err| {
        if (err != Error.EndOfFile) {
            return err;
        }
    }
}

fn nextLine(self: Self, token: Token) ?[]const u8 {
    var pos = token.index;
    while (pos < self.data.len) : (pos += 1) {
        if (self.data[pos] == '\n') {
            break;
        }
    }

    if (pos == self.data.len)
        return null;

    const line_begin = pos + 1;
    var line_end = pos + 1;

    while (line_end < self.data.len) : (line_end += 1) {
        if (self.data[line_end] == '\n')
            break;
    }
    return self.data[line_begin..line_end];
}

const LineContext = struct {
    chars: []const u8,
    token_offset: usize,
};

fn currentLine(self: Self, token: Token) LineContext {
    var line_begin = token.index;
    var line_end = token.index;

    while (line_begin > 0) : (line_begin -= 1) {
        if (self.data[line_begin] == '\n') {
            line_begin += 1;
            break;
        }
    }

    while (line_end < self.data.len) : (line_end += 1) {
        if (self.data[line_end] == '\n')
            break;
    }
    line_begin = if (line_begin > line_end) line_end else line_begin;
    return .{
        .chars = self.data[line_begin..line_end],
        .token_offset = token.index - line_begin,
    };
}

fn previousLine(self: Self, token: Token) ?[]const u8 {
    var pos = token.index;

    while (pos > 0) : (pos -= 1) {
        if (self.data[pos] == '\n') {
            break;
        }
    }

    if (pos == 0)
        return null;

    var line_begin = pos - 1;
    const line_end = pos;
    while (line_begin > 0) : (line_begin -= 1) {
        if (self.data[line_begin] == '\n') {
            line_begin += 1;
            break;
        }
    }

    return self.data[line_begin..line_end];
}

pub fn printContext(self: Self, out: std.io.AnyWriter, token: Token) Error!void {
    if (token.kind == .Newline)
        return;
    const tty_config = std.io.tty.detectConfig(std.io.getStdOut());

    if (previousLine(self, token)) |previous| {
        out.print("{d:5}:{s}\n", .{ token.line - 1, previous }) catch return Error.UnknownError;
    }
    const context = currentLine(self, token);
    const line = context.chars;

    out.print("{d:5}:{s}", .{ token.line, line[0..context.token_offset] }) catch return Error.UnknownError;
    std.io.tty.Config.setColor(tty_config, out, .red) catch return Error.UnknownError;
    std.io.tty.Config.setColor(tty_config, out, .bold) catch return Error.UnknownError;
    out.print("{s}", .{line[context.token_offset .. context.token_offset + token.chars.len]}) catch return Error.UnknownError;
    std.io.tty.Config.setColor(tty_config, out, .reset) catch return Error.UnknownError;
    out.print("{s}\n", .{line[context.token_offset + token.chars.len ..]}) catch return Error.UnknownError;

    if (nextLine(self, token)) |next| {
        out.print("{d:5}:{s}\n", .{ token.line + 1, next }) catch return Error.UnknownError;
    }
}
