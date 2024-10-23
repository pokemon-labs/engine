const pkmn = @import("pkmn.zig");
const std = @import("std");

const assert = std.debug.assert;

const Enum = if (@hasField(std.builtin.Type, "enum")) .@"enum" else .Enum;

const js = struct {
    extern "js" fn log(ptr: [*]const u8, len: usize) void;
    extern "js" fn panic(ptr: [*]const u8, len: usize) noreturn;
};

pub const std_options: std.Options = .{
    .logFn = logFn,
    .log_level = .debug,
};

fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime message_level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    var buf: [500]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, level_txt ++ prefix2 ++ format, args) catch l: {
        buf[buf.len - 3 ..][0..3].* = "...".*;
        break :l &buf;
    };
    js.log(line.ptr, line.len);
}

pub fn panic(msg: []const u8, st: ?*std.builtin.StackTrace, addr: ?usize) noreturn {
    _ = st;
    _ = addr;
    std.log.err("panic: {s}", .{msg});
    @trap();
}

export const SHOWDOWN = pkmn.options.showdown;
export const LOG = pkmn.options.log;
export const CHANCE = pkmn.options.chance;
export const CALC = pkmn.options.calc;

export const GEN1_CHOICES_SIZE =
    std.math.ceilPowerOfTwo(u32, @as(u32, @intCast(pkmn.gen1.CHOICES_SIZE))) catch unreachable;
export const GEN1_LOGS_SIZE =
    std.math.ceilPowerOfTwo(u32, @as(u32, @intCast(pkmn.gen1.LOGS_SIZE))) catch unreachable;

export fn GEN1_update(
    battle: *pkmn.gen1.Battle(pkmn.gen1.PRNG),
    c1: pkmn.Choice,
    c2: pkmn.Choice,
    options: ?[*]u8,
) pkmn.Result {
    std.log.err("hello: {}", .{c1});
    return (if (options) |o| result: {
        const buf = @as([*]u8, @ptrCast(o))[0..pkmn.gen1.LOGS_SIZE];
        var stream: pkmn.protocol.ByteStream = .{ .buffer = buf };
        // TODO: extract out
        var opts = pkmn.battle.options(
            pkmn.protocol.FixedLog{ .writer = stream.writer() },
            pkmn.gen1.chance.NULL,
            pkmn.gen1.calc.NULL,
        );
        break :result battle.update(c1, c2, &opts);
    } else battle.update(c1, c2, &pkmn.gen1.NULL)) catch unreachable;
}

export fn GEN1_choices(
    battle: *pkmn.gen1.Battle(pkmn.gen1.PRNG),
    player: u8,
    request: u8,
    buf: [*]u8,
) u8 {
    assert(player <= @field(@typeInfo(pkmn.Player), @tagName(Enum)).fields.len);
    assert(request <= @field(@typeInfo(pkmn.Choice.Type), @tagName(Enum)).fields.len);

    const len = GEN1_CHOICES_SIZE;
    return battle.choices(@enumFromInt(player), @enumFromInt(request), @ptrCast(buf[0..len]));
}
