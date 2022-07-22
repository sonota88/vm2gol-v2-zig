const std = @import("std");
const panic = std.debug.panic;
const allocator = std.heap.page_allocator;

const utils = @import("utils.zig");
const puts_e = utils.puts_e;
const putskv_e = utils.putskv_e;

pub const NodeKind = enum {
    INT,
    STR,
    LIST,
};

pub const Node = struct {
    kind: NodeKind,
    int: ?i32,
    str: [64]u8,
    list: ?*List,

    const Self = @This();

    pub fn init() *Self {
        var obj = allocator.create(Self) catch {
            panic("Failed to allocate", .{});
        };
        obj.int = undefined;
        obj.str[0] = 0;
        return obj;
    }

    pub fn initInt(n: i32) *Self {
        const node = Self.init();
        node.kind = NodeKind.INT;
        node.int = n;
        return node;
    }

    pub fn initStr(str: []const u8) *Self {
        const node = Self.init();
        node.kind = NodeKind.STR;
        utils.strcpy(&node.str, str);
        return node;
    }

    pub fn initList(list: *List) *Self {
        const node = Self.init();
        node.kind = NodeKind.LIST;
        node.list = list;
        return node;
    }

    pub fn getInt(self: *Self) i32 {
        if (self.kind != NodeKind.INT) {
            panic("Invalid node kind", .{});
        }

        if (self.int) |int| {
            return int;
        } else {
            panic("must not happen", .{});
        }
    }

    pub fn getStr(self: *Self) []const u8 {
        if (self.kind != NodeKind.STR) {
            panic("Invalid node kind", .{});
        }

        const len = utils.strlen(&self.str);
        return self.str[0..len];
    }

    pub fn getList(self: *Self) *List {
        if (self.kind != NodeKind.LIST) {
            panic("Invalid node kind", .{});
        }

        if (self.list) |_list| {
            return _list;
        }
        panic("must not happen", .{});
    }

    pub fn kindEq(self: *Self, kind: NodeKind) bool {
        return self.kind == kind;
    }
};

pub const List = struct {
    nodes: [64]*Node,
    len: usize,

    const Self = @This();

    pub fn init() *Self {
        var obj = allocator.create(List) catch |err| {
            panic("Failed to allocate ({})", .{err});
        };
        obj.len = 0;
        return obj;
    }

    pub fn empty() *Self {
        return Self.init();
    }

    pub fn size(self: *Self) usize {
        return self.len;
    }

    pub fn add(self: *Self, node: *Node) void {
        self.nodes[self.len] = node;
        self.len += 1;
    }

    pub fn addInt(self: *Self, n: i32) void {
        const node = Node.initInt(n);
        self.add(node);
    }

    pub fn addStr(self: *Self, str: []const u8) void {
        const node = Node.initStr(str);
        self.add(node);
    }

    pub fn addList(self: *Self, list: *List) void {
        const node = Node.initList(list);
        self.add(node);
    }

    pub fn addListAll(self: *Self, list: *List) void {
        var i: usize = 0;
        while (i < list.len) : (i += 1) {
            self.add(list.get(i));
        }
    }

    pub fn get(self: *Self, index: usize) *Node {
        return self.nodes[index];
    }
};

// --------------------------------

const Name = struct {
    str: [16]u8,

    const Self = @This();

    pub fn init() *Self {
        var obj = allocator.create(Self) catch {
            panic("Failed to allocate", .{});
        };
        return obj;
    }

    pub fn initWithStr(str: []const u8) *Self {
        var obj = Name.init();
        utils.strcpy(&obj.str, str);
        return obj;
    }

    pub fn getStr(self: *Self) []const u8 {
        const len = utils.strlen(self.str[0..]);
        return self.str[0..len];
    }
};

pub const Names = struct {
    strs: [8]*Name = []*Name{undefined},
    len: usize,

    const Self = @This();

    pub fn init() *Self {
        var obj = allocator.create(Self) catch {
            panic("Failed to allocate", .{});
        };
        obj.len = 0;

        return obj;
    }

    pub fn empty() *Self {
        return Self.init();
    }

    pub fn get(self: *Self, i: usize) *Name {
        return self.strs[i];
    }

    pub fn add(self: *Self, str: []const u8) void {
        const name: *Name = Name.initWithStr(str);
        self.strs[self.len] = name;

        self.len += 1;
    }

    pub fn indexOf(self: *Self, str: []const u8) i32 {
        var i: usize = 0;
        while (i < self.len) : (i += 1) {
            if (utils.strEq(self.get(i).getStr(), str)) {
                return @intCast(i32, i);
            }
        }
        return -1;
    }
};
