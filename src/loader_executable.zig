const std = @import("std");

const ldr = @import("loader_common.zig");
const asy = @import("helpers/zig_async/async.zig");

pub fn main() void {
    ldr.loadModules() catch |err| {
        std.log.err("{}", .{err});

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
