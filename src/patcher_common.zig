const std = @import("std");

const builtin = @import("builtin");
const native_os = builtin.os.tag;

const bshr = @import("build_shared.zig");

const asy = @import("helpers/zig_async/async.zig");
const hlp = @import("helpers/utils.zig");
const jsse = @import("helpers/settings/settings.zig").JSON;
const z2l = @import("helpers/s2s/zig2lua.zig");

const lshr = @import("loader_shared");

//// mongoose has failed while its older fork works fine
//// Good job.
//
const c = @cImport({
    @cInclude("civetweb/civetweb.h");
});

const clj = @import("clj");

pub const Errors = error{
    LuaContextFailed,
};

pub const settingsFile: []const u8 = bshr.patcherName ++ .{std.fs.path.sep} ++ "patcher_settings.json";

pub const PatcherSettings = struct {
    injectorPath: ?[]const u8 = null,
    luaScript: ?[]const u8 = null,
    steamPort: u16 = 8080,
    debug: bool = false,
    printRPCMessages: bool = false,
    autoreconnect: bool = false,
    exitOnLoopEnd: bool = true,
    connectionDelay: ?f64 = null,

    pub fn defaultString(self: *PatcherSettings, fieldName: []const u8) void {
        if (std.mem.eql(u8, fieldName, "injectorPath")) {
            self.injectorPath = hlp.gpa.dupe(
                u8,
                bshr.patcherName ++ "/js/injector/injector.js",
            ) catch unreachable;
        }

        if (std.mem.eql(u8, fieldName, "luaScript")) {
            self.luaScript = hlp.gpa.dupe(
                u8,
                bshr.patcherName ++ "/lua/script.lua",
            ) catch unreachable;
        }
    }

    pub fn initFromParsed(self: *PatcherSettings, parsed: std.json.Parsed(PatcherSettings)) !void {
        self.deinit();

        self.* = parsed.value;
        try jsse.initStructureStringsFromParsed(hlp.gpa, PatcherSettings, self, parsed);
    }

    pub fn deinit(self: *PatcherSettings) void {
        if (self.injectorPath) |capt| {
            hlp.gpa.free(capt);
        }

        if (self.luaScript) |capt| {
            hlp.gpa.free(capt);
        }
    }
};

export fn fixbrokenexport() *const anyopaque {
    _ = @import("c_export.zig");

    return @ptrCast(&c.mg_init_library);
}

export fn SNPEntryPoint() void {
    var exit = false;

    start(&exit) catch |err| {
        const sl = @src();

        std.log.err("{s}->{s} : {}", .{ sl.file, sl.fn_name, err });
    };

    if (exit) std.process.exit(0);
}

fn startLua(luaCtx: *clj.lua_State, settings: *PatcherSettings) void {
    z2l.structToTable(luaCtx, @typeInfo(PatcherSettings), "patcherSettings", settings.*);
    z2l.containerToTable(luaCtx, @typeInfo(std.fs.path), "stdfspath", std.fs.path);

    const err = clj.luaL_dofile(luaCtx, settings.luaScript.?.ptr);

    if (err) {
        std.log.err("{s}", .{
            clj.lua_tolstring(luaCtx, -1, null),
        });

        clj.lua_pop(luaCtx, 1);
    }
}

fn start(exit: *bool) !void {
    hlp.initAllocator();

    var settings = PatcherSettings{};
    jsse.defaultStrings(PatcherSettings, &settings);
    var jsonSettings = jsse.init(hlp.gpa);

    defer {
        if ((lshr.Mode == .Exe) and settings.exitOnLoopEnd) {
            exit.* = true;
        }
    }

    defer _ = hlp.deinitAllocator();

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

    defer {
        settings.deinit();
        jsonSettings.file.?.close();
    }

    try jsonSettings.fetchOrSerialize(PatcherSettings, &settings);

    if ((native_os == .windows) and (lshr.Mode == .Lib)) {
        const winDefs = @import("win32/defines.zig");

        if (settings.debug) {
            const conErr = winDefs.AllocConsole();

            if (conErr == 0) {
                winDefs.MessageBoxA_Util(
                    hlp.gpa,
                    "Console error",
                    .{},
                    "{s}",
                    .{bshr.windowName},
                    0x10,
                ) catch unreachable;
            }
        }
    }

    std.log.info("Patcher loaded", .{});

    const luaCtx = clj.luaL_newstate() orelse return Errors.LuaContextFailed;

    clj.luaL_openlibs(luaCtx);

    if (settings.luaScript) |_| {
        const cwd = jsonSettings.cwd.realpathAlloc(hlp.gpa, ".") catch unreachable;
        z2l.registerValue(luaCtx, []u8, "currentDirectory", cwd);
        z2l.registerValue(luaCtx, bool, "isCivetDynamic", lshr.CivetDynamic);

        hlp.gpa.free(cwd);

        startLua(luaCtx, &settings);
    }

    clj.lua_close(luaCtx);
}
