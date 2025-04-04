const std = @import("std");
const panic = std.debug.panic;

const utils = @import("lib/utils.zig");
const print = utils.print;
const print_s = utils.print_s;
const puts = utils.puts;
const puts_s = utils.puts_s;
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

fn asmPrologue() void {
    puts_s("  push bp");
    puts_s("  cp sp bp");
}

fn asmEpilogue() void {
    puts_s("  cp bp sp");
    puts_s("  pop bp");
}

fn fnArgDisp(names: *Names, name: []const u8) i32 {
    const i = names.indexOf(name);
    if (i == -1) {
        panic("fn arg not found", .{});
    }

    return i + 2;
}

fn lvarDisp(names: *Names, name: []const u8) i32 {
    const i = names.indexOf(name);
    if (i == -1) {
        panic("lvar not found", .{});
    }

    return -(i + 1);
}

// --------------------------------

fn genExprAdd() void {
    puts_s("  pop reg_b");
    puts_s("  pop reg_a");
    puts_s("  add_ab");
}

fn genExprMult() void {
    puts_s("  pop reg_b");
    puts_s("  pop reg_a");
    puts_s("  mult_ab");
}

fn genExprEq() void {
    const label_id = getLabelId();

    var buf1: [32]u8 = undefined;
    const then_label = bufPrint(&buf1, "then_{}", .{label_id});
    var buf2: [32]u8 = undefined;
    const end_label = bufPrint(&buf2, "end_eq_{}", .{label_id});

    puts_s("  pop reg_b");
    puts_s("  pop reg_a");

    puts_s("  compare");
    puts_fmt("  jump_eq {s}", .{then_label});

    puts_s("  cp 0 reg_a");
    puts_fmt("  jump {s}", .{end_label});

    puts_fmt("label {s}", .{then_label});
    puts_s("  cp 1 reg_a");
    puts_fmt("label {s}", .{end_label});
}

fn genExprNeq() void {
    const label_id = getLabelId();

    var buf1: [32]u8 = undefined;
    const then_label = bufPrint(&buf1, "then_{}", .{label_id});
    var buf2: [32]u8 = undefined;
    const end_label = bufPrint(&buf2, "end_neq_{}", .{label_id});

    puts_s("  pop reg_b");
    puts_s("  pop reg_a");

    puts_s("  compare");
    puts_fmt("  jump_eq {s}", .{then_label});

    puts_s("  cp 1 reg_a");
    puts_fmt("  jump {s}", .{end_label});

    puts_fmt("label {s}", .{then_label});
    puts_s("  cp 0 reg_a");
    puts_fmt("label {s}", .{end_label});
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
    puts_s("  push reg_a");
    genExpr(fn_arg_names, lvar_names, term_r);
    puts_s("  push reg_a");

    if (strEq(op, "+")) {
        genExprAdd();
    } else if (strEq(op, "*")) {
        genExprMult();
    } else if (strEq(op, "==")) {
        genExprEq();
    } else if (strEq(op, "!=")) {
        genExprNeq();
    } else {
        panic("not_yet_impl ({s})", .{op});
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
                puts_fmt("  cp {} reg_a", .{ intval });
            } else {
                panic("must not happen", .{});
            }
        },
        .STR => {
            const str = expr.getStr();
            if (0 <= lvar_names.indexOf(str)) {
                const disp = lvarDisp(lvar_names, str);
                puts_fmt("  cp [bp:{}] reg_a", .{ disp });
            } else if (0 <= fn_arg_names.indexOf(str)) {
                const disp = fnArgDisp(fn_arg_names, str);
                puts_fmt("  cp [bp:{}] reg_a", .{ disp });
            } else {
                panic("must not happen", .{});
            }
        },
        .LIST => {
            _genExprBinary(fn_arg_names, lvar_names, expr.getList());
        },
    }
}

fn _genFuncall(
    fn_arg_names: *Names,
    lvar_names: *Names,
    funcall: *List
) void {
    const fn_name = head(funcall).getStr();
    const fn_args = rest(funcall);

    if (1 <= fn_args.len) {
        var i: usize = fn_args.len - 1;
        while (true) {
            const fn_arg = fn_args.get(i);
            genExpr(fn_arg_names, lvar_names, fn_arg);
            puts_s("  push reg_a");
            if (i == 0) {
                break;
            } else {
                i -= 1;
            }
        }
    }

    var buf1: [256]u8 = undefined;
    const vm_cmt = bufPrint(&buf1, "call  {s}", .{fn_name});
    genVmComment(vm_cmt);

    puts_fmt("  call {s}", .{fn_name});
    puts_fmt("  add_sp {}", .{fn_args.len});
}

fn genCall(
    fn_arg_names: *Names,
    lvar_names: *Names,
    stmt: *List
) void {
    puts_fn("genCall");

    const funcall = rest(stmt);
    _genFuncall(fn_arg_names, lvar_names, funcall);
}

fn genCallSet(
    fn_arg_names: *Names,
    lvar_names: *Names,
    stmt: *List,
) void {
    puts_fn("genCallSet");

    const lvar_name = stmt.get(1).getStr();
    const funcall   = stmt.get(2).getList();

    _genFuncall(fn_arg_names, lvar_names, funcall);

    const disp = lvarDisp(lvar_names, lvar_name);
    puts_fmt("  cp reg_a [bp:{}]", .{ disp });
}

fn _genSet(
    fn_arg_names: *Names,
    lvar_names: *Names,
    dest: *Node,
    expr: *Node,
) void {
    genExpr(fn_arg_names, lvar_names, expr);

    switch (dest.kind) {
        .STR => {
            const str = dest.getStr();
            if (0 <= lvar_names.indexOf(str)) {
                const disp = lvarDisp(lvar_names, str);
                puts_fmt("  cp reg_a [bp:{}]", .{ disp });
            } else {
                panic("must not happen", .{});
            }
        },
        else => {
            panic("not yet implemented", .{});
        },
    }
}

fn genSet(
    fn_arg_names: *Names,
    lvar_names: *Names,
    stmt: *List,
) void {
    puts_fn("genSet");

    const dest = stmt.get(1);
    const expr = stmt.get(2);
    _genSet(fn_arg_names, lvar_names, dest, expr);
}

fn genReturn(
    fn_arg_names: *Names,
    lvar_names: *Names,
    stmt: *List,
) void {
    const expr = stmt.get(1);
    genExpr(fn_arg_names, lvar_names, expr);
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

    puts_fmt("  _cmt {s}", .{temp[0..i]});
}

fn genDebug() void {
    puts_fn("genDebug");

    puts("  _debug");
}

fn genWhile(
    fn_arg_names: *Names,
    lvar_names: *Names,
    stmt: *List,
) void {
    puts_fn("genWhile");

    const cond_expr = stmt.get(1);
    const stmts     = stmt.get(2).getList();

    const label_id = getLabelId();

    var buf1: [16]u8 = undefined;
    const label_begin = bufPrint(&buf1, "while_{}", .{label_id});

    var buf2: [16]u8 = undefined;
    const label_end = bufPrint(&buf2, "end_while_{}", .{label_id});

    print_s("\n");

    puts_fmt("label {s}", .{label_begin});

    genExpr(fn_arg_names, lvar_names, cond_expr);

    puts_s("  cp 0 reg_b");
    puts_s("  compare");

    puts_fmt("  jump_eq {s}\n", .{label_end});

    genStmts(fn_arg_names, lvar_names, stmts);

    puts_fmt("  jump {s}", .{label_begin});

    puts_fmt("label {s}\n", .{label_end});
    print_s("\n");
}

fn genCase(
    fn_arg_names: *Names,
    lvar_names: *Names,
    stmt: *List,
) void {
    puts_fn("genCase");

    const when_clauses = rest(stmt);

    const label_id = getLabelId();
    var when_idx: i32 = -1;

    var buf1: [32]u8 = undefined;
    const label_end = bufPrint(&buf1, "end_case_{}", .{label_id});

    var buf3: [32]u8 = undefined;
    const label_end_when_head = bufPrint(&buf3, "end_when_{}", .{label_id});

    var i: usize = 0;
    while (i < when_clauses.len) : (i += 1) {
        const when_clause = when_clauses.get(i).getList();
        when_idx += 1;

        const cond = head(when_clause);
        const stmts = rest(when_clause);

        genExpr(fn_arg_names, lvar_names, cond);

        puts_s("  cp 0 reg_b");
        puts_s("  compare");

        puts_fmt("  jump_eq {s}_{}", .{ label_end_when_head, when_idx });

        genStmts(fn_arg_names, lvar_names, stmts);

        puts_fmt("  jump {s}", .{label_end});
        puts_fmt("label {s}_{}", .{ label_end_when_head, when_idx });
    }

    puts_fmt("label end_case_{}", .{label_id});
}

fn genStmt(
    fn_arg_names: *Names,
    lvar_names: *Names,
    stmt: *List,
) void {
    puts_fn("genStmt");

    const stmt_head = head(stmt).getStr();

    if (strEq(stmt_head, "set")) {
        genSet(fn_arg_names, lvar_names, stmt);
    } else if (strEq(stmt_head, "call")) {
        genCall(fn_arg_names, lvar_names, stmt);
    } else if (strEq(stmt_head, "call_set")) {
        genCallSet(fn_arg_names, lvar_names, stmt);
    } else if (strEq(stmt_head, "return")) {
        genReturn(fn_arg_names, lvar_names, stmt);
    } else if (strEq(stmt_head, "while")) {
        genWhile(fn_arg_names, lvar_names, stmt);
    } else if (strEq(stmt_head, "case")) {
        genCase(fn_arg_names, lvar_names, stmt);
    } else if (strEq(stmt_head, "_cmt")) {
        genVmComment(stmt.get(1).str[0..]);
    } else if (strEq(stmt_head, "_debug")) {
        genDebug();
    } else {
        panic("Unsupported statement ({s})", .{stmt_head});
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

fn genVar(
    fn_arg_names: *Names,
    lvar_names: *Names,
    stmt: *List,
) void {
    puts_s("  add_sp -1");

    if (stmt.len == 3) {
        const dest = stmt.get(1);
        const expr = stmt.get(2);
        _genSet(fn_arg_names, lvar_names, dest, expr);
    }
}

fn genFuncDef(func_def: *List) void {
    const fn_name     = func_def.get(1).getStr();
    const fn_arg_vals = func_def.get(2).getList();
    const stmts       = func_def.get(3).getList();

    const fn_arg_names = Names.init();
    var i: usize = 0;
    while (i < fn_arg_vals.size()) : (i += 1) {
        fn_arg_names.add(fn_arg_vals.get(i).getStr());
    }

    const lvar_names = Names.init();

    puts_fmt("label {s}", .{fn_name});

    asmPrologue();

    i = 0;
    while (i < stmts.len) : (i += 1) {
        const stmt = stmts.get(i).getList();

        const stmt_head = head(stmt).getStr();

        if (strEq(stmt_head, "var")) {
            const varName = stmt.get(1).getStr();
            lvar_names.add(varName);

            genVar(fn_arg_names, lvar_names, stmt);
        } else {
            genStmt(fn_arg_names, lvar_names, stmt);
        }
    }

    asmEpilogue();
    puts_s("  ret");
}

fn genTopStmts(top_stmts: *List) void {
    var i: usize = 1;
    while (i < top_stmts.len) : (i += 1) {
        const top_stmt = top_stmts.get(i).getList();

        const stmt_head = head(top_stmt).getStr();

        if (strEq(stmt_head, "func")) {
            genFuncDef(top_stmt);
        } else {
            panic("must not happen ({s})", .{stmt_head});
        }
    }
}

fn genBuiltinSetVram() void {
    puts_s("");
    puts_s("label set_vram");
    asmPrologue();

    puts_s("  set_vram [bp:2] [bp:3]"); // vram_addr value

    asmEpilogue();
    puts_s("  ret");
}

fn genBuiltinGetVram() void {
    puts_s("");
    puts_s("label get_vram");
    asmPrologue();

    puts_s("  get_vram [bp:2] reg_a"); // vram_addr dest

    asmEpilogue();
    puts_s("  ret");
}

pub fn main() !void {
    var buf: [20000]u8 = undefined;
    const src = utils.readStdinAll(&buf);

    const top_stmts = json.parse(src);

    puts_s("  call main");
    puts_s("  exit");

    genTopStmts(top_stmts);

    puts_s("");
    puts_s("#>builtins");
    genBuiltinSetVram();
    genBuiltinGetVram();
    puts_s("#<builtins");
}
