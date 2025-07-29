const std = @import("std");

const builtin = @import("builtin");
const native_os = builtin.os.tag;

const bshr = @import("build_shared.zig");

const asy = @import("helpers/zig_async/async.zig");
const hlp = @import("helpers/utils.zig");
const jsse = @import("helpers/settings/settings.zig").JSON;

const lshr = @import("loader_shared");

const websocket = @import("websocket");

pub const dtBindingName: []const u8 = "__snp_devtools_binding__";
pub const settingsFile: []const u8 = bshr.patcherName ++ .{std.fs.path.sep} ++ "patcher_settings.json";

pub const PatcherSettings = struct {
    injectorPath: ?[]const u8 = null,
    steamPort: u16 = 8080,
    debug: bool = false,
    printRPCMessages: bool = false,
    autoreconnect: bool = false,

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
    client: *websocket.Client,
    mainLoop: *asy.Loop,
    settings: *PatcherSettings,
    execScript: ?[]u8,

    pub fn writeHandler(self: *ClientHandler, data: *[]u8, free: *const bool) void {
        defer {
            if (free.*) {
                hlp.gpa.free(data.*);
            }
        }

        self.client.writeText(data.*) catch |err| {
            std.log.err("{}", .{err});
        };
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

    pub fn serverMessage(self: *ClientHandler, data: []u8, _: websocket.MessageTextType) !void {
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

    pub fn close(self: *ClientHandler) void {
        std.log.info("Disconnected", .{});

        if (self.settings.autoreconnect) {
            std.log.info("Trying to reconnect", .{});

            if (reconnectToDevTools(hlp.gpa, self)) |_| {
                return;
            } else |err| {
                std.log.err("Failed to reconnect : {}", .{err});
            }
        }

        self.client.close(.{}) catch unreachable;
        self.client.deinit();

        self.mainLoop.deinit();
        self.mainLoop.exec();
    }
};

export fn SNPEntryPoint() void {
    start() catch |err| {
        std.log.err("{}", .{err});

        return;
    };
}

fn start() !void {
    hlp.initAllocator();

    var settings = PatcherSettings{};
    jsse.defaultStrings(PatcherSettings, &settings);
    var jsonSettings = jsse.init(hlp.gpa);

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

    const wsURL = try getDevToolsEntry(hlp.gpa, settings.steamPort);
    errdefer hlp.gpa.free(wsURL);

    var wsClient = try initDevTools(hlp.gpa, wsURL, settings.steamPort);

    var mainLoop: asy.Loop = .{};
    mainLoop.init(hlp.gpa);

    var clh = ClientHandler{
        .client = &wsClient,
        .mainLoop = &mainLoop,
        .settings = &settings,
        .execScript = execScript,
    };

    if (clh.client.readLoopInNewThread(&clh)) |thread| {
        thread.detach();
    } else |err| {
        return err;
    }

    try connectToDevTools(hlp.gpa, &clh);

    hlp.gpa.free(wsURL);

    mainLoop.callSameThread();
}

pub fn reconnectToDevTools(allocator: std.mem.Allocator, clh: *ClientHandler) !void {
    const wsURL = try getDevToolsEntry(hlp.gpa, clh.settings.steamPort);
    errdefer hlp.gpa.free(wsURL);

    try clh.client.close(.{});
    clh.client.deinit();

    var wsClient = try initDevTools(allocator, wsURL, clh.settings.steamPort);
    clh.client = &wsClient;

    try connectToDevTools(allocator, clh);

    hlp.gpa.free(wsURL);

    try clh.client.readLoop(clh);
}

pub fn connectToDevTools(allocator: std.mem.Allocator, clh: *ClientHandler) !void {
    const params1 = .{
        .discover = true,
    };

    clh.writeHandler(@constCast(
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

pub fn initDevTools(allocator: std.mem.Allocator, wsURL: []const u8, port: u16) !websocket.Client {
    const parsedURL = try std.Uri.parse(wsURL);

    const urlHost, const urlPath = .{
        hlp.returnURIComponentString(parsedURL.host.?),
        hlp.returnURIComponentString(parsedURL.path),
    };

    var wsClient = try websocket.Client.init(allocator, .{
        .host = urlHost,
        .port = port,
    });

    errdefer wsClient.deinit();

    try wsClient.handshake(urlPath, .{});

    return wsClient;
}

pub fn getDevToolsEntry(allocator: std.mem.Allocator, port: u16) ![]const u8 {
    const client = try hlp.HeapInit(allocator, std.http.Client);

    defer {
        client.deinit();
        allocator.destroy(client);
    }

    const response = try hlp.HeapInit(allocator, std.ArrayList(u8));

    defer {
        response.deinit();
        allocator.destroy(response);
    }

    const url = try std.fmt.allocPrint(allocator, "http://localhost:{d}/json/version", .{port});
    defer allocator.free(url);

    _ = try client.fetch(.{
        .response_storage = .{ .dynamic = response },
        .method = .GET,
        .location = .{ .url = url },
        .keep_alive = false,
    });

    var json: std.json.Parsed(std.json.Value) = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        response.items,
        .{},
    );

    defer {
        json.deinit();
    }

    return allocator.dupe(u8, json.value.object.get("webSocketDebuggerUrl").?.string);
}
