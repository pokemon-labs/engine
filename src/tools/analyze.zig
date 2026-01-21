// Forked from tigerbeetle/tigerbeetle's Apache-2 licensed src/copyhound.zig.
// The full license can be found at https://github.com/tigerbeetle/tigerbeetle/blob/main/LICENSE

const std = @import("std");

const Tool = union(enum) { copies: usize, sizes };

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    var tool: Tool = undefined;
    var err = std.Io.File.stderr().writer(init.io, &.{});
    if (args.len < 2) usageAndExit(&err.interface, args[0]);

    if (std.mem.eql(u8, args[1], "copies")) {
        if (args.len > 2 and args.len != 3) {
            errorAndExit(&err.interface, "copies only expects one optional argument", "", args[0]);
        }
        const threshold = if (args.len == 3) try std.fmt.parseUnsigned(usize, args[2], 10) else 8;
        tool = .{ .copies = threshold };
    } else if (std.mem.eql(u8, args[1], "sizes")) {
        if (args.len != 2) {
            errorAndExit(&err.interface, "sizes does not take any further arguments", "", args[0]);
        }
        tool = .sizes;
    } else {
        usageAndExit(&err.interface, args[0]);
    }

    const in_buf = try allocator.alloc(u8, 1024 * 1024);
    const out_buf = try allocator.alloc(u8, 4096);
    const function_buf = try allocator.alloc(u8, 4096);

    var stdin = std.Io.File.stdin().reader(init.io, in_buf);
    var in = &stdin.interface;

    var stdout = std.Io.File.stdout().writer(init.io, out_buf);
    var out = &stdout.interface;

    var current_function: ?[]const u8 = null;
    var current_function_size: usize = 0;
    while (try (in.takeDelimiterExclusive('\n') catch |e| switch (e) {
        error.EndOfStream => null,
        else => e,
    })) |line| {
        in.toss(1);
        if (std.mem.startsWith(u8, line, "define ")) {
            current_function = extractFunctionName(line, function_buf) orelse
                errorAndExit(&err.interface, "can't define parse line=", line, args[0]);
            continue;
        }

        if (current_function) |function| {
            if (std.mem.eql(u8, line, "}")) {
                if (tool == .sizes) {
                    try out.print("{s} {}\n", .{ function, current_function_size });
                }
                current_function = null;
                current_function_size = 0;
                continue;
            }
            current_function_size += 1;
            if (tool == .copies) {
                if (cut(line, "@llvm.memmove")) |c| {
                    const size = extractMemcpySize(c[1]) orelse
                        errorAndExit(&err.interface, "can't memcpy parse line=", line, args[0]);
                    if (size > tool.copies) {
                        try out.print("{s}: {} bytes memcpy\n", .{ function, size });
                    }
                }
            }
        }
    }
    try out.flush();
}

fn cut(haystack: []const u8, needle: []const u8) ?struct { []const u8, []const u8 } {
    const index = std.mem.indexOf(u8, haystack, needle) orelse return null;
    return .{ haystack[0..index], haystack[index + needle.len ..] };
}

fn extractFunctionName(define: []const u8, buf: []u8) ?[]const u8 {
    const function_name = (cut(define, "@") orelse return null)[1];
    var buf_count: usize = 0;
    var level: u32 = 0;
    for (function_name) |c| {
        switch (c) {
            '(' => level += 1,
            ')' => level -= 1,
            '"' => {},
            else => {
                if (level > 0) continue;
                if (c == ' ') return buf[0..buf_count];
                if (buf_count == buf.len) return null;
                buf[buf_count] = c;
                buf_count += 1;
            },
        }
    } else return null;
}

fn extractMemcpySize(memcpy_call: []const u8) ?u32 {
    const call_args = (cut(memcpy_call, "(") orelse return null)[1];
    var level: u32 = 0;
    var arg_count: u32 = 0;

    const args_after_size = for (call_args, 0..) |c, i| {
        switch (c) {
            '(' => level += 1,
            ')' => level -= 1,
            ',' => {
                if (level > 0) continue;
                arg_count += 1;
                if (!std.mem.startsWith(u8, call_args[i..], ", ")) return null;
                if (arg_count == 2) break call_args[i + 2 ..];
            },
            else => {},
        }
    } else return null;

    const size_arg = (cut(args_after_size, ",") orelse return null)[0];

    const size_value = (cut(size_arg, " ") orelse return null)[1];

    // Runtime-known memcpy size, assume that's OK.
    if (std.mem.startsWith(u8, size_value, "%")) return 0;

    return std.fmt.parseInt(u32, size_value, 10) catch null;
}

fn errorAndExit(err: *std.Io.Writer, msg: []const u8, arg: []const u8, cmd: []const u8) noreturn {
    err.print("{s}{s}\n", .{ msg, arg }) catch {};
    usageAndExit(err, cmd);
}

fn usageAndExit(err: *std.Io.Writer, cmd: []const u8) noreturn {
    err.print("Usage: {s} <copies|sizes>\n", .{cmd}) catch {};
    std.process.exit(1);
}
