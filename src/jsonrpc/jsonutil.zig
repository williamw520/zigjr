// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const Type = std.builtin.Type;
const Allocator = std.mem.Allocator;
const StringHashMap = std.hash_map.StringHashMap;
const AutoHashMap = std.hash_map.AutoHashMap;
const allocPrint = std.fmt.allocPrint;
const Value = std.json.Value;
const Array = std.json.Array;
const ObjectMap = std.json.ObjectMap;

const errors = @import("errors.zig");
const ErrorCode = errors.ErrorCode;
const JrErrors = errors.JrErrors;


pub fn ValueAs(comptime V: type) type {
    const vinfo = @typeInfo(V);

    // Check for supported parameter value types.
    switch (vinfo) {
        .bool => {},
        .int => {
            if (vinfo.int.signedness == .unsigned) @compileError("Required signed integer, at least i64.");
            if (vinfo.int.bits < 64) @compileError("Required at least i64 for integer.");
        },
        .float => {
            if (vinfo.float.bits < 64) @compileError("Required at least f64 for floating point number.");
        },
        .pointer => {
            if (vinfo.pointer.child != u8)
                @compileError("String slice requires the '[]const u8' type.");
        },
        else => @compileError("Unsupported parameter value type."),
    }

    return struct {
        pub fn from(json_value: Value) !V {
            return fromAlloc(json_value, .{});
        }

        pub fn fromAlloc(json_value: Value, opts: struct { alloc: ?Allocator = null }) !V {
            switch (vinfo) {
                .bool => switch (json_value) {
                    .bool       => |x| return x,
                    .integer    => |x| return x != 0,
                    .float      => |x| return x != 0.0,
                    .string     => |x| return std.mem.eql(u8, x, "true"),
                    else        => return JrErrors.InvalidJsonValueType,
                },
                .int => switch (json_value) {
                    .integer    => |x| return x,
                    .string     => |x| return try std.fmt.parseInt(i64, x, 10),
                    else        => return JrErrors.InvalidJsonValueType,
                },
                .float => switch (json_value) {
                    .float      => |x| return x,
                    .integer    => |x| return @as(f64, @floatFromInt(x)),
                    .string     => |x| return try std.fmt.parseFloat(f64, x),
                    else        => return JrErrors.InvalidJsonValueType,
                },
                .pointer => {
                    if (opts.alloc) |alloc| {
                        switch (json_value) {
                            .bool       => |x| return try allocPrint(alloc, "{}", .{x}),
                            .integer    => |x| return try allocPrint(alloc, "{}", .{x}),
                            .float      => |x| return try allocPrint(alloc, "{}", .{x}),
                            .string     => |x| return try allocPrint(alloc, "{s}", .{x}),
                            else        => return JrErrors.InvalidJsonValueType,
                        }
                    } else {
                        switch (json_value) {
                            .string     => |x| return x,
                            else        => return JrErrors.InvalidJsonValueType,
                        }
                    }
                },
                else => return JrErrors.InvalidParamType,
            }
        }
        
    };

}

/// Make a tuple type from the parameters of the function.
/// Each parameter becomes a field of the tuple.
pub fn ParamTupleType(comptime func: anytype) type {
    const fn_info = @typeInfo(@TypeOf(func)).@"fn";

    comptime var fields: [fn_info.params.len]std.builtin.Type.StructField = undefined;
    inline for (fn_info.params, 0..)|param, i| {
        fields[i] = .{
            .name = std.fmt.comptimePrint("{d}", .{i}),
            .type = param.type orelse null,
            .is_comptime = false,   // make all the fields not comptime to allow mutable tuple.
            .default_value_ptr = null,
            .alignment = 0,
        };
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = fields[0..],
            .decls = &.{},
            .is_tuple = true,
        },
    });
}

/// Make a tuple type from the parameters of the function.
/// Each parameter becomes a field of the tuple.
pub fn ParamTupleType2(comptime func: anytype) type {
    const fn_info = @typeInfo(@TypeOf(func)).@"fn";

    comptime var fields: [1 + fn_info.params.len]std.builtin.Type.StructField = undefined;

    fields[0] = .{
        .name = "0",
        .type = Allocator,
        .is_comptime = false,
        .default_value_ptr = null,
        .alignment = 0,
    };
    
    inline for (fn_info.params, 0..)|param, i| {
        fields[i+1] = .{
            .name = std.fmt.comptimePrint("{d}", .{i+1}),
            .type = param.type orelse null,
            .is_comptime = false,   // make all the fields not comptime to allow mutable tuple.
            .default_value_ptr = null,
            .alignment = 0,
        };
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = fields[0..],
            .decls = &.{},
            .is_tuple = true,
        },
    });
}

pub fn valuesToTuple(comptime tuple_type: type, values: Array) !tuple_type {
    const tt_info = @typeInfo(tuple_type).@"struct";
    var tuple: tuple_type = undefined;
    inline for (tt_info.fields, 0..)|field, i| {
        const value = values.items[i];
        // std.debug.print("@\"{d}\"| field: {any} | arg: {any}\n", .{i, field, value});
        @field(tuple, field.name) = try ValueAs(field.type).from(value);
    }
    return tuple;
}

pub fn valuesToTuple2(comptime tuple_type: type, alloc: Allocator, values: Array) !tuple_type {
    const tt_info = @typeInfo(tuple_type).@"struct";
    var tuple: tuple_type = undefined;
    @field(tuple, "0") = alloc;
    inline for (1..tt_info.fields.len)|i| {
        const field = tt_info.fields[i];
        const value = values.items[i-1];
        // std.debug.print("@\"{d}\"| field: {any} | arg: {any}\n", .{i, field, value});
        @field(tuple, field.name) = try ValueAs(field.type).from(value);
    }
    return tuple;
}

pub fn Fn2(comptime P1: type, comptime P2: type, callback: anytype) type {
    return struct {
        pub fn callWith(v1: Value, v2: Value) ![]const u8 {
            const x1 = try ValueAs(P1).from(v1);
            const x2 = try ValueAs(P2).from(v2);
            return try callback.run(x1, x2);
        }
    };
}

pub fn Fn3(comptime P1: type, comptime P2: type, comptime P3: type, callback: anytype) type {
    return struct {
        pub fn callWith(v1: Value, v2: Value, v3: Value) ![]const u8 {
            const x1 = try ValueAs(P1).from(v1);
            const x2 = try ValueAs(P2).from(v2);
            const x3 = try ValueAs(P3).from(v3);
            return try callback.run(x1, x2, x3);
        }
    };
}

// Uniform callback object that can be stored in the hash map.
// makeCallable will deal with the parameter unpacking of specific function at comptime.
pub const Callable = struct {
    context: *anyopaque,
    call: *const fn(context: *anyopaque, alloc: Allocator, json_args: Value) anyerror![]const u8,

    pub fn invoke(self: Callable, alloc: Allocator, json_args: Value) anyerror![]const u8 {
        return self.call(self.context, alloc, json_args);
    }

    pub fn deinit(self: Callable, allocator: Allocator) void {
        _=self;
        _=allocator;
    }
};

pub fn makeCallable(comptime F: anytype) Callable {
    // const param_ttype = ParamTupleType(F);
    const param_ttype = ParamTupleType(F);

    return .{
        .context = "",
        .call = &struct {
            // This is the actual runtime wrapper that gets called.
            fn call_wrapper(context: *anyopaque, alloc: Allocator, json_args: Value) anyerror![]const u8 {
                _ = context;
                // _ = alloc;
                const args_tuple = try valuesToTuple2(param_ttype, alloc, json_args.array);
                return @call(.auto, F, args_tuple);
            }
        }.call_wrapper,
    };
}


