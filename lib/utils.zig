const std = @import("std");
const panic = std.debug.panic;

fn print_to(file: std.fs.File, val: anytype) void {
    file.writer().print("{any}", .{val}) catch |err| {
        panic("error ({})", .{err});
    };
}

fn print_to_s(file: std.fs.File, s: []const u8) void {
    file.writer().print("{s}", .{s}) catch |err| {
        panic("error ({})", .{err});
    };
}

fn print_to_i(file: std.fs.File, n: i32) void {
    file.writer().print("{}", .{n}) catch |err| {
        panic("error ({})", .{err});
    };
}

pub fn print(val: anytype) void {
    print_to(std.io.getStdOut(), val);
}

pub fn print_s(s: []const u8) void {
    print_to_s(std.io.getStdOut(), s);
}

pub fn print_i(n: i32) void {
    print_to_i(std.io.getStdOut(), n);
}

pub fn puts(val: anytype) void {
    print(val);
    print_s("\n");
}

pub fn puts_s(s: []const u8) void {
    print_s(s);
    print_s("\n");
}

pub fn puts_fmt(comptime format: []const u8, args: anytype) void {
    std.io.getStdOut().writer().print(format, args) catch |err| {
        panic("error ({})", .{err});
    };
    print_s("\n");
}

pub fn print_e(val: anytype) void {
    print_to(std.io.getStdErr(), val);
}

pub fn puts_e(val: anytype) void {
    print_e(val);
    print_e("\n");
}

pub fn putskv_e(key: []const u8, val: anytype) void {
    print_e(key);
    print_e(" (");
    print_e(val);
    print_e(")\n");
}

// Print function name for debug
pub fn puts_fn(fnName: []const u8) void {
    if (!true) {
        print_e("    |-->> ");
        print_e(fnName);
        print_e("\n");
    }
}

pub fn readStdinAll(buf: [*]u8) []const u8 {
    const size_max = 20000;
    var i: usize = 0;
    const stdin_stream = std.io.getStdIn().reader();

    while (true) {
        const byte = stdin_stream.readByte() catch |err| switch (err) {
            error.EndOfStream => {
                break;
            },
            else => |e| {
                panic("error ({})", .{e});
            },
        };

        buf[i] = byte;
        i += 1;
        if (size_max <= i) {
            panic("error: Too large input", .{});
        }
    }

    return buf[0..i];
}

pub fn strlen(chars: []const u8) usize {
    var i: usize = 0;
    while (i < chars.len) : (i += 1) {
        if (chars[i] == 0) {
            return i;
        }
    }

    return chars.len;
}

pub fn strcpy(dest: [*]u8, src: []const u8) void {
    var i: usize = 0;
    while (true) : (i += 1) {
        dest[i] = src[i];
        if (src[i] == 0) {
            break;
        }
        if (strlen(src) - 1 <= i) {
            dest[i + 1] = 0;
            break;
        }
    }
}

pub fn indexOf(str: []const u8, ch: u8, from: usize) i32 {
    var i = from;
    while (true) : (i += 1) {
        if (str.len <= i) {
            return -1;
        }
        if (str[i] == 0) {
            return -1;
        }
        if (str[i] == ch) {
            break;
        }
    }
    return @intCast(i);
}

pub fn matchAnyChar(chars: []const u8, ch: u8) bool {
    return 0 <= indexOf(chars, ch, 0);
}

pub fn substring(dest: [*]u8, src: []const u8, index_start: usize, index_end: usize) void {
    var i: usize = 0;
    var size = index_end - index_start;
    while (i < size) : (i += 1) {
        if (src[index_start + i] == 0) {
            size = i;
            break;
        }
        dest[i] = src[index_start + i];
    }
    dest[size] = 0;
}

pub fn strncmp(s1: []const u8, s2: [*:0]const u8, len: usize) bool {
    var i: usize = 0;
    while (i < len) : (i += 1) {
        if (s1[i] != s2[i]) {
            return false;
        }
    }

    return true;
}

pub fn strEq(s1: []const u8, s2: []const u8) bool {
    if (strlen(s1) != strlen(s2)) {
        return false;
    }
    const len = strlen(s1);

    var i: usize = 0;
    while (i < len) : (i += 1) {
        if (s1[i] != s2[i]) {
            return false;
        }
    }

    return true;
}

pub fn isNumeric(ch: u8) bool {
    return '0' <= ch and ch <= '9';
}

pub fn indexOfNonNumeric(str: []const u8, start_index: usize) usize {
    var i: usize = start_index;
    while (i < str.len) : (i += 1) {
        if (!isNumeric(str[i])) {
            break;
        }
    }
    return i;
}

pub fn parseInt(str: []const u8) i32 {
    return std.fmt.parseInt(i32, str, 10) catch {
        panic("Failed to parse ({s})", .{str});
    };
}

pub fn bufPrint(buf: []u8, comptime fmt: []const u8, args: anytype) []u8 {
    return std.fmt.bufPrint(buf, fmt, args) catch |err| {
        panic("err ({})", .{err});
    };
}
