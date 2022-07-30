const std = @import("std");
const panic = std.debug.panic;

const utils = @import("lib/utils.zig");
const print = utils.print;
const print_s = utils.print_s;
const puts = utils.puts;
const puts_e = utils.puts_e;
const putskv_e = utils.putskv_e;
const strncmp = utils.strncmp;
const strEq = utils.strEq;
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

    const i = indexOf(rest, '\n', 2);
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
        panic("must not happen ({s})", .{rest});
    }
    return @intCast(usize, i) - 1;
}

fn isKwChar(ch: u8) bool {
    return (('a' <= ch and ch <= 'z') or ch == '_');
}

fn isKw(str: []const u8) bool {
    return (
        strEq(str, "func")
        or strEq(str, "var")
        or strEq(str, "set")
        or strEq(str, "call")
        or strEq(str, "call_set")
        or strEq(str, "while")
        or strEq(str, "case")
        or strEq(str, "when")
        or strEq(str, "return")
        or strEq(str, "_cmt")
        or strEq(str, "_debug")
    );
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
    return (('a' <= ch and ch <= 'z') or utils.isNumeric(ch) or ch == '_');
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

fn putsToken(lineno: i32, kind: []const u8, str: []const u8) void {
    const xs = List.init();
    xs.addInt(lineno);
    xs.addStr(kind);
    xs.addStr(str);

    json.printOneLine(xs);
    print_s("\n");
}

fn tokenize(src: []const u8) void {
    var pos: usize = 0;
    var temp: [1024]u8 = undefined;
    var lineno: i32 = 1;

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
            if (isKw(temp[0..size])) {
                putsToken(lineno, "kw", temp[0..size]);
            } else {
                putsToken(lineno, "ident", temp[0..size]);
            }
            pos += size;
            continue;
        }

        panic("Unexpected pattern ({s})", .{rest});
    }
}

pub fn main() !void {
    var buf: [20000]u8 = undefined;
    const src = utils.readStdinAll(&buf);

    tokenize(src);
}
