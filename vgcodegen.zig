// -*- mode: javascript; js-indent-level: 4 -*-

const std = @import("std");
const panic = std.debug.panic;

const utils = @import("lib/utils.zig");
const print = utils.print;
const puts = utils.puts;
const puts_fmt = utils.puts_fmt;
const print_e = utils.print_e;
const puts_e = utils.puts_e;
const putskv_e = utils.putskv_e;
const puts_fn = utils.puts_fn;

const bufPrint = utils.bufPrint;

const strEq = utils.strEq;
const strlen = utils.strlen;

const allocator = std.heap.page_allocator;

const types = @import("lib/types.zig");
const List = types.List;
const Node = types.Node;
const NodeKind = types.NodeKind;
const Names = types.Names;

const json = @import("lib/json.zig");

var gLabelId: i32 = 0;

// --------------------------------

fn getLabelId() i32 {
    gLabelId += 1;
    return gLabelId;
}

fn head(list: *List) *Node {
    return list.get(0);
}

fn rest(list: *List) *List {
    const new_list = List.init();
    var i: usize = 1;
    while (i < list.len) : (i += 1) {
        new_list.add(list.get(i));
    }
    return new_list;
}

// --------------------------------

fn fnArgDisp(names: *Names, name: []const u8) i32 {
    const i = names.indexOf(name);
    if (i == -1) {
        panic("fn arg not found", .{});
    }

    return i + 2;
}

fn lvarDisp(dest: []u8, names: *Names, name: []const u8) i32 {
    const i = names.indexOf(name);
    if (i == -1) {
        panic("lvar not found", .{});
    }

    return -(i + 1);
}

fn formatIndirection(buf: []u8, base: []const u8, disp: i32) []u8 {
    return bufPrint(buf, "[{}:{}]", .{base, disp});
}

fn matchNumber(str: []const u8) bool {
    var i: usize = 0;
    while (i < str.len) : (i += 1) {
        if (!utils.isNumeric(str[i])) {
            return false;
        }
    }
    return true;
}

// --------------------------------

fn genVar(
    fn_arg_names: *Names,
    lvar_names: *Names,
    stmt_rest: *List,
) void {
    puts("  sub_sp 1");

    if (stmt_rest.len == 2) {
        genSet(fn_arg_names, lvar_names, stmt_rest);
    }
}

fn genExprAdd() void {
    puts("  pop reg_b");
    puts("  pop reg_a");
    puts("  add_ab");
}

fn genExprMult() void {
    puts("  pop reg_b");
    puts("  pop reg_a");
    puts("  mult_ab");
}

fn genExprEq() void {
    const label_id = getLabelId();

    var buf1: [32]u8 = undefined;
    const then_label = bufPrint(&buf1, "then_{}", .{label_id});
    var buf2: [32]u8 = undefined;
    const end_label = bufPrint(&buf2, "end_eq_{}", .{label_id});

    puts("  pop reg_b");
    puts("  pop reg_a");

    puts("  compare");
    puts_fmt("  jump_eq {}", .{then_label});

    puts("  cp 0 reg_a");
    puts_fmt("  jump {}", .{end_label});

    puts_fmt("label {}", .{then_label});
    puts("  cp 1 reg_a");
    puts_fmt("label {}", .{end_label});
}

fn genExprNeq() void {
    const label_id = getLabelId();

    var buf1: [32]u8 = undefined;
    const then_label = bufPrint(&buf1, "then_{}", .{label_id});
    var buf2: [32]u8 = undefined;
    const end_label = bufPrint(&buf2, "end_neq_{}", .{label_id});

    puts("  pop reg_b");
    puts("  pop reg_a");

    puts("  compare");
    puts_fmt("  jump_eq {}", .{then_label});

    puts("  cp 1 reg_a");
    puts_fmt("  jump {}", .{end_label});

    puts_fmt("label {}", .{then_label});
    puts("  cp 0 reg_a");
    puts_fmt("label {}", .{end_label});
}

fn _genExprBinary(
    fn_arg_names: *Names,
    lvar_names: *Names,
    expr: *List,
) void {
    // puts_fn("_genExprBinary");

    const op = head(expr).getStr();
    const args = rest(expr);

    const term_l = args.get(0);
    const term_r = args.get(1);

    genExpr(fn_arg_names, lvar_names, term_l);
    puts("  push reg_a");
    genExpr(fn_arg_names, lvar_names, term_r);
    puts("  push reg_a");

    if (strEq(op, "+")) {
        genExprAdd();
    } else if (strEq(op, "*")) {
        genExprMult();
    } else if (strEq(op, "eq")) {
        genExprEq();
    } else if (strEq(op, "neq")) {
        genExprNeq();
    } else {
        panic("not_yet_impl ({})", .{op});
    }
}

fn genExpr(
    fn_arg_names: *Names,
    lvar_names: *Names,
    expr: *Node,
) void {
    puts_fn("genExpr");

    switch (expr.kind) {
        .INT => {
            if (expr.int) |intval| {
                var buf1: [16]u8 = undefined;
                puts_fmt("  cp {} reg_a", .{ intval });
            } else {
                panic("must not happen", .{});
            }
        },
        .STR => {
            var buf2: [16]u8 = undefined;
            const str = expr.getStr();
            if (0 <= lvar_names.indexOf(str)) {
                const disp = lvarDisp(buf2[0..], lvar_names, str);
                const cp_src = formatIndirection(buf2[0..], "bp", disp);
                puts_fmt("  cp {} reg_a", .{ cp_src });
            } else if (0 <= fn_arg_names.indexOf(str)) {
                const disp = fnArgDisp(fn_arg_names, str);
                const cp_src = formatIndirection(buf2[0..], "bp", disp);
                puts_fmt("  cp {} reg_a", .{ cp_src });
            } else {
                panic("must not happen", .{});
            }
        },
        .LIST => {
            _genExprBinary(fn_arg_names, lvar_names, expr.getList());
        },
    }
}

fn genCall(fn_arg_names: *Names, lvar_names: *Names, stmt_rest: *List) void {
    puts_fn("genCall");

    const fn_name = head(stmt_rest).getStr();
    const fn_args = rest(stmt_rest);

    if (1 <= fn_args.len) {
        var i: usize = fn_args.len - 1;
        while (true) {
            const fn_arg = fn_args.get(i);
            genExpr(fn_arg_names, lvar_names, fn_arg);
            puts("  push reg_a");
            if (i == 0) {
                break;
            } else {
                i -= 1;
            }
        }
    }

    var buf1: [256]u8 = undefined;
    const vm_cmt = bufPrint(&buf1, "call  {}", .{fn_name});
    genVmComment(vm_cmt);

    puts_fmt("  call {}", .{fn_name});
    puts_fmt("  add_sp {}", .{fn_args.len});
}

fn genCallSet(
    fn_arg_names: *Names,
    lvar_names: *Names,
    stmt_rest: *List,
) void {
    puts_fn("genCallSet");

    const lvar_name = stmt_rest.get(0).getStr();
    const funcall = stmt_rest.get(1).getList();

    genCall(fn_arg_names, lvar_names, funcall);

    var buf: [8]u8 = undefined;
    const disp = lvarDisp(buf[0..], lvar_names, lvar_name);
    var cp_dest = formatIndirection(buf[0..], "bp", disp);
    puts_fmt("  cp reg_a {}", .{ cp_dest });
}

fn genSet(
    fn_arg_names: *Names,
    lvar_names: *Names,
    stmt_rest: *List,
) void {
    puts_fn("genSet");
    const dest = stmt_rest.get(0);
    const expr = stmt_rest.get(1);

    genExpr(fn_arg_names, lvar_names, expr);

    switch (dest.kind) {
        .STR => {
            var buf2: [16]u8 = undefined;
            const str = dest.getStr();
            if (0 <= lvar_names.indexOf(str)) {
                const disp = lvarDisp(buf2[0..], lvar_names, str);
                const cp_dest = formatIndirection(buf2[0..], "bp", disp);
                puts_fmt("  cp reg_a {}", .{ cp_dest });
            } else if (0 <= fn_arg_names.indexOf(str)) {
                const disp = fnArgDisp(fn_arg_names, str);
                const cp_dest = formatIndirection(buf2[0..], "bp", disp);
                puts_fmt("  cp reg_a {}", .{ cp_dest });
            } else {
                panic("must not happen", .{});
            }
        },
        else => {
            panic("not yet implemented", .{});
        },
    }
}

fn genReturn(
    lvar_names: *Names,
    stmt_rest: *List,
) void {
    const retval = head(stmt_rest);
    genExpr(Names.empty(), lvar_names, retval);
}

fn genVmComment(cmt: []const u8) void {
    puts_fn("genVmComment");

    var temp: [256]u8 = undefined;

    var i: usize = 0;
    while (i < cmt.len and cmt[i] != 0) : (i += 1) {
        if (cmt[i] == ' ') {
            temp[i] = '~';
        } else {
            temp[i] = cmt[i];
        }
    }

    puts_fmt("  _cmt {}", .{temp[0..i]});
}

fn genWhile(
    fn_arg_names: *Names,
    lvar_names: *Names,
    stmt_rest: *List,
) void {
    puts_fn("genWhile");

    const cond_expr = stmt_rest.get(0);
    const body = stmt_rest.get(1).getList();

    const label_id = getLabelId();

    var buf1: [16]u8 = undefined;
    const label_begin = bufPrint(&buf1, "while_{}", .{label_id});

    var buf2: [16]u8 = undefined;
    const label_end = bufPrint(&buf2, "end_while_{}", .{label_id});

    var buf3: [16]u8 = undefined;
    const label_true = bufPrint(&buf3, "true_{}", .{label_id});

    print("\n");

    puts_fmt("label {}", .{label_begin});

    genExpr(fn_arg_names, lvar_names, cond_expr);

    puts("  cp 1 reg_b");
    puts("  compare");

    puts_fmt("  jump_eq {}\n", .{label_true});
    puts_fmt("  jump {}\n", .{label_end});
    puts_fmt("label {}\n", .{label_true});

    genStmts(fn_arg_names, lvar_names, body);

    puts_fmt("  jump {}", .{label_begin});

    puts_fmt("label {}\n", .{label_end});
    print("\n");
}

fn genCase(
    fn_arg_names: *Names,
    lvar_names: *Names,
    when_clauses: *List,
) void {
    puts_fn("genCase");

    const label_id = getLabelId();
    var when_idx: i32 = -1;

    var buf1: [32]u8 = undefined;
    const label_end = bufPrint(&buf1, "end_case_{}", .{label_id});

    var buf2: [32]u8 = undefined;
    const label_when_head = bufPrint(&buf2, "when_{}", .{label_id});

    var buf3: [32]u8 = undefined;
    const label_end_when_head = bufPrint(&buf3, "end_when_{}", .{label_id});

    print("\n");
    puts_fmt("  # -->> case_{}", .{label_id});

    var i: usize = 0;
    while (i < when_clauses.len) : (i += 1) {
        const when_clause = when_clauses.get(i).getList();
        when_idx += 1;

        const cond = head(when_clause);
        const _rest = rest(when_clause);

        puts_fmt("  # when_{}_{}", .{ label_id, when_idx });

        puts("  # -->> expr");
        genExpr(fn_arg_names, lvar_names, cond);
        puts("  # <<-- expr");

        puts("  cp 1 reg_b");

        puts("  compare");
        puts_fmt("  jump_eq {}_{}", .{ label_when_head, when_idx });
        puts_fmt("  jump {}_{}", .{ label_end_when_head, when_idx });

        puts_fmt("label {}_{}", .{ label_when_head, when_idx });

        genStmts(fn_arg_names, lvar_names, _rest);

        puts_fmt("  jump {}", .{label_end});
        puts_fmt("label {}_{}", .{ label_end_when_head, when_idx });
    }

    puts_fmt("label end_case_{}", .{label_id});
    puts_fmt("  # <<-- case_{}", .{label_id});
    print("\n");
}

fn genStmt(
    fn_arg_names: *Names,
    lvar_names: *Names,
    stmt: *List,
) void {
    puts_fn("genStmt");

    const stmt_head = head(stmt).getStr();
    const stmt_rest = rest(stmt);

    if (strEq(stmt_head, "set")) {
        genSet(fn_arg_names, lvar_names, stmt_rest);
    } else if (strEq(stmt_head, "call")) {
        genCall(fn_arg_names, lvar_names, stmt_rest);
    } else if (strEq(stmt_head, "call_set")) {
        genCallSet(fn_arg_names, lvar_names, stmt_rest);
    } else if (strEq(stmt_head, "return")) {
        genReturn(lvar_names, stmt_rest);
    } else if (strEq(stmt_head, "while")) {
        genWhile(fn_arg_names, lvar_names, stmt_rest);
    } else if (strEq(stmt_head, "case")) {
        genCase(fn_arg_names, lvar_names, stmt_rest);
    } else if (strEq(stmt_head, "_cmt")) {
        genVmComment(stmt_rest.get(0).str[0..]);
    } else {
        panic("Unsupported statement ({})", .{stmt_head});
    }
}

fn genStmts(
    fn_arg_names: *Names,
    lvar_names: *Names,
    stmts: *List,
) void {
    var i: usize = 0;
    while (i < stmts.len) : (i += 1) {
        const stmt = stmts.get(i).getList();
        genStmt(fn_arg_names, lvar_names, stmt);
    }
}

fn genFuncDef(top_stmt: *List) void {
    const fn_name = top_stmt.get(0).getStr();
    const fn_arg_vals = top_stmt.get(1).getList();
    const body = top_stmt.get(2).getList();

    const fn_arg_names = Names.init();
    var i: usize = 0;
    while (i < fn_arg_vals.size()) : (i += 1) {
        fn_arg_names.add(fn_arg_vals.get(i).getStr());
    }

    const lvar_names = Names.init();

    puts_fmt("label {}", .{fn_name});

    puts("  push bp");
    puts("  cp sp bp");

    i = 0;
    while (i < body.len) : (i += 1) {
        const stmt = body.get(i).getList();

        const stmt_head = head(stmt).getStr();
        const stmt_rest = rest(stmt);

        if (strEq(stmt_head, "var")) {
            const varName = stmt_rest.get(0).getStr();
            lvar_names.add(varName);

            genVar(fn_arg_names, lvar_names, stmt_rest);
        } else {
            genStmt(fn_arg_names, lvar_names, stmt);
        }
    }

    puts("  cp bp sp");
    puts("  pop bp");
    puts("  ret");
}

fn genTopStmts(top_stmts: *List) void {
    var i: usize = 1;
    while (i < top_stmts.len) : (i += 1) {
        const top_stmt = top_stmts.get(i).getList();

        const stmt_head = head(top_stmt).getStr();
        const stmt_rest = rest(top_stmt);

        if (strEq(stmt_head, "func")) {
            genFuncDef(stmt_rest);
        } else {
            panic("must not happen ({})", .{stmt_head});
        }
    }
}

fn genBuiltinSetVram() void {
    puts("");
    puts("label set_vram");
    puts("  push bp");
    puts("  cp sp bp");

    puts("  set_vram [bp:2] [bp:3]"); // vram_addr value

    puts("  cp bp sp");
    puts("  pop bp");
    puts("  ret");
}

fn genBuiltinGetVram() void {
    puts("");
    puts("label get_vram");
    puts("  push bp");
    puts("  cp sp bp");

    puts("  get_vram [bp:2] reg_a"); // vram_addr dest

    puts("  cp bp sp");
    puts("  pop bp");
    puts("  ret");
}

pub fn main() !void {
    var buf: [20000]u8 = undefined;
    const src = utils.readStdinAll(&buf);

    const top_stmts = json.parse(src);

    puts("  call main");
    puts("  exit");

    genTopStmts(top_stmts);

    puts("");
    puts("#>builtins");
    genBuiltinSetVram();
    genBuiltinGetVram();
    puts("#<builtins");
}
