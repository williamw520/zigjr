// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William W. Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const Type = std.builtin.Type;
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const allocPrint = std.fmt.allocPrint;
const Value = std.json.Value;
const Array = std.json.Array;
const ObjectMap = std.json.ObjectMap;

const zigjr = @import("../zigjr.zig");
const JrErrors = zigjr.JrErrors;
const DispatchResult = zigjr.DispatchResult;
const DispatchErrors = zigjr.DispatchErrors;


/// Uniform callback object that can be stored in a hash map.
/// makeRpcHandler will deal with the parameter unpacking of specific function at comptime.
pub const RpcHandler = struct {
    arena: *ArenaAllocator, // arena needs to be a ptr to the struct to survive copying.
    arena_alloc: Allocator,
    context: ?*anyopaque,
    call: *const fn(context: ?*anyopaque, arena_alloc: Allocator, value_args: Value) anyerror!DispatchResult,

    /// Call the handler callback fn with the arguments in the JSON value.
    pub fn invoke(self: *RpcHandler, value_args: Value) anyerror!DispatchResult {
        return self.call(self.context, self.arena_alloc, value_args);
    }

    /// Call the handler callback fn with the arguments in the JSON string.
    pub fn invokeJson(self: *RpcHandler, json_args: []const u8) anyerror!DispatchResult {
        const trimmed = std.mem.trim(u8, json_args, " ");
        if (trimmed.len == 0) {
            return self.call(self.context, self.arena_alloc, .{ .null = {} });
        } else {
            const parsed = try std.json.parseFromSlice(Value, self.arena_alloc, trimmed, .{});
            defer parsed.deinit();
            return self.call(self.context, self.arena_alloc, parsed.value);
        }
    }

    /// Reset arena memory accumulated at each invoke()/invokeJson() call.
    /// The frequency of reset is up to the caller. It can be for each invoke() or batched up.
    pub fn reset(self: *RpcHandler) void {
        _ = self.arena.reset(.{ .retain_with_limit = 1024 });
    }

    pub fn deinit(self: *RpcHandler) void {
        self.arena.deinit();
        const backing_alloc = self.arena.child_allocator;
        backing_alloc.destroy(self.arena);
    }
};

/// Package a context, a function, its parameters, its return type, and its return error type
/// into a RpcHandler object. This collects all the handler function's info in comptime,
/// and maps the JSON values to the function's parameters in runtime.
/// This allows dispatching a JSON-RPC call to arbitrary function (with some limitations).
///
/// The parameter types of the handler function are limited to the JSON's data types
/// - bool, i64, f64, string ([]const u8), and object (struct) - for the array based JSON-RPC parameters.
/// For an object map based JSON-RPC parameter, the function parameter can be a struct type.
/// RpcHandler will automatically convert the JSON ObjectMap to the struct value.
///
/// The return type of handler function can be any type that can be stringified to JSON.
/// Note that some types are converted to the JSON's data types in the result.
///
/// There are a few special parameters of the handler function supported by RpcHandler.
///
/// If the context object pointer is supplied (non-null), it is passed in as the first parameter
/// to the handler function. The context object can serve as the 'self' pointer for the function.
/// The parameter type and the context type need to be the same.
///
/// If an Allocator parameter is declared as the first parameter of the handler function
/// (or the second parameter if a context object is supplied), an allocator is passed in
/// during invocation.  The allocator is an arena allocator so the function doesn't need
/// to worry about freeing the memory.  The arena memory can be reset via the reset() function.
///
/// If std.json.Value is declared as a single parameter of the handler function,
/// the JSON-RPC parameters are passed in as a Value object without any interpretation.
/// It's up to the function to handle the data and types in the Value object.
/// e.g. fn h1(a: Value).
///
/// If std.json.Values are declared as part of the parameters of the handler function,
/// the JSON-RPC parameters of the correponding Value type function parameters are passed in
/// as a Value object without any interpretation. e.g. fn h3(a: Value, b: i64, c: Value).
///
pub fn makeRpcHandler(context: anytype, comptime F: anytype, backing_alloc: Allocator) !RpcHandler {
    const hinfo = getHandlerInfo(F, context);
    try validateHandler(hinfo);

    const wrapper = struct {
        fn call(ctx: ?*anyopaque, arena_alloc: Allocator, value_args: Value) anyerror!DispatchResult {
            if (hinfo.is_value1) {
                return callOnValue(F, hinfo, ctx, arena_alloc, value_args);
            } else if (hinfo.is_obj1) {
                return callOnObject(F, hinfo, ctx, arena_alloc, value_args);
            }
            switch (value_args) {
                .null   => return callOnArray(F, hinfo, ctx, arena_alloc, Array.init(arena_alloc)),
                .array  => return callOnArray(F, hinfo, ctx, arena_alloc, value_args.array),
                .bool, .integer, .float, .string => {
                    // JSON-RPC spec doesn't support primitive JSON types for the "params" property.
                    // Add them here for completeness.
                    return callOnPrimitive(F, hinfo, ctx, arena_alloc, value_args);
                },
                else    => {
                    std.debug.print("Unexpected JSON params: {any}\n", .{value_args});
                    return DispatchErrors.InvalidParams;
                },
            }
        }
    };

    const arena_ptr = try backing_alloc.create(ArenaAllocator);
    arena_ptr.* = ArenaAllocator.init(backing_alloc);
    return .{
        .arena = arena_ptr,
        .arena_alloc = arena_ptr.allocator(),
        .context = if (hinfo.has_ctx) context else null,
        .call = wrapper.call,
    };
}

fn validateHandler(comptime hinfo: HandlerInfo) !void {
    _=hinfo;
}

// Note: the following functions must be inline to force evaluation in comptime for makeRpcHandler.

// This is a comptime struct capturing the needed comptime info to do the call on the handler.
const HandlerInfo = struct {
    ctx_type:       type,                   // The type of the context object (the self pointer type).
    fn_info:        Type.Fn,                // Info on the handler function.
    params:         []const Type.Fn.Param,  // The parameter array of the handler function.
    tuple_type:     type,                   // The type of parameter tuple for calling the handler function.
    has_ctx:        bool,                   // Handler is registered with a context object.
    has_alloc:      bool,                   // The first parameter of the handler is an Allocator.
    user_idx:       usize,                  // The index of the first user parameter of the handler.
    is_value1:      bool,                   // The only user parameter is a std.json.Value.
    is_obj1:        bool,                   // The only user parameter is an object of a struct type.
    obj1_type:      type,                   // The struct type of the object.
    has_err:        bool,                   // The handler function has a error union in the return type.
    is_void:        bool,                   // The handler function has a void return type.
};

inline fn getHandlerInfo(comptime handler_fn: anytype, context: anytype) HandlerInfo {
    const fn_info   = getFnInfo(handler_fn);
    const params    = fn_info.params;
    const ctx_type  = @TypeOf(context);
    const has_ctx   = ctx_type != void and ctx_type != *void;
    const alloc_idx = if (has_ctx) 1 else 0;                // alloc parameter index is after context
    const has_alloc = params.len > alloc_idx and params[alloc_idx].type.? == std.mem.Allocator;
    const user_idx  = alloc_idx + if (has_alloc) 1 else 0;  // index of the first user parameter.
    const is_value1 = params.len == user_idx + 1 and isValue(params[user_idx].type);
    const is_obj1   = params.len == user_idx + 1 and isStruct(params[user_idx].type);
    const obj1_type = if (is_obj1) params[user_idx].type.? else void;

    return .{
        .fn_info    = fn_info,
        .params     = params,
        .tuple_type = ParamTupleType(params),
        .ctx_type   = ctx_type,
        .has_ctx    = has_ctx,
        .has_alloc  = has_alloc,
        .user_idx   = user_idx,
        .is_value1  = is_value1,
        .is_obj1    = is_obj1,
        .obj1_type  = obj1_type,
        .has_err    = isErrorUnion(fn_info.return_type),
        .is_void    = isVoid(fn_info.return_type),
    };
}

/// Make a tuple type from the parameters of a function.
/// Each parameter becomes a field of the tuple.
inline fn ParamTupleType(comptime params: []const Type.Fn.Param) type {
    comptime var fields: [params.len]std.builtin.Type.StructField = undefined;
    inline for (params, 0..)|param, i| {
        fields[i] = .{
            .name = std.fmt.comptimePrint("{d}", .{i}),
            .type = param.type orelse null,
            .is_comptime = false,   // make all the fields not comptime to allow mutable tuple.
            .default_value_ptr = null,
            .alignment = 0,
        };
    }

    // Create the tuple type. A tuple is a struct the is_tuple set.
    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = fields[0..],
            .decls = &.{},
            .is_tuple = true,
        },
    });
}

inline fn getFnInfo(comptime handler_fn: anytype) Type.Fn {
    const type_info: Type = @typeInfo(@TypeOf(handler_fn));
    return switch (type_info) {
        .@"fn"  => |info_fn| info_fn,
        else    => @compileError("handler_fn must be a function.  Got: " ++ @typeName(handler_fn)),
    };
}

inline fn getReturnType(comptime T: ?type) ?type {
    if (T)|t| {
        const type_info: Type = @typeInfo(t);
        switch (type_info) {
            .error_union => |eu| return eu.payload, // get the type wrapped in the error union.
            else => return t,
        }
    }
    return null;
}

inline fn isVoid(comptime T: ?type) bool {
    return getReturnType(T) == void;
}

inline fn isErrorUnion(comptime T: ?type) bool {
    if (T)|t| {
        const type_info = @typeInfo(t);
        switch (type_info) {
            .error_union => return true,    // e.g., !void, !u8, or FooErrorSet!void
            else => return false,
        }
    } else {
        return false;
    }
}

inline fn isValue(comptime T: ?type) bool {
    if (T)|t| {
        return t == std.json.Value;
    } else {
        return false;
    }
}

inline fn isStruct(comptime T: ?type) bool {
    if (T)|t| {
        if (t == std.json.Value)
            return false;       // Skip Value type.  Value parameter has special treatment.
        const type_info: Type = @typeInfo(t);
        switch (type_info) {
            .@"struct" =>   return true,
            else =>         return false,
        }
    } else {
        return false;
    }
}

fn callOnPrimitive(comptime F: anytype, comptime hinfo: HandlerInfo, ctx: ?*anyopaque, alloc: Allocator,
                   json_primitive: Value) anyerror!DispatchResult {
    // @compileLog(F);

    if (hinfo.params.len != hinfo.user_idx + 1)
        return DispatchErrors.MismatchedParamCounts;

    // Pack the JSON param to a tuple for the F's params.
    const args: hinfo.tuple_type = try primitiveToTuple(hinfo, ctx, alloc, json_primitive);
    return callF(F, hinfo, args, alloc);
}

fn callOnValue(comptime F: anytype, comptime hinfo: HandlerInfo, ctx: ?*anyopaque, alloc: Allocator,
               value_args: Value) anyerror!DispatchResult {

    if (hinfo.params.len != hinfo.user_idx + 1)
        return DispatchErrors.MismatchedParamCounts;

    // Pack the JSON params to a tuple for the F's params.
    const args: hinfo.tuple_type = jsonValueToTuple(hinfo, ctx, alloc, value_args);
    return callF(F, hinfo, args, alloc);
}

fn callOnObject(comptime F: anytype, comptime hinfo: HandlerInfo, ctx: ?*anyopaque, alloc: Allocator,
                obj_map: Value) anyerror!DispatchResult {

    if (hinfo.params.len != hinfo.user_idx + 1)
        return DispatchErrors.MismatchedParamCounts;

    // Map the incoming JSON value into a struct object.
    // Alloc is an arena allocator; don't need to free the parsed result here.
    const parsed = try std.json.parseFromValue(hinfo.obj1_type, alloc, obj_map, .{});
    const obj: hinfo.obj1_type = parsed.value;

    // Pack JSON array params to a tuple for the F's params.
    const args: hinfo.tuple_type = objToTuple(hinfo, ctx, alloc, obj);
    return callF(F, hinfo, args, alloc);
}

fn callOnArray(comptime F: anytype, comptime hinfo: HandlerInfo, ctx: ?*anyopaque, alloc: Allocator,
               array: Array) anyerror!DispatchResult {

    if (hinfo.params.len != hinfo.user_idx + array.items.len)
        return DispatchErrors.MismatchedParamCounts;

    // Pack the JSON array params to a tuple for fn params.
    const args: hinfo.tuple_type = try valuesToTuple(hinfo, ctx, alloc, array);
    return callF(F, hinfo, args, alloc);
}

fn callF(comptime F: anytype, comptime hinfo: HandlerInfo, args: hinfo.tuple_type,
         alloc: Allocator) anyerror!DispatchResult {
    if (hinfo.is_void) {
        if (hinfo.has_err) {
            try @call(.auto, F, args);
        } else {
            @call(.auto, F, args);
        }
        return DispatchResult.asNone();
    } else {
        if (hinfo.has_err) {
            const result = try @call(.auto, F, args);
            return DispatchResult.withResult(try std.json.stringifyAlloc(alloc, result, .{}));
        } else {
            const result = @call(.auto, F, args);
            return DispatchResult.withResult(try std.json.stringifyAlloc(alloc, result, .{}));
        }
    }
}

fn jsonValueToTuple(comptime hinfo: HandlerInfo, ctx: ?*anyopaque, alloc: Allocator,
                    value: Value) hinfo.tuple_type {

    var tuple: hinfo.tuple_type = undefined;

    // Assign the context, alloc, and Value to the appropriate function parameter slots.
    if (hinfo.has_ctx) {
        const ctx_ptr: hinfo.ctx_type = @ptrCast(@alignCast(ctx.?));
        if (hinfo.has_alloc) {
            // for fn(ctx, alloc, value)
            @field(tuple, "0") = ctx_ptr;
            @field(tuple, "1") = alloc;
            @field(tuple, "2") = value;
        } else {
            // for fn(ctx, value)
            @field(tuple, "0") = ctx_ptr;
            @field(tuple, "1") = value;
        }
    } else {
        if (hinfo.has_alloc) {
            // for fn(alloc, value)
            @field(tuple, "0") = alloc;
            @field(tuple, "1") = value;
        } else {
            // for fn(value)
            @field(tuple, "0") = value;
        }
    }
    return tuple;
}

fn primitiveToTuple(comptime hinfo: HandlerInfo, ctx: ?*anyopaque, alloc: Allocator,
                    json_primitive: Value) !hinfo.tuple_type {

    var tuple: hinfo.tuple_type = undefined;
    const tt_info = @typeInfo(hinfo.tuple_type).@"struct";
    const rvalue = try ValueAs(tt_info.fields[hinfo.user_idx].type).from(json_primitive);

    // Assign the context, alloc, and primitive value to the appropriate function parameter slots.
    if (hinfo.has_ctx) {
        const ctx_ptr: hinfo.ctx_type = @ptrCast(@alignCast(ctx.?));
        if (hinfo.has_alloc) {
            // for fn(ctx, alloc, value)
            @field(tuple, "0") = ctx_ptr;
            @field(tuple, "1") = alloc;
            @field(tuple, "2") = rvalue;
        } else {
            // for fn(ctx, value)
            @field(tuple, "0") = ctx_ptr;
            @field(tuple, "1") = rvalue;
        }
    } else {
        if (hinfo.has_alloc) {
            // for fn(alloc, value)
            @field(tuple, "0") = alloc;
            @field(tuple, "1") = rvalue;
        } else {
            // for fn(value)
            @field(tuple, "0") = rvalue;
        }
    }
    return tuple;
}

fn valuesToTuple(comptime hinfo: HandlerInfo, ctx: ?*anyopaque, alloc: Allocator,
                 values: Array) !hinfo.tuple_type {
    var tuple: hinfo.tuple_type = undefined;

    if (hinfo.has_ctx) {
        const ctx_ptr: hinfo.ctx_type = @ptrCast(@alignCast(ctx.?));
        if (hinfo.has_alloc) {
            @field(tuple, "0") = ctx_ptr;
            @field(tuple, "1") = alloc;
        } else {
            @field(tuple, "0") = ctx_ptr;
        }
    } else {
        if (hinfo.has_alloc) {
            @field(tuple, "0") = alloc;
        }
    }

    const tt_info = @typeInfo(hinfo.tuple_type).@"struct";
    const start_idx = hinfo.user_idx;
    inline for (start_idx..tt_info.fields.len) |i| {
        const field = tt_info.fields[i];
        const value = values.items[i - start_idx];
        if (isValue(field.type)) {
            @field(tuple, field.name) = value;
        } else if (isStruct(field.type)) {
            const parsed = try std.json.parseFromValue(field.type, alloc, value, .{});
            @field(tuple, field.name) = parsed.value;
        } else {
            @field(tuple, field.name) = try ValueAs(field.type).from(value);
        }
    }
    return tuple;
}

fn objToTuple(comptime hinfo: HandlerInfo, ctx: ?*anyopaque, alloc: Allocator,
              obj: hinfo.obj1_type) hinfo.tuple_type {

    var tuple: hinfo.tuple_type = undefined;

    if (hinfo.has_ctx) {
        const ctx_ptr: hinfo.ctx_type = @ptrCast(@alignCast(ctx.?));
        if (hinfo.has_alloc) {
            @field(tuple, "0") = ctx_ptr;
            @field(tuple, "1") = alloc;
            @field(tuple, "2") = obj;
        } else {
            @field(tuple, "0") = ctx_ptr;
            @field(tuple, "1") = obj;
        }
    } else {
        if (hinfo.has_alloc) {
            @field(tuple, "0") = alloc;
            @field(tuple, "1") = obj;
        } else {
            @field(tuple, "0") = obj;
        }
    }
    return tuple;
}


/// Convert the std.json.Value to the primitive type (bool, i64, f64, []const u8),
/// within the scope of JSON data type.
fn ValueAs(comptime V: type) type {
    const vinfo = @typeInfo(V);

    // Check for supported parameter value types.
    switch (vinfo) {
        .bool => {},
        .int => {
            if (vinfo.int.signedness == .unsigned)
                @compileError("Required signed integer, at least i64.");
            if (vinfo.int.bits < 64)
                @compileError("Required at least i64 for integer.");
        },
        .float => {
            if (vinfo.float.bits < 64)
                @compileError("Required at least f64 for floating point number.");
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



test "Test simple JSON value conversion." {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    {
        _=alloc;
        try testing.expectEqual(ValueAs(i64).from(.{ .integer = 10 }), 10);
        try testing.expectEqual(ValueAs(i128).from(.{ .integer = 10 }), 10);

        try testing.expectEqual(ValueAs(bool).from(.{ .bool = true }), true);
        try testing.expectEqual(ValueAs(bool).from(.{ .bool = false }), false);
        try testing.expectEqual(ValueAs(bool).from(.{ .integer = 0 }), false);
        try testing.expectEqual(ValueAs(bool).from(.{ .integer = 1 }), true);
        try testing.expectEqual(ValueAs(bool).from(.{ .integer = 2 }), true);
        try testing.expectEqual(ValueAs(bool).from(.{ .integer = -2 }), true);
        try testing.expectEqual(ValueAs(bool).from(.{ .float = 0 }), false);
        try testing.expectEqual(ValueAs(bool).from(.{ .float = 1 }), true);
        try testing.expectEqual(ValueAs(bool).from(.{ .float = -1 }), true);
        try testing.expectEqual(ValueAs(bool).from(.{ .float = -1.2 }), true);

        try testing.expectEqual(ValueAs(f64).from(.{ .float = 1.2 }), 1.2);
        try testing.expectEqual(ValueAs(f64).from(.{ .float = -1.2 }), -1.2);
        try testing.expectEqual(ValueAs(f128).from(.{ .float = 10 }), 10);
        try testing.expectEqual(ValueAs(f64).from(.{ .integer = 12 }), 12);

        try testing.expectEqualSlices(u8, try ValueAs([]const u8).from(.{ .string = "hello" }), "hello");
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Test simple JSON value conversion on invalid JSON values." {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    {
        _=alloc;
        try testing.expectEqual(ValueAs(i64).from(.{ .float = 0 }), JrErrors.InvalidJsonValueType);
        try testing.expectEqual(ValueAs(i128).from(.{ .bool = true }), JrErrors.InvalidJsonValueType);
        try testing.expectEqual(ValueAs(i64).from(.{ .string = "abc" }), error.InvalidCharacter);

        try testing.expectEqual(ValueAs(f128).from(.{ .bool = true }), JrErrors.InvalidJsonValueType);
        try testing.expectEqual(ValueAs(f64).from(.{ .string = "abc" }), error.InvalidCharacter);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Test JSON value conversion with alloc." {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    {
        const x = try ValueAs([]const u8).fromAlloc(.{ .string = "hello" }, .{ .alloc = alloc });
        try testing.expectEqualSlices(u8, x, "hello");

        try testing.expectEqual(ValueAs(i64).fromAlloc(.{ .integer = 10 }, .{ .alloc = alloc }), 10);
        
        alloc.free(x);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}


