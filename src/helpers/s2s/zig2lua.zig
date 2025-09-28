const std = @import("std");
const clj = @import("clj");

fn registerCollection(
    luaCtx: *clj.lua_State,
    T: type,
    name: []const u8,
    val: anytype,
) void {
    switch (T) {
        u8 => {
            clj.lua_pushlstring(luaCtx, val.ptr, val.len);
            clj.lua_setglobal(luaCtx, name.ptr);
        },

        else => {},
    }
}

pub fn registerValue(
    luaCtx: *clj.lua_State,
    T: type,
    name: [:0]const u8,
    val: anytype,
) void {
    const TI = @typeInfo(T);

    switch (TI) {
        .bool => {
            clj.lua_pushboolean(luaCtx, @intFromBool(val));
            clj.lua_setglobal(luaCtx, name.ptr);
        },

        .int, .comptime_int => {
            clj.lua_pushinteger(luaCtx, val);
            clj.lua_setglobal(luaCtx, name.ptr);
        },

        .float, .comptime_float => {
            clj.lua_pushnumber(luaCtx, val);
            clj.lua_setglobal(luaCtx, name.ptr);
        },

        .array => |arr| {
            registerCollection(luaCtx, arr.child, name, val[0..arr.len]);
        },

        .pointer => |ptr| {
            switch (ptr.size) {
                .slice => {
                    registerCollection(luaCtx, ptr.child, name, val);
                },

                .one => {
                    const childPtrTI = @typeInfo(ptr.child);

                    switch (childPtrTI) {
                        .array => |arr| {
                            registerCollection(luaCtx, arr.child, name, val[0..arr.len]);
                        },

                        else => {
                            clj.lua_pushlightuserdata(luaCtx, val);
                            clj.lua_setglobal(luaCtx, name.ptr);
                        },
                    }
                },

                else => {},
            }
        },

        .optional => |opt| {
            if (val) |data| {
                registerValue(luaCtx, opt.child, name, data);
            } else {
                clj.lua_pushnil(luaCtx);
                clj.lua_setglobal(luaCtx, name.ptr);
            }
        },

        else => {},
    }
}

fn pushCollection(
    luaCtx: *clj.lua_State,
    tableIndex: c_int,
    T: type,
    name: []const u8,
    val: anytype,
) void {
    switch (T) {
        u8 => {
            clj.lua_pushlstring(luaCtx, name.ptr, name.len);
            clj.lua_pushlstring(luaCtx, val.ptr, val.len);
            clj.lua_settable(luaCtx, tableIndex);
        },

        else => {},
    }
}

fn pushValue(
    luaCtx: *clj.lua_State,
    tableIndex: c_int,
    T: type,
    name: []const u8,
    val: anytype,
) void {
    const TI = @typeInfo(T);

    switch (TI) {
        .bool => {
            clj.lua_pushlstring(luaCtx, name.ptr, name.len);
            clj.lua_pushboolean(luaCtx, @intFromBool(val));
            clj.lua_settable(luaCtx, tableIndex);
        },

        .int, .comptime_int => {
            clj.lua_pushlstring(luaCtx, name.ptr, name.len);
            clj.lua_pushinteger(luaCtx, val);
            clj.lua_settable(luaCtx, tableIndex);
        },

        .float, .comptime_float => {
            clj.lua_pushlstring(luaCtx, name.ptr, name.len);
            clj.lua_pushnumber(luaCtx, val);
            clj.lua_settable(luaCtx, tableIndex);
        },

        .array => |arr| {
            pushCollection(luaCtx, tableIndex, arr.child, name, val[0..arr.len]);
        },

        .pointer => |ptr| {
            switch (ptr.size) {
                .slice => {
                    pushCollection(luaCtx, tableIndex, ptr.child, name, val);
                },

                .one => {
                    const childPtrTI = @typeInfo(ptr.child);

                    switch (childPtrTI) {
                        .array => |arr| {
                            pushCollection(luaCtx, tableIndex, arr.child, name, val[0..arr.len]);
                        },

                        else => {
                            clj.lua_pushlstring(luaCtx, name.ptr, name.len);
                            clj.lua_pushlightuserdata(luaCtx, val);
                            clj.lua_settable(luaCtx, tableIndex);
                        },
                    }
                },

                else => {},
            }
        },

        .optional => |opt| {
            if (val) |data| {
                pushValue(luaCtx, tableIndex, opt.child, name, data);
            } else {
                clj.lua_pushlstring(luaCtx, name.ptr, name.len);
                clj.lua_pushnil(luaCtx);
                clj.lua_settable(luaCtx, tableIndex);
            }
        },

        else => {},
    }
}

fn pushStruct(
    luaCtx: *clj.lua_State,
    tableIndex: c_int,
    sf: std.builtin.Type.StructField,
    val: anytype,
) void {
    const TI = @typeInfo(sf.type);

    switch (TI) {
        .@"struct" => |st| {
            clj.lua_newtable(luaCtx);
            const newTableIndex = clj.lua_gettop(luaCtx);

            inline for (st.fields) |field| {
                try pushStruct(luaCtx, newTableIndex, sf, @field(val, field.name));
            }

            clj.lua_settable(luaCtx, newTableIndex);
        },

        else => {
            pushValue(luaCtx, tableIndex, sf.type, sf.name, val);
        },
    }
}

pub fn structToTable(
    luaCtx: *clj.lua_State,
    TI: std.builtin.Type,
    name: [:0]const u8,
    value: anytype,
) void {
    clj.lua_newtable(luaCtx);
    const tableIndex = clj.lua_gettop(luaCtx);

    switch (TI) {
        .@"struct" => |container| {
            inline for (container.fields) |decl| {
                const declVal = @field(value, decl.name);
                const declType = @TypeOf(declVal);
                const declTypeInfo = @typeInfo(declType);

                switch (declTypeInfo) {
                    .@"struct" => |st| {
                        clj.lua_newtable(luaCtx);
                        const newTableIndex = clj.lua_gettop(luaCtx);

                        inline for (st.fields) |field| {
                            try pushStruct(luaCtx, newTableIndex, field, @field(declVal, field.name));
                        }

                        clj.lua_settable(luaCtx, newTableIndex);
                    },

                    else => {
                        pushValue(luaCtx, tableIndex, declType, decl.name, declVal);
                    },
                }
            }
        },

        else => {},
    }

    clj.lua_setglobal(luaCtx, name.ptr);
}

pub fn containerToTable(
    luaCtx: *clj.lua_State,
    TI: std.builtin.Type,
    name: [:0]const u8,
    value: type,
) void {
    clj.lua_newtable(luaCtx);
    const tableIndex = clj.lua_gettop(luaCtx);

    switch (TI) {
        .@"struct" => |container| {
            inline for (container.decls) |decl| {
                const declVal = @field(value, decl.name);
                const declType = @TypeOf(declVal);
                const declTypeInfo = @typeInfo(declType);

                switch (declTypeInfo) {
                    .@"struct" => |st| {
                        clj.lua_newtable(luaCtx);
                        const newTableIndex = clj.lua_gettop(luaCtx);

                        inline for (st.fields) |field| {
                            try pushStruct(luaCtx, newTableIndex, field, @field(declVal, field.name));
                        }

                        clj.lua_settable(luaCtx, newTableIndex);
                    },

                    else => {
                        pushValue(luaCtx, tableIndex, declType, decl.name, declVal);
                    },
                }
            }
        },

        else => {},
    }

    clj.lua_setglobal(luaCtx, name.ptr);
}
