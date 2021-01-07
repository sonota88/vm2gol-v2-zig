// -*- mode: javascript; js-indent-level: 4 -*-

const std = @import("std");
const panic = std.debug.panic;

const utils = @import("utils.zig");
const print = utils.print;
const puts_e = utils.puts_e;

const types = @import("types.zig");
const NodeKind = types.NodeKind;
const Node = types.Node;
const NodeList = types.NodeList;

const allocator = std.heap.page_allocator;

const ParseRetval = struct {
    list: *NodeList,
    size: usize,

    fn init(list: *NodeList, size: usize) *ParseRetval {
        var obj = allocator.create(ParseRetval) catch |err| {
            panic("Failed to allocate ({})", .{err});
        };
        obj.list = list;
        obj.size = size;
        return obj;
    }
};

pub fn parseList(input_json: []const u8) *ParseRetval {
    const list = NodeList.init();
    var pos: usize = 1;
    var rest: []const u8 = undefined;

    while (pos < input_json.len) {
        rest = input_json[pos..];

        if (rest[0] == ']') {
            pos += 1;
            break;
        } else if (rest[0] == '[') {
            const retval = parseList(rest);
            list.addList(retval.list);
            pos += retval.size;
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

    return ParseRetval.init(list, pos);
}

pub fn parse(input_json: []const u8) *NodeList {
    if (input_json[0] == '[') {
        const retval = parseList(input_json);
        return retval.list;
    } else {
        panic("Unexpected pattern", .{});
    }
}

fn printIndent(lv: u8) void {
    var i: usize = 0;
    while (i < lv) : (i += 1) {
        print("  ");
    }
}

fn printNodeAsJson(node: *Node, lv: u8) void {
    switch (node.kind) {
        .INT => {
            printIndent(lv + 1);
            print(node.int);
        },
        .STR => {
            printIndent(lv + 1);
            print("\"");
            print(node.getStr());
            print("\"");
        },
        .LIST => {
            const list: ?*NodeList = node.list;
            if (list) |_list| {
                printNodeListAsJson(_list, lv + 1);
            }
        },
    }
}

fn printNodeListAsJson(list: *NodeList, lv: u8) void {
    printIndent(lv);
    print("[\n");

    var i: usize = 0;
    while (i < list.size()) : (i += 1) {
        const node = list.get(i);
        if (1 <= i) {
            print(",");
            print("\n");
        }
        printNodeAsJson(node, lv);
    }
    print("\n");

    printIndent(lv);
    print("]");
}

pub fn printAsJson(list: *NodeList) void {
    printNodeListAsJson(list, 0);
    print("\n");
}
