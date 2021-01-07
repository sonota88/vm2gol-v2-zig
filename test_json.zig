// -*- mode: javascript; js-indent-level: 4 -*-

const std = @import("std");
const utils = @import("lib/utils.zig");
const json = @import("lib/json.zig");
const types = @import("lib/types.zig");
const NodeList = types.NodeList;
const Node = types.Node;

pub fn newlist() !*NodeList {
    return try NodeList.init();
}

fn make_test_json_data_1() !*NodeList {
    var list = try newlist();
    return list;
}

fn make_test_json_data_2() !*NodeList {
    var list = try newlist();
    try list.addInt(1);
    return list;
}

fn make_test_json_data_3() !*NodeList {
    var list = try newlist();
    try list.addStr("fdsa");
    return list;
}

fn make_test_json_data_4() !*NodeList {
    var list = try newlist();
    try list.addInt(-123);
    try list.addStr("fdsa");
    return list;
}

fn make_test_json_data_5() !*NodeList {
    var list = try newlist();

    const inner_list = try newlist();
    try list.addList(inner_list);

    return list;
}

fn make_test_json_data_6() !*NodeList {
    var list = try newlist();

    try list.addInt(1);
    try list.addStr("a");

    {
        const inner_list = try newlist();
        try inner_list.addInt(2);
        try inner_list.addStr("b");
        try list.addList(inner_list);
    }

    try list.addInt(3);
    try list.addStr("c");

    return list;
}

pub fn main() !void {
    // const tree = try make_test_json_data_1();
    // const tree = try make_test_json_data_2();
    // const tree = try make_test_json_data_3();
    // const tree = try make_test_json_data_4();
    // const tree = try make_test_json_data_5();
    // const tree = try make_test_json_data_6();
    var buf: [1024]u8 = undefined;
    const input_json = utils.readStdinAll(&buf);

    const tree = json.parse(input_json);
    json.printAsJson(tree);
}
