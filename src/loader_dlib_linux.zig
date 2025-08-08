const std = @import("std");

const bshr = @import("build_shared.zig");

const asy = @import("helpers/zig_async/async.zig");

const ldr = @import("loader_common.zig");

const c = @cImport({
    @cDefine("_GNU_SOURCE", "1");
    @cInclude("dlfcn.h");
    @cInclude("stdlib.h");
});

fn isChildProcess(argc: usize, argv: [*c][*c]u8) bool {
    for (0..argc) |index| {
        const arg: []const u8 = std.mem.sliceTo(argv[index], 0);

        if (std.mem.eql(u8, arg, "-child-update-ui") or std.mem.eql(u8, arg, "-child-update-ui-socket")) {
            return true;
        }
    }

    return false;
}

export fn __libc_start_main(
    main: *const fn (_: c_int, _: [*c][*c]u8, _: [*c][*c]u8) callconv(.c) c_int,
    argc: c_int,
    argv: [*c][*c]u8,
    init: *const fn (_: c_int, _: [*c][*c]u8, _: [*c][*c]u8) callconv(.c) c_int,
    fini: *const fn () callconv(.c) void,
    rtld_fini: *const fn () callconv(.c) void,
    stack_end: *anyopaque,
) c_int {
    const orig: *const @TypeOf(__libc_start_main) = @ptrCast(std.c.dlsym(c.RTLD_NEXT, "__libc_start_main").?);

    blk: {
        const currentProc = std.posix.getenv("SNP_CURRENT_PROC") orelse break :blk;
        const searchProc = std.posix.getenv("SNP_SEARCH_PROC") orelse break :blk;

        if (std.mem.eql(u8, searchProc, currentProc) and !isChildProcess(@intCast(argc), argv)) {
            ldr.loadModules() catch |err| {
                const sl = @src();

                std.log.err("{s}->{s} : {}", .{ sl.file, sl.fn_name, err });
            };
        }

        // unsetenv produces errors
        _ = c.setenv("SNP_SEARCH_PROC", "", 1);
    }

    return orig(main, argc, argv, init, fini, rtld_fini, stack_end);
}
