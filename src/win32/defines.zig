const std = @import("std");
const winAPI = std.os.windows;

pub const DLL_PROCESS_ATTACH: winAPI.DWORD = 1;
pub const DLL_PROCESS_DETACH: winAPI.DWORD = 0;
pub const DLL_THREAD_ATTACH: winAPI.DWORD = 2;
pub const DLL_THREAD_DETACH: winAPI.DWORD = 3;

pub extern "c" fn MessageBoxA(HWND: ?winAPI.HWND, lpText: ?winAPI.LPCSTR, lpCaption: ?winAPI.LPCSTR, uType: winAPI.UINT) callconv(.winapi) winAPI.INT;
pub extern "c" fn AllocConsole() callconv(.winapi) winAPI.BOOL;
pub extern "c" fn FreeLibraryAndExitThread(hLibModule: *anyopaque, dwExitCode: winAPI.DWORD) callconv(.winapi) void;

pub fn MessageBoxA_Util(
    allocator: std.mem.Allocator,
    comptime textFmt: []const u8,
    textArgs: anytype,
    comptime captionFmt: []const u8,
    captionArgs: anytype,
    code: c_uint,
) !void {
    const textBuf = try std.fmt.allocPrintSentinel(allocator, textFmt, textArgs, 0);
    const captionBuf = try std.fmt.allocPrintSentinel(allocator, captionFmt, captionArgs, 0);

    _ = MessageBoxA(null, textBuf, captionBuf, code);

    allocator.free(textBuf);
    allocator.free(captionBuf);
}
