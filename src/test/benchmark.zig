const pkmn = @import("pkmn");
const std = @import("std");

const showdown = pkmn.options.showdown;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    var err = std.Io.File.stderr().writer(init.io, &.{});

    if (args.len < 3 or args.len > 5) usageAndExit(&err.interface, args[0]);

    const gen = std.fmt.parseUnsigned(u8, args[1], 10) catch
        errorAndExit(&err.interface, "gen", args[1], args[0]);
    if (gen < 1 or gen > 9) errorAndExit(&err.interface, "gen", args[1], args[0]);

    var arg: []u8 = @constCast(args[2]);
    var warmup: ?usize = null;
    const index = std.mem.indexOfScalar(u8, arg, '/');
    if (index) |i| {
        warmup = std.fmt.parseUnsigned(usize, arg[0..i], 10) catch
            errorAndExit(&err.interface, "warmup", args[2], args[0]);
        if (warmup.? == 0) errorAndExit(&err.interface, "warmup", args[2], args[0]);
        arg = arg[(i + 1)..arg.len];
    }
    const battles = std.fmt.parseUnsigned(usize, arg, 10) catch
        errorAndExit(&err.interface, "battles", args[2], args[0]);
    if (battles == 0) errorAndExit(&err.interface, "battles", args[2], args[0]);

    const seed = if (args.len > 3) std.fmt.parseUnsigned(u64, args[3], 0) catch
        errorAndExit(&err.interface, "seed", args[3], args[0]) else seed: {
        var secret: [std.Random.DefaultCsprng.secret_seed_length]u8 = undefined;
        init.io.random(&secret);
        var csprng = std.Random.DefaultCsprng.init(secret);
        const random = csprng.random();
        break :seed random.int(usize);
    };

    try benchmark(init.io, gen, seed, battles, warmup);
}

pub fn benchmark(io: std.Io, gen: u8, seed: u64, battles: usize, warmup: ?usize) !void {
    std.debug.assert(gen >= 1 and gen <= 9);

    var choices: [pkmn.CHOICES_SIZE]pkmn.Choice = undefined;
    var random = pkmn.PSRNG.init(seed);

    var time: u64 = 0;
    var turns: usize = 0;

    var i: usize = 0;
    const w = warmup orelse 0;
    const num = battles + w;
    while (i < num) : (i += 1) {
        if (warmup != null and i == w) random = pkmn.PSRNG.init(seed);

        var battle = switch (gen) {
            1 => pkmn.gen1.helpers.Battle.random(&random, .{
                .cleric = showdown,
                .block = showdown,
            }),
            else => unreachable,
        };
        var options = switch (gen) {
            1 => pkmn.gen1.NULL,
            else => unreachable,
        };

        std.debug.assert(!showdown or battle.side(.P1).get(1).hp > 0);
        std.debug.assert(!showdown or battle.side(.P2).get(1).hp > 0);

        var c1 = pkmn.Choice{};
        var c2 = pkmn.Choice{};

        var p1 = pkmn.PSRNG.init(random.newSeed());
        var p2 = pkmn.PSRNG.init(random.newSeed());

        var timer = std.Io.Clock.awake.now(io);

        var result = try battle.update(c1, c2, &options);
        while (result.type == .None) : (result = try battle.update(c1, c2, &options)) {
            var n = battle.choices(.P1, result.p1, &choices);
            if (n == 0) break;
            c1 = choices[p1.range(u8, 0, n)];
            n = battle.choices(.P2, result.p2, &choices);
            if (n == 0) break;
            c2 = choices[p2.range(u8, 0, n)];
        }

        const t: u64 = @intCast(timer.untilNow(io, .awake).toNanoseconds());
        std.debug.assert(!showdown or result.type != .Error);

        if (i >= w) {
            time += t;
            turns += battle.turn;
        }
    }

    var out = std.Io.File.stdout().writer(io, &.{});
    try out.interface.print("{d},{d},{d}\n", .{ time, turns, random.src.seed });
}

fn errorAndExit(err: *std.Io.Writer, msg: []const u8, arg: []const u8, cmd: []const u8) noreturn {
    err.print("Invalid {s}: {s}\n", .{ msg, arg }) catch {};
    usageAndExit(err, cmd);
}

fn usageAndExit(err: *std.Io.Writer, cmd: []const u8) noreturn {
    err.print("Usage: {s} <GEN> <(WARMUP/)BATTLES> <SEED?>\n", .{cmd}) catch {};
    std.process.exit(1);
}
