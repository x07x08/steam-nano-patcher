const std = @import("std");

const ldr = @import("loader_common.zig");
const asy = @import("helpers/zig_async/async.zig");

pub fn main() void {
    ldr.loadModules() catch |err| {
        const sl = @src();

        std.log.err("{s}->{s} : {}", .{ sl.file, sl.fn_name, err });

        return;
    };

    var mainLoop: asy.Loop = .{};
    mainLoop.data.funcs = std.ArrayList(asy.LoopFuncData){
        .allocator = undefined,
        .capacity = 0,
        .items = &[_]asy.LoopFuncData{},
    };

    mainLoop.callSameThread();
}
