const std = @import("std");
const panic = std.debug.panic;

const utils = @import("lib/utils.zig");
const print = utils.print;
const puts = utils.puts;
const puts_e = utils.puts_e;
const putskv_e = utils.putskv_e;
const strncmp = utils.strncmp;
const indexOf = utils.indexOf;

const types = @import("lib/types.zig");
const List = types.List;

const json = @import("lib/json.zig");

fn matchSpace(ch: u8) usize {
    if (ch == ' ' or ch == '\n') {
        return 1;
    } else {
        return 0;
    }
}

fn matchComment(rest: []const u8) usize {
    if (!strncmp(rest, "//", 2)) {
        return 0;
    }

    const i = utils.indexOf(rest, '\n', 2);
    if (i == -1) {
        return rest.len;
    } else {
        return @intCast(usize, i);
    }
}

fn matchStr(rest: []const u8) usize {
    if (rest[0] != '"') {
        return 0;
    }

    const i = indexOf(rest, '"', 1);
    if (i == -1) {
        panic("must not happen ({})", .{rest});
    }
    return @intCast(usize, i) - 1;
}

fn isKwChar(ch: u8) bool {
    return (('a' <= ch and ch <= 'z') or ch == '_');
}

fn matchKw(rest: []const u8) usize {
    var size: usize = 0;

    size = 8;
    if ((strncmp(rest, "call_set", size)) and !isKwChar(rest[size])) {
        return size;
    }

    size = 6;
    if ((strncmp(rest, "return", size) or strncmp(rest, "_debug", size)) and !isKwChar(rest[size])) {
        return size;
    }

    size = 5;
    if ((strncmp(rest, "while", size)) and !isKwChar(rest[size])) {
        return size;
    }

    size = 4;
    if ((strncmp(rest, "func", size) or strncmp(rest, "call", size) or strncmp(rest, "case", size) or strncmp(rest, "_cmt", size)) and !isKwChar(rest[size])) {
        return size;
    }

    size = 3;
    if ((strncmp(rest, "var", size) or strncmp(rest, "set", size)) and !isKwChar(rest[size])) {
        return size;
    }

    return 0;
}

fn matchInt(rest: []const u8) usize {
    if (!(rest[0] == '-' or utils.isNumeric(rest[0]))) {
        return 0;
    }

    if (rest[0] == '-') {
        return utils.indexOfNonNumeric(rest, 1);
    } else {
        return utils.indexOfNonNumeric(rest, 0);
    }
}

fn matchSymbol(rest: []const u8) usize {
    if (strncmp(rest, "==", 2) or strncmp(rest, "!=", 2)) {
        return 2;
    } else if (utils.matchAnyChar(";(){},+*=", rest[0])) {
        return 1;
    } else {
        return 0;
    }
}

fn isIdentChar(ch: u8) bool {
    return (('a' <= ch and ch <= 'z') or utils.isNumeric(ch) or utils.matchAnyChar("[]_", ch));
}

fn matchIdent(rest: []const u8) usize {
    var i: usize = 0;

    while (i < rest.len) : (i += 1) {
        if (!isIdentChar(rest[i])) {
            break;
        }
    }

    return i;
}

fn putsToken(lineno: u32, kind: []const u8, str: []const u8) void {
    const xs = List.init();
    xs.addInt(1);
    xs.addStr(kind);
    xs.addStr(str);

    json.printOneLine(xs);
    print("\n");
}

fn tokenize(src: []const u8) void {
    var pos: usize = 0;
    var temp: [1024]u8 = undefined;
    var lineno: u32 = 1;

    while (pos < src.len) {
        var size: usize = 0;
        const rest = src[pos..];

        size = matchSpace(rest[0]);
        if (0 < size) {
            if (rest[0] == '\n') {
                lineno += 1;
            }
            pos += size;
            continue;
        }

        size = matchComment(rest);
        if (0 < size) {
            pos += size;
            continue;
        }

        size = matchStr(rest);
        if (0 < size) {
            utils.substring(&temp, rest, 1, size + 1);
            putsToken(lineno, "str", temp[0..size]);
            pos += size + 2;
            continue;
        }

        size = matchKw(rest);
        if (0 < size) {
            utils.substring(&temp, rest, 0, size);
            putsToken(lineno, "kw", temp[0..size]);
            pos += size;
            continue;
        }

        size = matchInt(rest);
        if (0 < size) {
            utils.substring(&temp, rest, 0, size);
            putsToken(lineno, "int", temp[0..size]);
            pos += size;
            continue;
        }

        size = matchSymbol(rest);
        if (0 < size) {
            utils.substring(&temp, rest, 0, size);
            putsToken(lineno, "sym", temp[0..size]);
            pos += size;
            continue;
        }

        size = matchIdent(rest);
        if (0 < size) {
            utils.substring(&temp, rest, 0, size);
            putsToken(lineno, "ident", temp[0..size]);
            pos += size;
            continue;
        }

        panic("Unexpected pattern ({})", .{rest});
    }
}

pub fn main() !void {
    var buf: [20000]u8 = undefined;
    const src = utils.readStdinAll(&buf);

    tokenize(src);
}
