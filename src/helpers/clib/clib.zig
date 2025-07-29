const std = @import("std");

pub const CLib = struct {
    name: []const u8,
    target: std.Build.ResolvedTarget,
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    inc_path: []const []const u8,
    c_files: []const []const u8,
    makefunc: ?*const fn (*CLib, *std.Build.Step.Compile) void = null,
    cflags: []const []const u8 = &[_][]const u8{},
    dependencies: []const *std.Build.Step.Compile = &[_]*std.Build.Step.Compile{},
    dynamic: bool = false,
    link_libc: bool = true,
    strip: bool = true,

    pub fn makeLibrary(options: *CLib) *std.Build.Step.Compile {
        const libdyn_option = std.fmt.allocPrint(options.b.allocator, "{s}_dynamic", .{options.name}) catch unreachable;
        defer options.b.allocator.free(libdyn_option);

        options.dynamic = options.b.option(bool, libdyn_option, "") orelse options.dynamic;

        const bin = options.b.addLibrary(.{
            .linkage = if (options.dynamic) .dynamic else .static,
            .name = options.name,
            .root_module = options.b.createModule(.{
                .target = options.target,
                .optimize = options.optimize,
                .strip = options.strip,
                .link_libc = options.link_libc,
            }),
        });

        for (options.dependencies) |dependency| {
            bin.linkLibrary(dependency);
        }

        for (options.inc_path) |path| {
            bin.addIncludePath(options.b.path(path));
        }

        for (options.c_files) |c_file| {
            bin.addCSourceFile(.{
                .file = options.b.path(c_file),
                .flags = options.cflags,
            });
        }

        options.callMakeFunc(bin);

        if (options.dynamic) {
            options.b.getInstallStep().dependOn(&options.b.addInstallArtifact(bin, .{
                .pdb_dir = .disabled,
                .h_dir = .disabled,
                .implib_dir = .disabled,
            }).step);
        }

        return bin;
    }

    pub fn callMakeFunc(self: *CLib, bin: *std.Build.Step.Compile) void {
        if (self.makefunc) |func| {
            func(self, bin);
        }
    }
};
