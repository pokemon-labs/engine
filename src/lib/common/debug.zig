const std = @import("std");

const debug = std.debug;
const io = std.io;

pub fn print(value: anytype) void {
    debug.lockStdErr();
    defer debug.unlockStdErr();
    const stderr = io.getStdErr().writer();

    nosuspend {
        stderr.writeAll("\x1b[41m") catch return;
        if (@TypeOf(@src()) == @TypeOf(value)) {
            stderr.print("{s} ({s}:{d}:{d})", .{
                value.fn_name,
                value.file,
                value.line,
                value.column,
            }) catch return;
        } else {
            switch (@typeInfo(@TypeOf(value))) {
                .@"struct" => |info| {
                    if (info.is_tuple) {
                        inline for (info.fields, 0..) |f, i| {
                            inspect(@field(value, f.name));
                            if (i < info.fields.len - 1) stderr.writeAll(" ") catch return;
                        }
                    } else {
                        inspect(value);
                    }
                },
                else => inspect(value),
            }
        }
        stderr.writeAll("\x1b[K\x1b[0m\n") catch return;
    }
}

fn inspect(value: anytype) void {
    const stderr = io.getStdErr().writer();

    nosuspend {
        const err = "Unable to format type '" ++ @typeName(@TypeOf(value)) ++ "'";
        switch (@typeInfo(@TypeOf(value))) {
            .array => |info| {
                if (info.child == u8) return stderr.print("{s}", .{value}) catch return;
                @compileError(err);
            },
            .pointer => |ptr_info| switch (ptr_info.size) {
                .one => switch (@typeInfo(ptr_info.child)) {
                    .array => |info| {
                        if (info.child == u8) return stderr.print("{s}", .{value}) catch return;
                        @compileError(err);
                    },
                    .@"enum", .@"union", .@"struct" => return inspect(value.*),
                    else => @compileError(err),
                },
                .many, .c => {
                    if (ptr_info.sentinel) |_| return inspect(std.mem.span(value));
                    if (ptr_info.child == u8) {
                        return stderr.print("{s}", .{std.mem.span(value)}) catch return;
                    }
                    @compileError(err);
                },
                .slice => {
                    if (ptr_info.child == u8) return stderr.print("{s}", .{value}) catch return;
                    @compileError(err);
                },
            },
            .optional => stderr.print("{?}", .{value}) catch return,
            else => stderr.print("{}", .{value}) catch return,
        }
    }
}

const showdown = @import("./options.zig").showdown;
const Result = @import("./data.zig").Result;
const Choice = @import("./data.zig").Choice;

pub fn dump(gen: u8, battle: anytype, frame: ?struct { Result, Choice, Choice }) void {
    const file = std.fs.cwd().createFile("logs/dump.bin", .{}) catch return;
    defer file.close();
    var w = file.writer();
    w.writeByte(@intFromBool(showdown)) catch return;
    w.writeByte(gen) catch return;
    w.writeInt(i16, 0, .little) catch return;
    w.writeInt(i32, 0, .little) catch return;
    w.writeStruct(battle) catch return;
    w.writeStruct(battle) catch return;
    if (frame) |f| {
        w.writeStruct(f[0]) catch return;
        w.writeStruct(f[1]) catch return;
        w.writeStruct(f[2]) catch return;
    }
}
