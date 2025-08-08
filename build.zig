const std = @import("std");
const bshr = @import("src/build_shared.zig");
const z2z = @import("src/helpers/zig2zig/zig2zig.zig");

pub const LoaderInfo = struct {
    pub var Mode: std.builtin.OutputMode = .Exe;
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const loaderMode = b.option(std.builtin.OutputMode, "loaderMode", "Output mode for the loader.") orelse .Exe;
    const isDLib = (loaderMode == .Lib);

    LoaderInfo.Mode = loaderMode;

    const loaderInfo = z2z.serializeType(LoaderInfo, b.allocator,
        \\const std = @import("std");
        \\
        \\
    ) catch unreachable;

    const genFile = b.addWriteFiles();
    const lshr = genFile.add("loader_shared.zig", loaderInfo);

    var loaderSource: []const u8 = "src/loader_executable.zig";
    const patcherSource: []const u8 = "src/patcher_common.zig";
    var loaderName: []const u8 = bshr.loaderName;

    const os = target.result.os.tag;

    if (isDLib) {
        if (target.query.cpu_arch != .x86) {
            std.log.info("Loader and patcher compilation targets should be x86.", .{});
        }

        switch (os) {
            .windows => {
                loaderSource = "src/loader_dlib_win32.zig";
                loaderName = "user32";
            },

            .linux => {
                // Wasted time on this
                // Windows' ABI is GNU by default

                if (target.query.abi != .gnu) {
                    std.log.info("Non GNU ABI will crash Steam", .{});
                }

                loaderSource = "src/loader_dlib_linux.zig";
            },

            else => {},
        }
    }

    const optimize = b.standardOptimizeOption(.{});
    const strippdb = b.option(bool, "strippdb", "Strip debug symbols file") orelse (optimize != .Debug);

    const loader = b.createModule(.{
        .root_source_file = b.path(loaderSource),
        .target = target,
        .optimize = optimize,
        .strip = strippdb,
        .link_libc = true,
    });
    const loaderBin = if (isDLib) b.addLibrary(.{
        .linkage = .dynamic,
        .name = loaderName,
        .root_module = loader,
    }) else b.addExecutable(.{
        .linkage = .dynamic,
        .name = loaderName,
        .root_module = loader,
    });

    // Took me a while to find this fix
    // Didn't notice this happening on Windows

    loaderBin.use_llvm = true;
    loaderBin.use_lld = true;

    const patcher = b.createModule(.{
        .root_source_file = b.path(patcherSource),
        .target = target,
        .optimize = optimize,
        .strip = strippdb,
        .link_libc = true,
    });
    patcher.addImport("websocket", b.dependency("websocket", .{}).module("websocket"));
    patcher.addAnonymousImport("loader_shared", .{
        .root_source_file = lshr,
    });
    const patcherBin = b.addLibrary(.{
        .linkage = .dynamic,
        .name = bshr.patcherName,
        .root_module = patcher,
    });
    patcherBin.use_llvm = true;
    patcherBin.use_lld = true;

    if (os == .windows) {
        patcherBin.linkSystemLibrary2("ws2_32", .{});
        patcherBin.linkSystemLibrary2("crypt32", .{});
    }

    if (os == .linux) {
        if (target.query.cpu_arch == .x86) {
            // https://github.com/ziglang/zig/issues/19342

            loaderBin.link_z_notext = true;
            patcherBin.link_z_notext = true;
        }
    }

    b.getInstallStep().dependOn(&b.addInstallArtifact(loaderBin, .{
        .implib_dir = .disabled,
    }).step);

    b.getInstallStep().dependOn(&b.addInstallArtifact(patcherBin, .{
        .implib_dir = .disabled,
    }).step);
}
