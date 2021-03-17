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

fn fnArgDisp(names: *Names, name: []const u8) i32 {
    const i = names.indexOf(name);
    if (i == -1) {
        panic("fn arg not found", .{});
    }

    return i + 2;
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

fn formatIndirection(buf: []u8, base: []const u8, disp: i32) []u8 {
    return bufPrint(buf, "[{}:{}]", .{base, disp});
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
                const disp = fnArgDisp(fn_arg_names, str);
                return formatIndirection(buf2[0..], "bp", disp);
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

fn genVar(
    fn_arg_names: *Names,
    lvar_names: *Names,
    stmt_rest: *NodeList,
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
    expr: *NodeList,
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
                _genExprBinary(fn_arg_names, lvar_names, expr.getList());
            },
            else => {
                putskv_e("expr", expr);
                panic("not_yet_impl", .{});
            },
        }
    }
}

fn genCall(fn_arg_names: *Names, lvar_names: *Names, stmt_rest: *NodeList) void {
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
    stmt_rest: *NodeList,
) void {
    puts_fn("genCallSet");

    const lvar_name = stmt_rest.get(0).getStr();
    const funcall = stmt_rest.get(1).getList();

    genCall(fn_arg_names, lvar_names, funcall);

    var buf: [8]u8 = undefined;
    toLvarRef(buf[0..], lvar_names, lvar_name);
    puts_fmt("  cp reg_a {}", .{
        buf[0..strlen(buf[0..])],
    });
}

fn genSet(
    fn_arg_names: *Names,
    lvar_names: *Names,
    stmt_rest: *NodeList,
) void {
    puts_fn("genSet");
    const dest = stmt_rest.get(0);
    const expr = stmt_rest.get(1);

    genExpr(fn_arg_names, lvar_names, expr);

    var buf2: [8]u8 = undefined;
    const arg_dest = toAsmArg(&buf2, fn_arg_names, lvar_names, dest);
    if (0 < arg_dest.len) {
        puts_fmt("  cp reg_a {}", .{ arg_dest });
    } else {
        switch (dest.kind) {
            .STR => {
                if (vramMatch(dest.getStr())) {
                    const vram_arg = getVramParam(dest.getStr());

                    if (matchNumber(vram_arg)) {
                        puts_fmt("  set_vram {} reg_a", .{ vram_arg });
                    } else {
                        var buf3: [8]u8 = undefined;
                        const vram_ref = toAsmArg(&buf3, fn_arg_names, lvar_names, Node.initStr(vram_arg));
                        if (0 < vram_ref.len) {
                            puts_fmt("  set_vram {} reg_a", .{ vram_ref });
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

fn genReturn(
    lvar_names: *Names,
    stmt_rest: *NodeList,
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
    stmt_rest: *NodeList,
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
    when_blocks: *NodeList,
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
    while (i < when_blocks.len) : (i += 1) {
        const when_block = when_blocks.get(i).getList();
        when_idx += 1;

        const cond = head(when_block);
        const _rest = rest(when_block);

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
    stmt: *NodeList,
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
    stmts: *NodeList,
) void {
    var i: usize = 0;
    while (i < stmts.len) : (i += 1) {
        const stmt = stmts.get(i).getList();
        genStmt(fn_arg_names, lvar_names, stmt);
    }
}

fn genFuncDef(top_stmt: *NodeList) void {
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

fn genTopStmts(top_stmts: *NodeList) void {
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

pub fn main() !void {
    var buf: [20000]u8 = undefined;
    const src = utils.readStdinAll(&buf);

    const top_stmts = json.parse(src);

    puts("  call main");
    puts("  exit");

    genTopStmts(top_stmts);
}
