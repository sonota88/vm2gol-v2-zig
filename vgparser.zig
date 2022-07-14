const std = @import("std");
const panic = std.debug.panic;

const utils = @import("lib/utils.zig");
const print = utils.print;
const puts = utils.puts;
const print_e = utils.print_e;
const puts_e = utils.puts_e;
const putskv_e = utils.putskv_e;
const puts_fn = utils.puts_fn;
const strEq = utils.strEq;

const allocator = std.heap.page_allocator;

const types = @import("lib/types.zig");
const List = types.List;
const Node = types.Node;

const json = @import("lib/json.zig");

// --------------------------------

const TokenKind = enum {
    KW,
    SYM,
    INT,
    STR,
    IDENT,
};

const Token = struct {
    kind: TokenKind,
    _str: [64]u8,

    const Self = @This();

    fn create(kind: TokenKind, str: []const u8) !*Self {
        var obj = try allocator.create(Self);
        obj.kind = kind;
        utils.strcpy(&obj._str, str);
        return obj;
    }

    fn kindEq(self: *Self, kind: TokenKind) bool {
        return self.kind == kind;
    }

    pub fn getStr(self: *Self) []const u8 {
        const len = utils.strlen(&self._str);
        return self._str[0..len];
    }

    fn strEq(self: *Self, str: []const u8) bool {
        return utils.strEq(self.getStr(), str);
    }

    fn is(self: *Self, kind: TokenKind, str: []const u8) bool {
        return self.kindEq(kind) and self.strEq(str);
    }
};

// --------------------------------

const NUM_TOKEN_MAX = 1024;

var tokens: [NUM_TOKEN_MAX]*Token = undefined;
var numTokens: usize = 0;
var pos: usize = 0;

// --------------------------------

fn strToTokenKind(kind_str: []const u8) TokenKind {
    if (strEq(kind_str, "kw")) {
        return TokenKind.KW;
    } else if (strEq(kind_str, "sym")) {
        return TokenKind.SYM;
    } else if (strEq(kind_str, "int")) {
        return TokenKind.INT;
    } else if (strEq(kind_str, "str")) {
        return TokenKind.STR;
    } else if (strEq(kind_str, "ident")) {
        return TokenKind.IDENT;
    } else {
        panic("must not happen ({})", .{kind_str});
    }
}

fn addToken(line: []const u8, ti: usize) !void {
    const xs = json.parse(line);
    const kind = strToTokenKind(xs.get(1).getStr());
    const str = xs.get(2).getStr();

    const t: *Token = try Token.create(kind, str);
    tokens[ti] = t;
}

fn getLineSize(rest: []const u8) usize {
    const i = utils.indexOf(rest, '\n', 0);
    if (0 <= i) {
        return @intCast(usize, i) + 1;
    } else {
        return rest.len;
    }
}

fn readTokens(src: []const u8) !void {
    puts_fn("readTokens");

    var src_pos: usize = 0;
    var ti: usize = 0;
    while (src_pos < src.len) {
        const rest = src[src_pos..];
        const line_size = getLineSize(rest);
        var line: [256]u8 = undefined;
        if (rest[line_size - 1] == '\n') {
            utils.substring(&line, rest, 0, line_size - 1);
        } else {
            utils.substring(&line, rest, 0, line_size);
        }

        try addToken(line[0..], ti);
        ti += 1;

        src_pos += line_size;
    }

    numTokens = ti;
}

// --------------------------------

fn isEnd() bool {
    return numTokens <= pos;
}

fn peek(offset: usize) *Token {
    return tokens[pos + offset];
}

fn assertToken(kind: TokenKind, str: []const u8) void {
    const t = peek(0);

    if (!t.kindEq(kind)) {
        panic("Unexpected kind ({})", .{t});
    }

    if (!t.strEq(str)) {
        panic("Unexpected str ({}) ({})", .{ str, t });
    }
}

fn consumeKw(str: []const u8) void {
    assertToken(TokenKind.KW, str);
    pos += 1;
}

fn consumeSym(str: []const u8) void {
    assertToken(TokenKind.SYM, str);
    pos += 1;
}

fn newlist() *List {
    return List.init();
}

// --------------------------------

fn parseArg() *Node {
    // puts_fn("parseArg");

    const t = peek(0);

    switch (t.kind) {
        .INT => {
            pos += 1;
            const n = utils.parseInt(t.getStr());
            return Node.initInt(n);
        },
        .IDENT => {
            pos += 1;
            return Node.initStr(t.getStr());
        },
        else => {
            panic("unexpected token ({})", .{t});
        },
    }
}

fn parseArgs() *List {
    // puts_fn("parseArgs");

    const args = newlist();

    if (peek(0).is(TokenKind.SYM, ")")) {
        return args;
    }

    args.add(parseArg());

    while (peek(0).is(TokenKind.SYM, ",")) {
        pos += 1;
        args.add(parseArg());
    }

    return args;
}

fn parseFunc() *List {
    puts_fn("parseFunc");

    consumeKw("func");

    const fn_name = peek(0).getStr();
    pos += 1;

    consumeSym("(");

    const args = parseArgs();

    consumeSym(")");

    consumeSym("{");

    const stmts = newlist();
    while (true) {
        const t = peek(0);
        if (t.strEq("}")) {
            break;
        }

        if (t.strEq("var")) {
            stmts.addList(parseVar());
        } else {
            stmts.addList(parseStmt());
        }
    }

    consumeSym("}");

    const func = newlist();

    func.addStr("func");
    func.addStr(fn_name);
    func.addList(args);
    func.addList(stmts);

    return func;
}

fn parseVarDeclare() *List {
    puts_fn("parseVarDeclare");

    const t = peek(0);
    pos += 1;
    const var_name = t.getStr();

    consumeSym(";");

    const stmt = newlist();
    stmt.addStr("var");
    stmt.addStr(var_name);
    return stmt;
}

fn parseVarInit() *List {
    const t = peek(0);
    pos += 1;
    const var_name = t.getStr();

    consumeSym("=");

    const expr = parseExpr();

    consumeSym(";");

    const stmt = newlist();
    stmt.addStr("var");
    stmt.addStr(var_name);
    stmt.add(expr);
    return stmt;
}

fn parseVar() *List {
    puts_fn("parseVar");

    consumeKw("var");

    const t = peek(1);

    if (t.is(TokenKind.SYM, ";")) {
        return parseVarDeclare();
    } else {
        return parseVarInit();
    }
}

fn isBinaryOp(t: *Token) bool {
    const s = t.getStr();

    return (
        strEq(s, "+")
        or strEq(s, "*")
        or strEq(s, "==")
        or strEq(s, "!=")
    );
}

fn _parseExprFactor() *Node {
    const t: *Token = peek(0);

    switch (t.kind) {
        .SYM => {
            consumeSym("(");
            const expr = parseExpr();
            consumeSym(")");
            return expr;
        },
        .INT => {
            pos += 1;
            const n = utils.parseInt(t.getStr());
            return Node.initInt(n);
        },
        .IDENT => {
            pos += 1;
            return Node.initStr(t.getStr());
        },
        else => {
            panic("Invalid token kind", .{});
        },
    }
}

fn _convertOp(s: []const u8) []const u8 {
    if (strEq(s, "+")) {
        return "+";
    } else if (strEq(s, "*")) {
        return "*";
    } else if (strEq(s, "==")) {
        return "eq";
    } else if (strEq(s, "!=")) {
        return "neq";
    } else {
        panic("Unsupported operator", .{});
    }
}

fn parseExpr() *Node {
    puts_fn("parseExpr");

    var expr: *Node = _parseExprFactor();

    while (isBinaryOp(peek(0))) {
        const s = peek(0).getStr();
        const op = _convertOp(s);
        pos += 1;

        const exprR = _parseExprFactor();

        const temp = newlist();
        temp.addStr(op);
        temp.add(expr);
        temp.add(exprR);

        expr = Node.initList(temp);
    }

    return expr;
}

fn parseSet() *List {
    puts_fn("parseSet");

    consumeKw("set");

    const t = peek(0);
    pos += 1;
    const var_name = t.getStr();

    consumeSym("=");

    const expr = parseExpr();

    consumeSym(";");

    const stmt = newlist();
    stmt.addStr("set");
    stmt.addStr(var_name);
    stmt.add(expr);
    return stmt;
}

fn parseFuncall() *List {
    puts_fn("parseFuncall");

    const t = peek(0);
    pos += 1;
    const fn_name = t.getStr();

    consumeSym("(");
    const args = parseArgs();
    consumeSym(")");

    const list = newlist();
    list.addStr(fn_name);
    list.addListAll(args);

    return list;
}

fn parseCall() *List {
    puts_fn("parseCall");

    consumeKw("call");

    const funcall = parseFuncall();

    consumeSym(";");

    const stmt = newlist();
    stmt.addStr("call");
    stmt.addListAll(funcall);

    return stmt;
}

fn parseCallSet() *List {
    puts_fn("parseCallSet");

    consumeKw("call_set");

    const t = peek(0);
    pos += 1;
    const var_name = t.getStr();

    consumeSym("=");

    const funcall = parseFuncall();

    consumeSym(";");

    const stmt = newlist();
    stmt.addStr("call_set");

    stmt.addStr(var_name);

    stmt.addList(funcall);
    return stmt;
}

fn parseReturn() *List {
    puts_fn("parseReturn");

    consumeKw("return");

    const expr = parseExpr();

    consumeSym(";");

    const stmt = newlist();
    stmt.addStr("return");
    stmt.add(expr);
    return stmt;
}

fn parseWhile() *List {
    puts_fn("parseWhile");

    consumeKw("while");

    consumeSym("(");
    const expr = parseExpr();
    consumeSym(")");

    consumeSym("{");
    const stmts = parseStmts();
    consumeSym("}");

    const stmt = newlist();
    stmt.addStr("while");
    stmt.add(expr);
    stmt.addList(stmts);
    return stmt;
}

fn parseWhenClause() *List {
    // puts_fn("parseWhenClause")
    const t = peek(0);

    if (t.is(TokenKind.SYM, "}")) {
        return List.empty();
    }

    consumeSym("(");
    const expr = parseExpr();
    consumeSym(")");

    consumeSym("{");
    const stmts = parseStmts();
    consumeSym("}");

    const list = newlist();
    list.add(expr);
    var i: usize = 0;
    while (i < stmts.len) : (i += 1) {
        const stmt = stmts.get(i).getList();
        list.addList(stmt);
    }

    return list;
}

fn parseCase() *List {
    puts_fn("parseCase");

    consumeKw("case");

    consumeSym("{");

    const whenClauses = newlist();

    while (true) {
        const whenClause = parseWhenClause();
        if (whenClause.len == 0) {
            break;
        }
        whenClauses.addList(whenClause);
    }

    consumeSym("}");

    const stmt = newlist();
    stmt.addStr("case");

    var i: usize = 0;
    while (i < whenClauses.len) : (i += 1) {
        const whenClause = whenClauses.get(i).getList();
        stmt.addList(whenClause);
    }

    return stmt;
}

fn parseVmComment() *List {
    puts_fn("parseVmComment");

    consumeKw("_cmt");
    consumeSym("(");

    const t = peek(0);
    pos += 1;
    const cmt = t.getStr();

    consumeSym(")");
    consumeSym(";");

    const stmt = newlist();
    stmt.addStr("_cmt");
    stmt.addStr(cmt);
    return stmt;
}

fn parseDebug() *List {
    puts_fn("parseDebug");

    consumeKw("_debug");
    consumeSym("(");
    consumeSym(")");
    consumeSym(";");

    const stmt = newlist();
    stmt.addStr("_debug");
    return stmt;
}

fn parseStmt() *List {
    puts_fn("parseStmt");

    const t = peek(0);

    if (t.is(TokenKind.SYM, "}")) {
        return List.empty();
    }

    if (t.strEq("set")) {
        return parseSet();
    } else if (t.strEq("call")) {
        return parseCall();
    } else if (t.strEq("call_set")) {
        return parseCallSet();
    } else if (t.strEq("return")) {
        return parseReturn();
    } else if (t.strEq("while")) {
        return parseWhile();
    } else if (t.strEq("case")) {
        return parseCase();
    } else if (t.strEq("_cmt")) {
        return parseVmComment();
    } else if (t.strEq("_debug")) {
        return parseDebug();
    } else {
        putskv_e("pos", pos);
        putskv_e("t", t);
        panic("Unexpected token", .{});
    }
}

fn parseStmts() *List {
    const stmts = newlist();

    while (!isEnd()) {
        const stmt = parseStmt();
        if (stmt.len == 0) {
            break;
        }
        stmts.addList(stmt);
    }

    return stmts;
}

fn parseTopStmt() *List {
    puts_fn("parseTopStmt");

    const t = tokens[pos];

    if (strEq(t.getStr(), "func")) {
        return parseFunc();
    } else {
        panic("Unexpected tokens: pos({}) kind({}) str({})", .{ pos, t.kind, t.getStr() });
    }
}

fn parseTopStmts() *List {
    puts_fn("parseTopStmts");

    const top_stmts = newlist();
    top_stmts.addStr("top_stmts");

    while (!isEnd()) {
        top_stmts.addList(parseTopStmt());
    }

    return top_stmts;
}

pub fn main() !void {
    var buf: [20000]u8 = undefined;
    const src = utils.readStdinAll(&buf);
    try readTokens(src);

    const top_stmts = parseTopStmts();

    json.print(top_stmts);
}
