const std = @import("std");

const asy = @import("helpers/zig_async/async.zig");
const hlp = @import("helpers/utils.zig");

const ldr = @import("loader_common.zig");

pub fn main() void {
    ldr.loadModules() catch |err| {
        const sl = @src();

        std.log.err("{s}->{s} : {}", .{ sl.file, sl.fn_name, err });

        return;
    };

    var mainLoop: asy.Loop = .{};
    mainLoop.data.funcs = std.ArrayList(asy.LoopFuncData).empty;

    mainLoop.callSameThread(hlp.gpa);
}
