const std = @import("std");

const builtin = @import("builtin");
const native_os = builtin.os.tag;

const asy = @import("helpers/zig_async/async.zig");
const hlp = @import("helpers/utils.zig");

// Divisions of a nanosecond.
export const ns_per_us: u64 = 1000;
export const ns_per_ms = 1000 * ns_per_us;
export const ns_per_s = 1000 * ns_per_ms;
export const ns_per_min = 60 * ns_per_s;
export const ns_per_hour = 60 * ns_per_min;
export const ns_per_day = 24 * ns_per_hour;
export const ns_per_week = 7 * ns_per_day;

// Divisions of a microsecond.
export const us_per_ms: u64 = 1000;
export const us_per_s = 1000 * us_per_ms;
export const us_per_min = 60 * us_per_s;
export const us_per_hour = 60 * us_per_min;
export const us_per_day = 24 * us_per_hour;
export const us_per_week = 7 * us_per_day;

// Divisions of a millisecond.
export const ms_per_s: u64 = 1000;
export const ms_per_min = 60 * ms_per_s;
export const ms_per_hour = 60 * ms_per_min;
export const ms_per_day = 24 * ms_per_hour;
export const ms_per_week = 7 * ms_per_day;

// Divisions of a second.
export const s_per_min: u64 = 60;
export const s_per_hour = s_per_min * 60;
export const s_per_day = s_per_hour * 24;
export const s_per_week = s_per_day * 7;

export fn zigsleep(ns: u64) void {
    std.Thread.sleep(ns);
}

// std.Thread.sleep(ns) but for ms

export fn sleep_ms(ms: u64) void {
    const s = ms / std.time.ms_per_s;
    const ns = (ms % std.time.ms_per_s) * std.time.ns_per_ms;

    switch (native_os) {
        .linux => {
            const linux = std.os.linux;

            var req: linux.timespec = .{
                .sec = std.math.cast(linux.time_t, s) orelse std.math.maxInt(linux.time_t),
                .nsec = std.math.cast(linux.time_t, ns) orelse std.math.maxInt(linux.time_t),
            };
            var rem: linux.timespec = undefined;

            while (true) {
                switch (linux.E.init(linux.clock_nanosleep(.MONOTONIC, .{ .ABSTIME = false }, &req, &rem))) {
                    .SUCCESS => return,
                    .INTR => {
                        req = rem;
                        continue;
                    },
                    .FAULT,
                    .INVAL,
                    .OPNOTSUPP,
                    => unreachable,
                    else => return,
                }
            }
        },

        .windows => {
            const ms32 = std.math.cast(std.os.windows.DWORD, ms) orelse std.math.maxInt(std.os.windows.DWORD);

            std.os.windows.kernel32.Sleep(ms32);
        },

        else => {
            std.posix.nanosleep(s, ns);
        },
    }
}

export fn allocLoop() ?*asy.Loop {
    return hlp.gpa.create(asy.Loop) catch null;
}

export fn freeLoop(loop: *asy.Loop) void {
    hlp.gpa.destroy(loop);
}

export fn initLoop(loop: *asy.Loop) void {
    loop.init();
}

export fn deinitLoop(loop: *asy.Loop) void {
    loop.deinit();
}

export fn callLoop(loop: *asy.Loop) void {
    loop.call(hlp.gpa) catch {};
}

export fn callLoopSameThread(loop: *asy.Loop) void {
    loop.callSameThread(hlp.gpa);
}

export fn execLoop(loop: *asy.Loop) void {
    loop.exec();
}

export fn pushToLoop(loop: *asy.Loop, ptr: *anyopaque, args: [*c]*anyopaque, len: usize) void {
    loop.add(hlp.gpa, .{
        .ptr = ptr,
        .args = args[0..len],
    }) catch {};
}

export fn asySpawn(ptr: *anyopaque, args: [*c]*anyopaque, len: usize) void {
    asy.Spawn(asy.callFunc, .{
        asy.FuncData{ .ptr = ptr, .args = args[0..len] },
    }) catch {};
}

export fn bitAND(a1: i32, a2: i32) i32 {
    return a1 & a2;
}

export fn bit64AND(a1: i64, a2: i64) i64 {
    return a1 & a2;
}

export fn bitOR(a1: i32, a2: i32) i32 {
    return a1 | a2;
}

export fn bit64OR(a1: i64, a2: i64) i64 {
    return a1 | a2;
}

export fn bitXOR(a1: i32, a2: i32) i32 {
    return a1 ^ a2;
}

export fn bit64XOR(a1: i64, a2: i64) i64 {
    return a1 ^ a2;
}

export fn bitNOT(a1: i32) i32 {
    return ~a1;
}

export fn bit64NOT(a1: i64) i64 {
    return ~a1;
}

export fn bitLSH(a1: i32, a2: i32) i32 {
    return a1 << std.math.lossyCast(u5, a2);
}

export fn bit64LSH(a1: i64, a2: i64) i64 {
    return a1 << std.math.lossyCast(u6, a2);
}

export fn bitRSH(a1: i32, a2: i32) i32 {
    return a1 >> std.math.lossyCast(u5, a2);
}

export fn bit64RSH(a1: i64, a2: i64) i64 {
    return a1 >> std.math.lossyCast(u6, a2);
}
