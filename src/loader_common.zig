const std = @import("std");

const bshr = @import("build_shared.zig");

const asy = @import("helpers/zig_async/async.zig");
const hlp = @import("helpers/utils.zig");
const jsse = @import("helpers/settings/settings.zig").JSON;

pub const Errors = error{
    EntryNotFound,
};

pub const settingsFile: []const u8 = bshr.patcherName ++ .{std.fs.path.sep} ++ "settings.json";

pub const Module = struct {
    path: []const u8,
    entryPoint: [:0]const u8,

    pub fn deinit(self: *const Module, allocator: std.mem.Allocator) void {
        allocator.free(self.entryPoint);
        allocator.free(self.path);
    }
};

pub const LoaderSettings = struct {
    loadOtherModules: bool = false,
    modules: std.json.ArrayHashMap(*Module) = .{},

    pub fn ownModule(self: *LoaderSettings, K: []const u8, val: *const Module) !void {
        const dMClone = try hlp.gpa.create(Module);
        dMClone.entryPoint = try hlp.gpa.dupeZ(u8, val.entryPoint);
        dMClone.path = try hlp.gpa.dupe(u8, val.path);

        try self.modules.map.put(
            hlp.gpa,
            try hlp.gpa.dupe(u8, K),
            dMClone,
        );
    }

    pub fn initFromParsed(self: *LoaderSettings, parsed: std.json.Parsed(LoaderSettings)) !void {
        self.deinit();
        jsse.simpleInitFromParsed(LoaderSettings, self, parsed);

        var iter = parsed.value.modules.map.iterator();

        while (iter.next()) |entry| {
            try self.ownModule(entry.key_ptr.*, entry.value_ptr.*);
        }
    }

    pub fn deinit(self: *LoaderSettings) void {
        var iter = self.modules.map.iterator();

        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit(hlp.gpa);
            hlp.gpa.destroy(entry.value_ptr.*);
            hlp.gpa.free(entry.key_ptr.*);
        }

        self.modules.deinit(hlp.gpa);
    }
};

pub fn loadModules() !void {
    hlp.initAllocator();

    const defaultModule = Module{
        .entryPoint = "SNPEntryPoint",
        .path = bshr.patcherName,
    };

    var settings = LoaderSettings{};
    var jsonSettings = jsse.init(hlp.gpa);

    defer {
        settings.deinit();
        jsonSettings.file.?.close();
        _ = hlp.deinitAllocator();
    }

    jsonSettings.file = jsonSettings.cwd.openFile(
        settingsFile,
        .{
            .mode = .read_write,
        },
    ) catch try hlp.makeFileTree(
        jsonSettings.cwd,
        settingsFile,
        .{
            .truncate = true,
            .read = true,
        },
    );

    try settings.ownModule(bshr.patcherName, &defaultModule);
    try jsonSettings.fetchOrSerialize(LoaderSettings, &settings);

    var iter = settings.modules.map.iterator();

    while (iter.next()) |entry| {
        const module = entry.value_ptr.*;

        try loadModule(module);

        if (!settings.loadOtherModules and std.mem.eql(u8, module.path, defaultModule.path)) {
            break;
        }
    }
}

pub fn loadModule(module: *const Module) !void {
    var bin = try hlp.openDynLib(hlp.gpa, module.path);

    const entry = bin.lookup(*fn () void, module.entryPoint);

    if (entry) |val| {
        try asy.Spawn(val, .{});
    } else {
        bin.close();

        return Errors.EntryNotFound;
    }
}
