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
const NodeList = types.NodeList;
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

fn head(list: *NodeList) *Node {
    return list.get(0);
}

fn rest(list: *NodeList) *NodeList {
    const new_list = NodeList.init();
    var i: usize = 1;
    while (i < list.len) : (i += 1) {
        new_list.add(list.get(i));
    }
    return new_list;
}

// --------------------------------

fn toFnArgRef(dest: []u8, names: *Names, name: []const u8) void {
    const i = names.indexOf(name);
    if (i == -1) {
        panic("fn arg not found", .{});
    }

    const ret: []u8 = std.fmt.bufPrint(dest, "[bp:{}]", .{i + 2}) catch |err| {
        panic("err ({})", .{err});
    };

    dest[ret.len] = 0;
}

fn toLvarRef(dest: []u8, names: *Names, name: []const u8) void {
    const i = names.indexOf(name);
    if (i == -1) {
        panic("lvar not found", .{});
    }

    const ret: []u8 = std.fmt.bufPrint(dest, "[bp:-{}]", .{i + 1}) catch |err| {
        panic("err ({})", .{err});
    };

    dest[ret.len] = 0;
}

fn toAsmArg(
    buf: [*]u8,
    fn_arg_names: *Names,
    lvar_names: *Names,
    node: *Node,
) []const u8 {
    // puts_fn("toAsmArg");
    switch (node.kind) {
        .INT => {
            if (node.int) |intval| {
                var buf1: [16]u8 = undefined;
                const size = std.fmt.formatIntBuf(buf1[0..], intval, 10, false, std.fmt.FormatOptions{});

                var i: usize = 0;
                while (i < size) : (i += 1) {
                    buf[i] = buf1[i];
                }

                return buf[0..size];
            } else {
                panic("must not happen", .{});
            }
        },
        .STR => {
            var buf2: [16]u8 = undefined;
            const str = node.getStr();
            if (0 <= lvar_names.indexOf(str)) {
                toLvarRef(buf2[0..], lvar_names, str);
                utils.strcpy(buf, buf2[0..]);
                const len = strlen(buf2[0..]);
                return buf[0..len];
            } else if (0 <= fn_arg_names.indexOf(str)) {
                toFnArgRef(buf2[0..], fn_arg_names, str);
                utils.strcpy(buf, buf2[0..]);
                const len = strlen(buf2[0..]);
                return buf[0..len];
            } else {
                return "";
            }
        },
        else => {
            return "";
        },
    }
}

fn vramMatch(str: []const u8) bool {
    return strEq(str[0..5], "vram[") and str[str.len - 1] == ']';
}

fn getVramParam(str: []const u8) []const u8 {
    const i = utils.indexOf(str, ']', 5);
    if (i == -1) {
        panic("must not happen", .{});
    } else {
        return str[5..@intCast(usize, i)];
    }
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

fn codegenVar(
    fn_arg_names: *Names,
    lvar_names: *Names,
    stmt_rest: *NodeList,
) void {
    puts("  sub_sp 1");

    if (stmt_rest.len == 2) {
        codegenSet(fn_arg_names, lvar_names, stmt_rest);
    }
}

fn codegenExprAdd() void {
    puts("  pop reg_b");
    puts("  pop reg_a");
    puts("  add_ab");
}

fn codegenExprMult() void {
    puts("  pop reg_b");
    puts("  pop reg_a");
    puts("  mult_ab");
}

fn codegenExprEq() void {
    const label_id = getLabelId();

    var buf1: [32]u8 = undefined;
    const then_label = bufPrint(&buf1, "then_{}", .{label_id});
    var buf2: [32]u8 = undefined;
    const end_label = bufPrint(&buf2, "end_eq_{}", .{label_id});

    puts("  pop reg_b");
    puts("  pop reg_a");

    puts("  compare");
    puts_fmt("  jump_eq {}", .{then_label});

    puts("  set_reg_a 0");
    puts_fmt("  jump {}", .{end_label});

    puts_fmt("label {}", .{then_label});
    puts("  set_reg_a 1");
    puts_fmt("label {}", .{end_label});
}

fn codegenExprNeq() void {
    const label_id = getLabelId();

    var buf1: [32]u8 = undefined;
    const then_label = bufPrint(&buf1, "then_{}", .{label_id});
    var buf2: [32]u8 = undefined;
    const end_label = bufPrint(&buf2, "end_neq_{}", .{label_id});

    puts("  pop reg_b");
    puts("  pop reg_a");

    puts("  compare");
    puts_fmt("  jump_eq {}", .{then_label});

    puts("  set_reg_a 1");
    puts_fmt("  jump {}", .{end_label});

    puts_fmt("label {}", .{then_label});
    puts("  set_reg_a 0");
    puts_fmt("label {}", .{end_label});
}

fn _codegenExprBinary(
    fn_arg_names: *Names,
    lvar_names: *Names,
    expr: *NodeList,
) void {
    // puts_fn("_codegenExprBinary");

    const op = head(expr).getStr();
    const args = rest(expr);

    const term_l = args.get(0);
    const term_r = args.get(1);

    codegenExpr(fn_arg_names, lvar_names, term_l);
    puts("  push reg_a");
    codegenExpr(fn_arg_names, lvar_names, term_r);
    puts("  push reg_a");

    if (strEq(op, "+")) {
        codegenExprAdd();
    } else if (strEq(op, "*")) {
        codegenExprMult();
    } else if (strEq(op, "eq")) {
        codegenExprEq();
    } else if (strEq(op, "neq")) {
        codegenExprNeq();
    } else {
        panic("not_yet_impl ({})", .{op});
    }
}

fn codegenExpr(
    fn_arg_names: *Names,
    lvar_names: *Names,
    expr: *Node,
) void {
    puts_fn("codegenExpr");

    var buf: [8]u8 = undefined;
    var push_arg: []const u8 = toAsmArg(&buf, fn_arg_names, lvar_names, expr);

    if (0 < push_arg.len) {
        puts_fmt("  cp {} reg_a", .{push_arg});
    } else {
        switch (expr.kind) {
            .STR => {
                if (vramMatch(expr.getStr())) {
                    const vram_arg = getVramParam(expr.getStr());

                    if (matchNumber(vram_arg)) {
                        puts_fmt("  get_vram {} reg_a", .{vram_arg});
                    } else {
                        var buf2: [8]u8 = undefined;
                        const vram_ref: []const u8 = toAsmArg(&buf2, fn_arg_names, lvar_names, Node.initStr(vram_arg));
                        if (0 < vram_ref.len) {
                            puts_fmt("  get_vram {} reg_a", .{vram_ref});
                        } else {
                            panic("not_yet_impl", .{});
                        }
                    }
                } else {
                    panic("not_yet_impl", .{});
                }
            },
            .LIST => {
                _codegenExprBinary(fn_arg_names, lvar_names, expr.getList());
            },
            else => {
                putskv_e("expr", expr);
                panic("not_yet_impl", .{});
            },
        }
    }
}

fn codegenCall(fn_arg_names: *Names, lvar_names: *Names, stmt_rest: *NodeList) void {
    puts_fn("codegenCall");

    const fn_name = head(stmt_rest).getStr();
    const fn_args = rest(stmt_rest);

    if (1 <= fn_args.len) {
        var i: usize = fn_args.len - 1;
        while (true) {
            const fn_arg = fn_args.get(i);
            codegenExpr(fn_arg_names, lvar_names, fn_arg);
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
    codegenVmComment(vm_cmt);

    puts_fmt("  call {}", .{fn_name});
    puts_fmt("  add_sp {}", .{fn_args.len});
}

fn codegenCallSet(
    fn_arg_names: *Names,
    lvar_names: *Names,
    stmt_rest: *NodeList,
) void {
    puts_fn("codegenCallSet");

    const lvar_name = stmt_rest.get(0).getStr();
    const fn_temp = stmt_rest.get(1).getList();

    const fn_name = head(fn_temp).getStr();
    const fn_args = rest(fn_temp);

    if (1 <= fn_args.size()) {
        var i: usize = fn_args.size() - 1;
        while (true) : (i -= 1) {
            const fn_arg = fn_args.get(i);
            codegenExpr(fn_arg_names, lvar_names, fn_arg);
            puts("  push reg_a");

            if (i == 0) {
                break;
            }
        }
    }

    puts_fmt("  _cmt call_set~~{}", .{fn_name});
    puts_fmt("  call {}", .{fn_name});
    puts_fmt("  add_sp {}", .{fn_args.size()});

    var buf: [8]u8 = undefined;
    toLvarRef(buf[0..], lvar_names, lvar_name);
    puts_fmt("  cp reg_a {}", .{
        buf[0..strlen(buf[0..])],
    });
}

fn codegenSet(
    fn_arg_names: *Names,
    lvar_names: *Names,
    stmt_rest: *NodeList,
) void {
    puts_fn("codegenSet");
    const dest = stmt_rest.get(0);
    const expr = stmt_rest.get(1);

    var arg_src: []const u8 = undefined;

    var buf: [8]u8 = undefined;
    arg_src = toAsmArg(&buf, fn_arg_names, lvar_names, expr);

    if (arg_src.len == 0) {
        switch (expr.kind) {
            .LIST => {
                if (expr.list) |_list| {
                    _codegenExprBinary(fn_arg_names, lvar_names, _list);
                }
                arg_src = "reg_a";
            },
            .STR => {
                if (vramMatch(expr.getStr())) {
                    const vram_arg = getVramParam(expr.getStr());

                    if (matchNumber(vram_arg)) {
                        puts_fmt("  get_vram {} reg_a", .{vram_arg});
                    } else {
                        var buf2: [8]u8 = undefined;
                        const vram_ref: []const u8 = toAsmArg(&buf2, fn_arg_names, lvar_names, Node.initStr(vram_arg));
                        if (0 < vram_ref.len) {
                            puts_fmt("  get_vram {} reg_a", .{vram_ref});
                        } else {
                            panic("not_yet_impl", .{});
                        }
                    }
                    arg_src = "reg_a";
                } else {
                    panic("not_yet_impl", .{});
                }
            },
            else => {
                putskv_e("expr", expr);
                panic("not_yet_impl", .{});
            },
        }
    }

    var buf2: [8]u8 = undefined;
    const arg_dest = toAsmArg(&buf2, fn_arg_names, lvar_names, dest);
    if (0 < arg_dest.len) {
        puts_fmt("  cp {} {}", .{ arg_src, arg_dest });
    } else {
        switch (dest.kind) {
            .STR => {
                if (vramMatch(dest.getStr())) {
                    const vram_arg = getVramParam(dest.getStr());

                    if (matchNumber(vram_arg)) {
                        puts_fmt("  set_vram {} {}", .{ vram_arg, arg_src });
                    } else {
                        var buf3: [8]u8 = undefined;
                        const vram_ref = toAsmArg(&buf3, fn_arg_names, lvar_names, Node.initStr(vram_arg));
                        if (0 < vram_ref.len) {
                            puts_fmt("  set_vram {} {}", .{ vram_ref, arg_src });
                        } else {
                            panic("not_yet_impl", .{});
                        }
                    }
                } else {
                    panic("not_yet_impl", .{});
                }
            },
            else => {
                panic("not_yet_impl", .{});
            },
        }
    }
}

fn codegenReturn(
    lvar_names: *Names,
    stmt_rest: *NodeList,
) void {
    const retval = head(stmt_rest);
    var buf1: [16]u8 = undefined;
    const asm_arg = toAsmArg(&buf1, Names.empty(), lvar_names, retval);
    if (0 < asm_arg.len) {
        puts_fmt("  cp {} reg_a", .{asm_arg});
    } else {
        switch (retval.kind) {
            .STR => {
                const str = retval.getStr();

                if (vramMatch(str)) {
                    const vram_arg = getVramParam(str);

                    if (matchNumber(vram_arg)) {
                        panic("not_yet_impl", .{});
                    } else {
                        var buf2: [8]u8 = undefined;
                        const vram_ref = toAsmArg(&buf1, Names.empty(), lvar_names, Node.initStr(vram_arg));
                        if (0 < vram_ref.len) {
                            puts_fmt("  get_vram {} reg_a", .{vram_ref});
                        } else {
                            panic("not_yet_impl", .{});
                        }
                    }
                } else {
                    panic("not_yet_impl", .{});
                }
            },
            else => {
                panic("not_yet_impl", .{});
            },
        }
    }
}

fn codegenVmComment(cmt: []const u8) void {
    puts_fn("codegenVmComment");

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

fn codegenWhile(
    fn_arg_names: *Names,
    lvar_names: *Names,
    stmt_rest: *NodeList,
) void {
    puts_fn("codegenWhile");

    const cond_expr = stmt_rest.get(0).getList();
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

    _codegenExprBinary(fn_arg_names, lvar_names, cond_expr);

    puts("  set_reg_b 1");
    puts("  compare");

    puts_fmt("  jump_eq {}\n", .{label_true});
    puts_fmt("  jump {}\n", .{label_end});
    puts_fmt("label {}\n", .{label_true});

    codegenStmts(fn_arg_names, lvar_names, body);

    puts_fmt("  jump {}", .{label_begin});

    puts_fmt("label {}\n", .{label_end});
    print("\n");
}

fn codegenCase(
    fn_arg_names: *Names,
    lvar_names: *Names,
    when_blocks: *NodeList,
) void {
    puts_fn("codegenCase");

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
    while (i < when_blocks.len) : (i += 1) {
        const when_block = when_blocks.get(i).getList();
        when_idx += 1;

        const cond = head(when_block).getList();
        const _rest = rest(when_block);

        const cond_head = head(cond).getStr();
        // const cond_rest = rest(cond);

        puts_fmt("  # when_{}_{}", .{ label_id, when_idx });

        if (strEq(cond_head, "eq")) {
            puts("  # -->> expr");
            _codegenExprBinary(fn_arg_names, lvar_names, cond);
            puts("  # <<-- expr");

            puts("  set_reg_b 1");

            puts("  compare");
            puts_fmt("  jump_eq {}_{}", .{ label_when_head, when_idx });
            puts_fmt("  jump {}_{}", .{ label_end_when_head, when_idx });

            puts_fmt("label {}_{}", .{ label_when_head, when_idx });

            codegenStmts(fn_arg_names, lvar_names, _rest);

            puts_fmt("  jump {}", .{label_end});
            puts_fmt("label {}_{}", .{ label_end_when_head, when_idx });
        } else {
            panic("not_yet_impl", .{});
        }
    }

    puts_fmt("label end_case_{}", .{label_id});
    puts_fmt("  # <<-- case_{}", .{label_id});
    print("\n");
}

fn codegenStmt(
    fn_arg_names: *Names,
    lvar_names: *Names,
    stmt: *NodeList,
) void {
    puts_fn("codegenStmt");

    const stmt_head = head(stmt).getStr();
    const stmt_rest = rest(stmt);

    if (strEq(stmt_head, "set")) {
        codegenSet(fn_arg_names, lvar_names, stmt_rest);
    } else if (strEq(stmt_head, "call")) {
        codegenCall(fn_arg_names, lvar_names, stmt_rest);
    } else if (strEq(stmt_head, "call_set")) {
        codegenCallSet(fn_arg_names, lvar_names, stmt_rest);
    } else if (strEq(stmt_head, "return")) {
        codegenReturn(lvar_names, stmt_rest);
    } else if (strEq(stmt_head, "while")) {
        codegenWhile(fn_arg_names, lvar_names, stmt_rest);
    } else if (strEq(stmt_head, "case")) {
        codegenCase(fn_arg_names, lvar_names, stmt_rest);
    } else if (strEq(stmt_head, "_cmt")) {
        codegenVmComment(stmt_rest.get(0).str[0..]);
    } else {
        panic("Unsupported statement ({})", .{stmt_head});
    }
}

fn codegenStmts(
    fn_arg_names: *Names,
    lvar_names: *Names,
    stmts: *NodeList,
) void {
    var i: usize = 0;
    while (i < stmts.len) : (i += 1) {
        const stmt = stmts.get(i).getList();
        codegenStmt(fn_arg_names, lvar_names, stmt);
    }
}

fn codegenFuncDef(top_stmt: *NodeList) void {
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

            codegenVar(fn_arg_names, lvar_names, stmt_rest);
        } else {
            codegenStmt(fn_arg_names, lvar_names, stmt);
        }
    }

    puts("  cp bp sp");
    puts("  pop bp");
    puts("  ret");
}

fn codegenTopStmts(top_stmts: *NodeList) void {
    var i: usize = 1;
    while (i < top_stmts.len) : (i += 1) {
        const top_stmt = top_stmts.get(i).getList();

        const stmt_head = head(top_stmt).getStr();
        const stmt_rest = rest(top_stmt);

        if (strEq(stmt_head, "func")) {
            codegenFuncDef(stmt_rest);
        } else {
            panic("must not happen ({})", .{stmt_head});
        }
    }
}

pub fn main() !void {
    var buf: [20000]u8 = undefined;
    const src = utils.readStdinAll(&buf);

    const top_stmts = json.parse(src);

    puts("  call main");
    puts("  exit");

    codegenTopStmts(top_stmts);
}
