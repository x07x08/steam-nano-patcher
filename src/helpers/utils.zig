const std = @import("std");

const builtin = @import("builtin");
const native_os = builtin.os.tag;

pub const Errors = error{
    BadDirName,
};

pub var alloc_cfg: ?std.heap.DebugAllocator(.{}) = if (builtin.mode == .ReleaseFast) null else .init;
pub var gpa: std.mem.Allocator = undefined;

pub fn initAllocator() void {
    gpa = if (alloc_cfg == null) std.heap.smp_allocator else alloc_cfg.?.allocator();
}

pub fn deinitAllocator() std.heap.Check {
    if (alloc_cfg != null) {
        return alloc_cfg.?.deinit();
    }

    return .ok;
}

pub fn openDynLib(allocator: std.mem.Allocator, libName: []const u8) !std.DynLib {
    var targetLib: ?[]const u8 = null;

    defer {
        if (targetLib != null) {
            allocator.free(targetLib.?);
        }
    }

    switch (native_os) {
        .linux => {
            targetLib = try std.mem.concat(allocator, u8, &.{
                libName, ".so",
            });

            return std.DynLib.open(targetLib.?) catch {
                allocator.free(targetLib.?);

                targetLib = try std.mem.concat(allocator, u8, &.{
                    "./", libName, ".so",
                });

                return std.DynLib.open(targetLib.?);
            };
        },

        .windows => {
            targetLib = try std.mem.concat(allocator, u8, &.{
                libName, ".dll",
            });

            return std.DynLib.open(targetLib.?);
        },

        else => {
            return std.DynLib.open(libName);
        },
    }
}

pub fn HeapInit(allocator: std.mem.Allocator, T: type) !*T {
    var temp: T = if (@hasDecl(T, "init"))
        T.init(allocator)
    else if (@hasField(T, "allocator"))
        .{ .allocator = allocator }
    else
        .{};

    const ret = try allocator.create(T);
    ret.* = temp;

    if (@hasDecl(T, "deinit")) temp.deinit();

    return ret;
}

pub fn HeapElem(allocator: std.mem.Allocator, elem: anytype) !*@TypeOf(elem) {
    const elemType = @TypeOf(elem);

    const ret = try allocator.create(elemType);
    ret.* = elem;

    return ret;
}

pub fn returnURIComponentString(component: std.Uri.Component) []const u8 {
    switch (component) {
        .percent_encoded, .raw => |string| {
            return string;
        },
    }
}

pub fn makeFileTree(cwd: std.fs.Dir, fullPath: []const u8, flags: std.fs.File.CreateFlags) !std.fs.File {
    try cwd.makePath(std.fs.path.dirname(fullPath) orelse return Errors.BadDirName);

    return try cwd.createFile(fullPath, flags);
}
