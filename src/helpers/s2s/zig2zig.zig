const std = @import("std");

pub fn isBaseTypePrimitive(T: type) bool {
    switch (@typeInfo(T)) {
        .optional => |opt| {
            switch (@typeInfo(opt.child)) {
                .pointer => |ptr| {
                    return isBaseTypePrimitive(ptr.child);
                },

                .array => |ptr| {
                    return isBaseTypePrimitive(ptr.child);
                },

                else => {
                    return isBaseTypePrimitive(opt.child);
                },
            }
        },

        .pointer => |ptr| {
            return isBaseTypePrimitive(ptr.child);
        },

        .array => |ptr| {
            return isBaseTypePrimitive(ptr.child);
        },

        else => {
            return std.zig.isPrimitive(@typeName(T));
        },
    }
}

pub fn getBaseTypeName(T: type) []const u8 {
    switch (@typeInfo(T)) {
        .optional => |opt| {
            switch (@typeInfo(opt.child)) {
                .pointer => |ptr| {
                    return getBaseTypeName(ptr.child);
                },

                .array => |ptr| {
                    return getBaseTypeName(ptr.child);
                },

                else => {
                    return getBaseTypeName(opt.child);
                },
            }
        },

        .pointer => |ptr| {
            return getBaseTypeName(ptr.child);
        },

        .array => |ptr| {
            return getBaseTypeName(ptr.child);
        },

        else => {
            return @typeName(T);
        },
    }
}

pub fn getSplitTypeName(T: type) struct { []const u8, []const u8 } {
    const typeName = @typeName(T);
    const baseName = comptime getBaseTypeName(T);
    const baseIndex = comptime std.mem.indexOf(u8, @typeName(T), baseName) orelse 0;

    return .{
        typeName[0..baseIndex],
        typeName[baseIndex..],
    };
}

pub fn serializeStruct(
    sf: std.builtin.Type.StructField,
    val: anytype,
    writer: *std.io.Writer,
) !void {
    //const isPrimitive = isBaseTypePrimitive(field.type);

    switch (@typeInfo(sf.type)) {
        .@"struct" => |st| {
            try writer.print(
                ".{{",
                .{},
            );

            inline for (st.fields) |field| {
                try serializeStruct(sf, @field(val, field.name), writer);
            }

            try writer.print(
                "}},",
                .{},
            );
        },

        else => {
            try writer.print(
                ".{s} = {any},",
                .{
                    sf.name,
                    val,
                },
            );
        },
    }
}

pub fn serializeSlice(
    sliceType: type,
    val: anytype,
    writer: *std.io.Writer,
) !void {
    const sliceTypeInfo = @typeInfo(sliceType);

    switch (sliceTypeInfo) {
        .pointer => |ptr| {
            for (val) |childVal| {
                try writer.print(
                    "&.{{",
                    .{},
                );

                try serializeSlice(ptr.child, childVal, writer);

                try writer.print(
                    "}},",
                    .{},
                );
            }
        },

        .array => |ptr| {
            try serializeSlice(ptr.child, val, writer);
        },

        .@"struct" => |st| {
            for (val) |data| {
                try writer.print(
                    ".{{",
                    .{},
                );

                inline for (st.fields) |field| {
                    try serializeStruct(field, @field(data, field.name), writer);
                }

                try writer.print(
                    "}},",
                    .{},
                );
            }
        },

        else => {
            for (val) |data| {
                try writer.print(
                    "{any},",
                    .{data},
                );
            }
        },
    }
}

pub fn serializeContainer(
    value: anytype,
    TI: std.builtin.Type,
    writer: *std.io.Writer,
) !void {
    switch (TI) {
        .@"struct" => |container| {
            inline for (container.decls) |decl| {
                const declVal = @field(value, decl.name);
                const declType = @TypeOf(declVal);
                const declTypeInfo = @typeInfo(declType);
                const splitTypeName = getSplitTypeName(declType);

                const isPrimitive = isBaseTypePrimitive(declType);

                if (isPrimitive) {
                    try writer.print(
                        \\pub var {s}: {s}{s} = 
                    ,
                        .{
                            decl.name,
                            splitTypeName[0],
                            splitTypeName[1],
                        },
                    );
                } else {
                    try writer.print(
                        \\pub var {s}: {s}std.{s} = 
                    ,
                        .{
                            decl.name,
                            splitTypeName[0],
                            splitTypeName[1],
                        },
                    );
                }

                switch (declTypeInfo) {
                    .@"struct" => |st| {
                        try writer.print(
                            ".{{",
                            .{},
                        );

                        inline for (st.fields) |field| {
                            try serializeStruct(field, @field(declVal, field.name), writer);
                        }

                        try writer.print(
                            "}};",
                            .{},
                        );
                    },

                    .pointer => |ptr| {
                        try writer.print(
                            "&.{{",
                            .{},
                        );

                        try serializeSlice(ptr.child, declVal, writer);

                        try writer.print(
                            "}};",
                            .{},
                        );
                    },

                    else => {
                        try writer.print(
                            "{any};",
                            .{declVal},
                        );
                    },
                }
            }
        },

        else => {},
    }
}

pub fn serializeType(value: anytype, allocator: std.mem.Allocator, prepend: []const u8) ![]u8 {
    var output = std.io.Writer.Allocating.init(allocator);
    errdefer output.deinit();

    var writer = &output.writer;

    try writer.print(
        "{s}",
        .{prepend},
    );

    try serializeContainer(value, @typeInfo(value), writer);

    return output.toOwnedSlice();
}
