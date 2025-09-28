const std = @import("std");

const bshr = @import("build_shared.zig");

const winDefs = @import("win32/defines.zig");
const winAPI = std.os.windows;

const asy = @import("helpers/zig_async/async.zig");

const ldr = @import("loader_common.zig");

var textBuf: [64:0]u8 = .{0} ** 64;
var allocCfg = std.heap.FixedBufferAllocator.init(&textBuf);
const bufAlloc = allocCfg.allocator();

pub fn DllMain(
    hinstDLL: *anyopaque,
    dwReason: winAPI.DWORD,
    lpReserved: winAPI.LPVOID,
) callconv(.winapi) winAPI.BOOL {
    _ = lpReserved;

    if (dwReason == winDefs.DLL_PROCESS_ATTACH) {
        asy.Spawn(winInit, .{hinstDLL}) catch unreachable;
    }

    return winAPI.TRUE;
}

pub fn winInit(_: *anyopaque) void {
    ldr.loadModules() catch |err| {
        winDefs.MessageBoxA_Util(
            bufAlloc,
            "winInit->loadModules : {}",
            .{err},
            "{s}",
            .{bshr.windowName},
            0x10,
        ) catch unreachable;

        return;
    };

    //asy.Spawn(winDefs.FreeLibraryAndExitThread, .{ hinstDLL, 0 }) catch unreachable;
}
