const std = @import("std");

pub const Errors = error{
    NullFile,
};

pub const JSON = struct {
    allocator: std.mem.Allocator,
    file: ?std.fs.File = null,
    cwd: std.fs.Dir,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .cwd = std.fs.cwd(),
        };
    }

    pub fn truncateFile(self: *Self) !void {
        if (self.file == null) return Errors.NullFile;

        try self.file.?.seekTo(0);
        try self.file.?.setEndPos(0);
    }

    pub fn serialize(self: *Self, structure: anytype) !void {
        if (self.file == null) return Errors.NullFile;

        const string = try std.json.Stringify.valueAlloc(
            self.allocator,
            structure,
            .{ .whitespace = .indent_tab },
        );
        defer self.allocator.free(string);

        _ = try self.file.?.write(string);
    }

    pub fn deserialize(self: *Self, T: type, buf: *[]u8) !std.json.Parsed(T) {
        if (self.file == null) return Errors.NullFile;

        _ = try self.file.?.read(buf.*);

        return try std.json.parseFromSlice(T, self.allocator, buf.*, .{
            .ignore_unknown_fields = true,
        });
    }

    pub fn fetchOrSerialize(self: *Self, T: type, structure: anytype) !void {
        const stat = try self.file.?.stat();
        var buf = try self.allocator.alloc(u8, @intCast(stat.size));
        defer self.allocator.free(buf);

        if (stat.size != 0) {
            if (self.deserialize(T, &buf)) |parsed| {
                if (@hasDecl(T, "initFromParsed")) {
                    try structure.initFromParsed(parsed);
                }

                defer parsed.deinit();
            } else |err| {
                return err;
            }
        } else {
            try self.serialize(structure);
        }
    }

    pub fn defaultStrings(T: type, structure: *T) void {
        inline for (@typeInfo(T).@"struct".fields) |field| {
            if (@typeInfo(field.type) != .optional) {
                continue;
            }

            @field(structure.*, field.name) = null;

            switch (field.type) {
                ?[]const u8 => {
                    if (@hasDecl(T, "defaultString")) {
                        structure.defaultString(field.name);
                    }
                },
                else => {},
            }
        }
    }

    pub fn initStructureStringsFromParsed(
        allocator: std.mem.Allocator,
        T: type,
        structure: *T,
        parsed: std.json.Parsed(T),
    ) !void {
        inline for (@typeInfo(T).@"struct".fields) |field| {
            const fieldInfo = @typeInfo(field.type);

            if ((fieldInfo != .optional) or
                (fieldInfo.optional.child != []const u8))
            {
                continue;
            }

            @field(structure.*, field.name) = null;

            if (@field(parsed.value, field.name)) |val| {
                switch (@TypeOf(val)) {
                    []const u8 => {
                        @field(structure.*, field.name) = try allocator.dupe(u8, val);
                    },
                    else => {},
                }
            } else {
                if (@hasDecl(T, "defaultString")) {
                    structure.defaultString(field.name);
                }
            }
        }
    }

    pub fn simpleInitFromParsed(
        T: type,
        structure: *T,
        parsed: std.json.Parsed(T),
    ) void {
        structure.* = parsed.value;

        inline for (@typeInfo(T).@"struct".fields) |field| {
            switch (@typeInfo(field.type)) {
                .@"struct" => {
                    @field(structure.*, field.name) = .{};
                },
                else => {},
            }
        }
    }
};
