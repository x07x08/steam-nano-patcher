const std = @import("std");

const builtin = @import("builtin");
const native_os = builtin.os.tag;

const bshr = @import("build_shared.zig");

const asy = @import("helpers/zig_async/async.zig");
const hlp = @import("helpers/utils.zig");
const jsse = @import("helpers/settings/settings.zig").JSON;

const lshr = @import("loader_shared");

// mongoose has failed while its older fork works fine
// Good job.

const c = @cImport({
    @cInclude("civetweb/civetweb.h");
});

pub const Errors = error{
    ConnectionFailed,
};

pub const dtBindingName: []const u8 = "__snp_devtools_binding__";
pub const settingsFile: []const u8 = bshr.patcherName ++ .{std.fs.path.sep} ++ "patcher_settings.json";

pub const PatcherSettings = struct {
    injectorPath: ?[]const u8 = null,
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
                bshr.patcherName ++ "/injector/injector.js",
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
    }
};

pub const CDPID = struct {
    const AttachToTarget = 7800;
    const ExposeDP = 7801;
    const LogEnable = 7802;
    const PageEnable = 7803;
    const AddScript = 7804;
    const BypassCSP = 7805;
};

pub const ClientHandler = struct {
    connection: ?*c.mg_connection,
    mainLoop: *asy.Loop,
    settings: *PatcherSettings,
    execScript: ?[]u8,

    pub fn reconnectToDevTools(self: *ClientHandler, allocator: std.mem.Allocator) !void {
        const wsURL = try self.getDevToolsEntry(allocator);
        errdefer allocator.free(wsURL);

        self.connection = null;

        try self.initDevTools(wsURL);
        try self.connectToDevTools(allocator);

        allocator.free(wsURL);
    }

    pub fn connectToDevTools(self: *ClientHandler, allocator: std.mem.Allocator) !void {
        const params1 = .{
            .discover = true,
        };

        self.writeHandler(@constCast(
            &(std.json.Stringify.valueAlloc(
                allocator,
                .{
                    .id = CDPID.AttachToTarget,
                    .method = "Target.setDiscoverTargets",
                    .params = params1,
                },
                .{},
            ) catch unreachable),
        ), &true);
    }

    pub fn initDevTools(self: *ClientHandler, wsURL: [:0]u8) !void {
        const parsedURL = try std.Uri.parse(wsURL);

        const urlHost, const urlPath = .{
            hlp.returnURIComponentString(parsedURL.host.?),
            hlp.returnURIComponentString(parsedURL.path),
        };

        const schemeSize = parsedURL.scheme.len + 3; // ://
        const cHost = wsURL[schemeSize .. schemeSize + urlHost.len];
        cHost.ptr[cHost.len] = 0;

        self.connection = c.mg_connect_websocket_client(
            cHost.ptr,
            self.settings.steamPort,
            0,
            null,
            0,
            urlPath.ptr,
            null,
            &ClientHandler.handleMessage,
            &ClientHandler.handleClose,
            self,
        ) orelse return Errors.ConnectionFailed;
    }

    pub fn getDevToolsEntry(self: *ClientHandler, allocator: std.mem.Allocator) ![:0]u8 {
        if (self.settings.connectionDelay) |delay| {
            const time: u64 = std.math.lossyCast(u64, delay * @as(f64, std.time.ns_per_s));

            std.Thread.sleep(time);
        }

        var client = std.http.Client{ .allocator = allocator };

        defer {
            client.deinit();
        }

        var response = std.io.Writer.Allocating.init(allocator);

        defer {
            response.deinit();
        }

        const url = try std.fmt.allocPrint(allocator, "http://localhost:{d}/json/version", .{
            self.settings.steamPort,
        });
        defer allocator.free(url);

        _ = try client.fetch(.{
            .response_writer = &response.writer,
            .method = .GET,
            .location = .{ .url = url },
            .keep_alive = false,
        });

        var json: std.json.Parsed(std.json.Value) = try std.json.parseFromSlice(
            std.json.Value,
            allocator,
            response.written(),
            .{},
        );

        defer {
            json.deinit();
        }

        return allocator.dupeZ(u8, json.value.object.get("webSocketDebuggerUrl").?.string);
    }

    pub fn writeHandler(self: *ClientHandler, data: *[]u8, free: *const bool) void {
        defer {
            if (free.*) {
                hlp.gpa.free(data.*);
            }
        }

        if (self.connection == null) return;

        if (c.mg_websocket_client_write(self.connection.?, c.MG_WEBSOCKET_OPCODE_TEXT, data.*.ptr, data.len) == 0) {
            const sl = @src();

            std.log.err("{s}->{s} : {s}", .{ sl.file, sl.fn_name, "failed" });
        }
    }

    pub fn attachToPage(self: *ClientHandler, targetID: []const u8) void {
        const params1 = .{
            .targetId = targetID,
            .flatten = true,
        };

        const params2 = .{
            .targetId = targetID,
            .bindingName = dtBindingName,
        };

        self.writeHandler(@constCast(
            &(std.json.Stringify.valueAlloc(
                hlp.gpa,
                .{
                    .id = CDPID.AttachToTarget,
                    .method = "Target.attachToTarget",
                    .params = params1,
                },
                .{},
            ) catch unreachable),
        ), &true);

        self.writeHandler(@constCast(
            &(std.json.Stringify.valueAlloc(
                hlp.gpa,
                .{
                    .id = CDPID.ExposeDP,
                    .method = "Target.exposeDevToolsProtocol",
                    .params = params2,
                },
                .{},
            ) catch unreachable),
        ), &true);
    }

    pub fn textMsg(self: *ClientHandler, data: []u8) void {
        const msg: std.json.Parsed(std.json.Value) = std.json.parseFromSlice(
            std.json.Value,
            hlp.gpa,
            data,
            .{},
        ) catch unreachable;

        defer msg.deinit();

        if (self.settings.debug and self.settings.printRPCMessages) {
            std.debug.print("{s}\n", .{data});
        }

        if (msg.value.object.get("id")) |_| {
            if (msg.value.object.get("error")) |_| {
                return;
            }
        } else {
            const method = msg.value.object.get("method") orelse return;

            if (std.mem.eql(u8, method.string, "Target.attachedToTarget")) {
                const params = msg.value.object.get("params") orelse return;
                const jsContextSessionID = params.object.get("sessionId").?.string;

                self.writeHandler(@constCast(
                    &(std.json.Stringify.valueAlloc(
                        hlp.gpa,
                        .{
                            .id = CDPID.LogEnable,
                            .method = "Log.enable",
                            .sessionId = jsContextSessionID,
                        },
                        .{},
                    ) catch unreachable),
                ), &true);

                self.writeHandler(@constCast(
                    &(std.json.Stringify.valueAlloc(
                        hlp.gpa,
                        .{
                            .id = CDPID.PageEnable,
                            .method = "Page.enable",
                            .sessionId = jsContextSessionID,
                        },
                        .{},
                    ) catch unreachable),
                ), &true);

                if (self.execScript) |capt| {
                    const params1 = .{
                        .enabled = true,
                    };

                    self.writeHandler(@constCast(
                        &(std.json.Stringify.valueAlloc(
                            hlp.gpa,
                            .{
                                .id = CDPID.BypassCSP,
                                .method = "Page.setBypassCSP",
                                .params = params1,
                                .sessionId = jsContextSessionID,
                            },
                            .{},
                        ) catch unreachable),
                    ), &true);

                    // Without "runImmediately" it does not run
                    //
                    // The "Runtime" domain does not bypass CORS and it cannot
                    // run inside fetched documents

                    const params2 = .{
                        .source = capt,
                        .runImmediately = true,
                    };

                    self.writeHandler(@constCast(
                        &(std.json.Stringify.valueAlloc(
                            hlp.gpa,
                            .{
                                .id = CDPID.AddScript,
                                .method = "Page.addScriptToEvaluateOnNewDocument",
                                .params = params2,
                                .sessionId = jsContextSessionID,
                            },
                            .{},
                        ) catch unreachable),
                    ), &true);
                }
            } else if (std.mem.eql(u8, method.string, "Target.targetCreated")) {
                const targetInfo = msg.value.object.get("params").?.object.get("targetInfo").?;

                self.attachToPage(targetInfo.object.get("targetId").?.string);
            }
        }
    }

    pub fn handleMessage(
        _: ?*c.struct_mg_connection,
        flags: c_int,
        data: [*c]u8,
        dataLen: usize,
        userData: ?*anyopaque,
    ) callconv(.c) c_int {
        const self: *ClientHandler = @ptrCast(@alignCast(userData.?));

        const isText: bool = ((flags & 0xf) == c.MG_WEBSOCKET_OPCODE_TEXT);

        if (isText) {
            self.textMsg(data[0..dataLen]);
        }

        return 1;
    }

    pub fn handleClose(
        _: ?*const c.struct_mg_connection,
        userData: ?*anyopaque,
    ) callconv(.c) void {
        const self: *ClientHandler = @ptrCast(@alignCast(userData.?));

        self.close();
    }

    pub fn close(self: *ClientHandler) void {
        std.log.info("Disconnected", .{});

        if (self.settings.autoreconnect) {
            std.log.info("Trying to reconnect", .{});

            if (self.reconnectToDevTools(hlp.gpa)) |_| {
                return;
            } else |err| {
                std.log.err("Failed to reconnect : {}", .{err});

                self.connection = null;
            }
        }

        self.mainLoop.deinit();
        self.mainLoop.exec();
    }
};

export fn SNPEntryPoint() void {
    var exit = false;

    start(&exit) catch |err| {
        const sl = @src();

        std.log.err("{s}->{s} : {}", .{ sl.file, sl.fn_name, err });
    };

    if (exit) std.process.exit(0);
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

    std.log.info("Loaded", .{});

    var execScript: ?[]u8 = null;

    defer {
        if (execScript) |capt| {
            hlp.gpa.free(capt);
        }
    }

    blk: {
        if (settings.injectorPath) |capt| {
            const scriptFile = try jsonSettings.cwd.openFile(capt, .{});
            const stat = scriptFile.stat() catch {
                scriptFile.close();

                break :blk;
            };

            execScript = hlp.gpa.alloc(u8, @intCast(stat.size)) catch {
                scriptFile.close();

                break :blk;
            };

            _ = scriptFile.read(execScript.?) catch {
                hlp.gpa.free(execScript.?);
                execScript = null;

                scriptFile.close();

                break :blk;
            };

            scriptFile.close();
        }
    }

    var mainLoop: asy.Loop = .{};
    mainLoop.init();

    var clh = ClientHandler{
        .connection = null,
        .mainLoop = &mainLoop,
        .settings = &settings,
        .execScript = execScript,
    };

    const wsURL = try clh.getDevToolsEntry(hlp.gpa);
    errdefer hlp.gpa.free(wsURL);

    _ = c.mg_init_library(0);

    try clh.initDevTools(wsURL);
    try clh.connectToDevTools(hlp.gpa);

    hlp.gpa.free(wsURL);

    mainLoop.callSameThread(hlp.gpa);
}
