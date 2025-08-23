const std = @import("std");

fn spawn_call(fun: anytype, args: anytype) void {
    _ = @call(.auto, fun, args);
}

/// Async task without return
pub fn Spawn(fun: anytype, args: anytype) !void {
    var thread = try std.Thread.spawn(.{}, spawn_call, .{ fun, args });

    thread.detach();
}

fn task_call(fun: anytype, args: anytype, then_fun: anytype, then_args: anytype) void {
    const ret = @call(.auto, fun, args);

    _ = @call(.auto, then_fun, .{ret} ++ then_args);
}

/// Async task with callback (`fn (ret: <fun return type>, then_args...) void`)
pub fn Task(fun: anytype, args: anytype, then_fun: anytype, then_args: anytype) !void {
    var thread = try std.Thread.spawn(.{}, task_call, .{ fun, args, then_fun, then_args });

    thread.detach();
}

fn waitFunc(db: *DebounceData, fun: anytype) void {
    while (true) {
        db.wait.timedWait(db.timeNs) catch {
            break;
        };

        db.wait.reset();
    }

    _ = @call(.auto, fun, .{});

    db.spawned = false;
}

pub const DebounceData = struct {
    timeNs: u64,
    spawned: bool = false,
    wait: std.Thread.ResetEvent = .{},
};

pub fn Debouncer(timeNs: u64, td: *const fn () void) type {
    return struct {
        data: DebounceData = .{ .timeNs = timeNs },
        fun: @TypeOf(td) = td,

        const Self = @This();

        pub fn call(self: *Self) !void {
            if (!self.data.spawned) {
                self.data.spawned = true;

                try Spawn(waitFunc, .{ &self.data, self.fun });
            } else {
                self.data.wait.set();
            }
        }
    };
}

fn tickFunc(td: *TickData, fun: anytype) void {
    while (true) {
        if (((td.terminate != null) and
            (td.terminate.?.* == true)) or
            (td.forceTerminate == true))
        {
            td.forceTerminate = false;

            break;
        }

        td.wait.timedWait(td.timeNs) catch {};

        _ = @call(.auto, fun, .{});
    }
}

pub const TickData = struct {
    timeNs: u64,
    forceTerminate: bool = false,
    wait: std.Thread.ResetEvent = .{},
    terminate: ?*bool = null,
};

pub fn Ticker(timeNs: u64, td: *const fn () void) type {
    return struct {
        data: TickData = .{ .timeNs = timeNs },
        fun: @TypeOf(td) = td,

        const Self = @This();

        pub fn call(self: *Self) !void {
            try Spawn(tickFunc, .{ &self.data, self.fun });
        }
    };
}

// No function generator...

fn loopFunc(data: *LoopData, allocator: std.mem.Allocator) void {
    while (true) {
        for (data.funcs.items) |funcData| {
            switch (funcData.args.len) {
                0 => {
                    @call(.auto, @as(*const fn () void, @ptrCast(funcData.ptr)), .{});
                },
                1 => {
                    @call(
                        .auto,
                        @as(*const fn (
                            a1: *anyopaque,
                        ) void, @ptrCast(funcData.ptr)),
                        .{funcData.args[0]},
                    );
                },
                2 => {
                    @call(.auto, @as(*const fn (
                        a1: *anyopaque,
                        a2: *anyopaque,
                    ) void, @ptrCast(funcData.ptr)), .{
                        funcData.args[0],
                        funcData.args[1],
                    });
                },
                3 => {
                    @call(.auto, @as(*const fn (
                        a1: *anyopaque,
                        a2: *anyopaque,
                        a3: *anyopaque,
                    ) void, @ptrCast(funcData.ptr)), .{
                        funcData.args[0],
                        funcData.args[1],
                        funcData.args[2],
                    });
                },
                4 => {
                    @call(.auto, @as(*const fn (
                        a1: *anyopaque,
                        a2: *anyopaque,
                        a3: *anyopaque,
                        a4: *anyopaque,
                    ) void, @ptrCast(funcData.ptr)), .{
                        funcData.args[0],
                        funcData.args[1],
                        funcData.args[2],
                        funcData.args[3],
                    });
                },
                5 => {
                    @call(.auto, @as(*const fn (
                        a1: *anyopaque,
                        a2: *anyopaque,
                        a3: *anyopaque,
                        a4: *anyopaque,
                        a5: *anyopaque,
                    ) void, @ptrCast(funcData.ptr)), .{
                        funcData.args[0],
                        funcData.args[1],
                        funcData.args[2],
                        funcData.args[3],
                        funcData.args[4],
                    });
                },
                6 => {
                    @call(.auto, @as(*const fn (
                        a1: *anyopaque,
                        a2: *anyopaque,
                        a3: *anyopaque,
                        a4: *anyopaque,
                        a5: *anyopaque,
                        a6: *anyopaque,
                    ) void, @ptrCast(funcData.ptr)), .{
                        funcData.args[0],
                        funcData.args[1],
                        funcData.args[2],
                        funcData.args[3],
                        funcData.args[4],
                        funcData.args[5],
                    });
                },
                7 => {
                    @call(.auto, @as(*const fn (
                        a1: *anyopaque,
                        a2: *anyopaque,
                        a3: *anyopaque,
                        a4: *anyopaque,
                        a5: *anyopaque,
                        a6: *anyopaque,
                        a7: *anyopaque,
                    ) void, @ptrCast(funcData.ptr)), .{
                        funcData.args[0],
                        funcData.args[1],
                        funcData.args[2],
                        funcData.args[3],
                        funcData.args[4],
                        funcData.args[5],
                        funcData.args[6],
                    });
                },
                else => {},
            }
        }

        data.funcs.clearAndFree(allocator);

        if (((data.terminate != null) and
            (data.terminate.?.* == true)) or
            (data.forceTerminate == true))
        {
            data.forceTerminate = false;

            break;
        }

        data.wait.reset();
        data.wait.wait();
    }
}

pub const LoopData = struct {
    funcs: std.ArrayList(LoopFuncData) = undefined,
    forceTerminate: bool = false,
    wait: std.Thread.ResetEvent = .{},
    terminate: ?*bool = null,
};

pub const LoopFuncData = struct {
    ptr: *const anyopaque,
    args: []const *anyopaque,
};

pub const Loop = struct {
    data: LoopData = .{},

    const Self = @This();

    pub fn init(
        self: *Self,
    ) void {
        self.data = .{ .funcs = std.ArrayList(LoopFuncData).empty };
    }

    pub fn deinit(
        self: *Self,
    ) void {
        self.data.forceTerminate = true;
    }

    pub fn call(self: *Self, allocator: std.mem.Allocator) !void {
        try Spawn(loopFunc, .{ &self.data, allocator });
    }

    pub fn callSameThread(self: *Self, allocator: std.mem.Allocator) void {
        loopFunc(&self.data, allocator);
    }

    pub fn add(self: *Self, allocator: std.mem.Allocator, funcData: LoopFuncData) !void {
        try self.data.funcs.append(funcData, allocator);
    }

    pub fn exec(self: *Self) void {
        self.data.wait.set();
    }
};
