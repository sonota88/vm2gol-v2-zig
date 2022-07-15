const std = @import("std");
const panic = std.debug.panic;

const utils = @import("utils.zig");
const _print = utils.print;
const puts_e = utils.puts_e;

const types = @import("types.zig");
const NodeKind = types.NodeKind;
const Node = types.Node;
const List = types.List;

const allocator = std.heap.page_allocator;

pub fn parseList(input_json: []const u8, size: *usize) *List {
    const list = List.init();
    var pos: usize = 1;
    var rest: []const u8 = undefined;

    while (pos < input_json.len) {
        rest = input_json[pos..];

        if (rest[0] == ']') {
            pos += 1;
            break;
        } else if (rest[0] == '[') {
            var inner_list_size: usize = undefined;
            const inner_list = parseList(rest, &inner_list_size);
            list.addList(inner_list);
            pos += inner_list_size;
        } else if (rest[0] == ' ' or rest[0] == '\n' or rest[0] == ',') {
            pos += 1;
        } else if (utils.isNumeric(rest[0]) or rest[0] == '-') {
            const idx = utils.indexOfNonNumeric(rest, 1);
            const matched_part = rest[0..idx];
            const n: i32 = utils.parseInt(matched_part);

            list.addInt(n);
            pos += matched_part.len;
        } else if (rest[0] == '"') {
            const idx: i32 = utils.indexOf(rest, '"', 1);
            var usize_idx: usize = 0;
            if (1 <= idx) {
                usize_idx = @intCast(usize, idx);
            } else {
                panic("must not happen ({})", .{idx});
            }
            const matched_part = rest[1..usize_idx];

            list.addStr(matched_part);
            pos += matched_part.len + 2;
        } else {
            std.debug.panic("Unexpected pattern: pos({}) rest({}) rest[0]({})", .{ pos, rest, rest[0] });
        }
    }

    size.* = pos;
    return list;
}

pub fn parse(input_json: []const u8) *List {
    if (input_json[0] == '[') {
        var size: usize = undefined;
        return parseList(input_json, &size);
    } else {
        panic("Unexpected pattern", .{});
    }
}

fn printIndent(lv: u8) void {
    var i: usize = 0;
    while (i < lv) : (i += 1) {
        _print("  ");
    }
}

fn printNode(node: *Node, lv: u8, pretty: bool) void {
    switch (node.kind) {
        .INT => {
            if (pretty) {
                printIndent(lv + 1);
            }
            _print(node.int);
        },
        .STR => {
            if (pretty) {
                printIndent(lv + 1);
            }
            _print("\"");
            _print(node.getStr());
            _print("\"");
        },
        .LIST => {
            const list: ?*List = node.list;
            if (list) |_list| {
                printList(_list, lv + 1, pretty);
            }
        },
    }
}

fn printList(list: *List, lv: u8, pretty: bool) void {
    printIndent(lv);
    _print("[");
    if (pretty) {
        _print("\n");
    }

    var i: usize = 0;
    while (i < list.size()) : (i += 1) {
        const node = list.get(i);
        if (1 <= i) {
            if (pretty) {
                _print(",\n");
            } else {
                _print(", ");
            }
        }
        printNode(node, lv, pretty);
    }
    if (pretty) {
        _print("\n");
    }

    if (pretty) {
        printIndent(lv);
    }
    _print("]");
}

pub fn print(list: *List) void {
    printList(list, 0, true);
    _print("\n");
}

pub fn printOneLine(list: *List) void {
    printList(list, 0, false);
}
