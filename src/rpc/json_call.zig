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

const zigjr = @import("../zigjr.zig");
const JrErrors = zigjr.JrErrors;
const DispatchResult = zigjr.DispatchResult;
const DispatchErrors = zigjr.DispatchErrors;


/// Uniform call object that can be stored in a hash map.
/// makeRpcHandler will deal with the parameter unpacking of specific function at comptime.
pub const RpcHandler = struct {
    arena: *ArenaAllocator, // arena needs to be a ptr to the struct to survive copying.
    arena_alloc: Allocator,
    context: ?*anyopaque,
    call: *const fn(context: ?*anyopaque, arena_alloc: Allocator, params_value: Value) anyerror!DispatchResult,

    /// Call the handler call fn with the JSON Value parameters.
    pub fn invoke(self: *RpcHandler, params_value: Value) anyerror!DispatchResult {
        return self.call(self.context, self.arena_alloc, params_value);
    }

    /// Call the handler call fn with the JSON string parameters, convenient method for testing.
    pub fn invokeJson(self: *RpcHandler, params_json: []const u8) anyerror!DispatchResult {
        const trimmed = std.mem.trim(u8, params_json, " ");
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
/// into a RpcHandler object. This collects all the handler function's info in comptime
/// and maps the JSON values to the function's parameters in runtime.
/// This allows dispatching a JSON-RPC call to arbitrary function (with some limitations).
///
/// The parameter types of the handler function are limited to the JSON's data types
/// - bool, i64, f64, string ([]const u8), and object (struct) - for the array based JSON-RPC parameters.
/// For an object based JSON-RPC parameter, the function parameter is the matching struct type.
/// RpcHandler will automatically convert the JSON object to the struct value at runtime.
///
/// There are a few special parameters of the handler function supported by RpcHandler.
///
/// If a context object pointer is supplied (non-null), it is passed in as the first parameter
/// to the handler function. The context object can serve as the 'self' pointer for the function.
/// The first parameter's type and the context type need to be the same.
///
/// If an Allocator parameter is declared as the first parameter of the handler function
/// (or the second parameter if a context object is supplied), an allocator is passed in
/// during invocation.  The allocator is an arena allocator so the function doesn't need
/// to worry about freeing the memory.  The arena memory can be reset via the reset() function.
/// The arena memory is reset for each dispatch() by higher level callers.
///
/// If std.json.Value is declared as a single parameter of the handler function,
/// the JSON-RPC parameters are passed in as a Value object without any interpretation.
/// It's up to the function to interpret the value types and extract the value data.
/// e.g. fn h1(a: Value).
///
/// If std.json.Values are declared as part of the parameters of the handler function,
/// the JSON-RPC parameters of the correponding Value type function parameters are passed in
/// as Value objects without any interpretation. e.g. fn h3(a: Value, b: i64, c: Value).
///
/// The return type of handler function can be void, JsonStr, or any type that can be
/// stringified to JSON.  The function can just return a value and it will be automatically
/// stringified to JSON.  If the function has already built its own JSON string, it can
/// return it in a JsonStr struct, which prevents it from being stringified again.
/// 
pub fn makeRpcHandler(context: anytype, comptime F: anytype, backing_alloc: Allocator) !RpcHandler {
    const hinfo = getHandlerInfo(F, context);
    try validateHandler(hinfo);

    const wrapper = struct {
        fn call(ctx: ?*anyopaque, arena_alloc: Allocator, params_value: Value) anyerror!DispatchResult {
            // Function expects a single Value or a single struct object.
            if (hinfo.is_value1) {
                return callOnValue(F, hinfo, ctx, arena_alloc, params_value);
            } else if (hinfo.is_obj1) {
                return callOnObject(F, hinfo, ctx, arena_alloc, params_value);
            }
            // Function expects no parameter or an array of parameters.
            switch (params_value) {
                .null   => {
                    return callOnArray(F, hinfo, ctx, arena_alloc, Array.init(arena_alloc));
                },
                .array  => {
                    return callOnArray(F, hinfo, ctx, arena_alloc, params_value.array);
                },
                .bool, .integer, .float, .string => {
                    // JSON-RPC spec doesn't support primitive JSON types for the "params" property.
                    // Add them here for completeness.
                    return callOnPrimitive(F, hinfo, ctx, arena_alloc, params_value);
                },
                else    => {
                    std.debug.print("Unexpected JSON params: {any}\n", .{params_value});
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

/// Wrapper struct on a JSON string, for tagging a string with JSON data.
pub const JsonStr = struct {
    json:   []const u8
};

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
    is_optional1:   bool,                   // The only user parameter is optional, for optional "params" in a request.
    has_ret_err:    bool,                   // The function has a error union in the return type.
    is_ret_void:    bool,                   // The function has a void return type.
    is_ret_json:    bool,                   // The function has a JsonStr return type.
    is_ret_dresult: bool,                   // The function has a DispatchResult return type.
};

// Note: the following functions must be inline to force evaluation in comptime for makeRpcHandler.

pub inline fn getHandlerInfo(comptime handler_fn: anytype, context: anytype) HandlerInfo {
    const fn_info       = getFnInfo(handler_fn);
    const params        = fn_info.params;
    const ctx_type      = @TypeOf(context);
    const has_ctx       = ctx_type != void and ctx_type != *void;
    const alloc_idx     = if (has_ctx) 1 else 0;                // the alloc param index is after ctx
    const has_alloc     = params.len > alloc_idx and params[alloc_idx].type.? == std.mem.Allocator;
    const user_idx      = alloc_idx + if (has_alloc) 1 else 0;  // index of the first user param.
    const is_value1     = params.len == user_idx + 1 and isValue(params[user_idx].type);
    const is_struct     = params.len == user_idx + 1 and isStruct(params[user_idx].type);
    const is_optional1  = params.len == user_idx + 1 and isOptional(params[user_idx].type);
    const is_obj1       = is_struct and !is_value1;
    const obj1_type     = if (is_obj1) params[user_idx].type.? else void;

    return .{
        .fn_info        = fn_info,
        .params         = params,
        .tuple_type     = ArgsTupleType(params),
        .ctx_type       = ctx_type,
        .has_ctx        = has_ctx,
        .has_alloc      = has_alloc,
        .user_idx       = user_idx,
        .is_value1      = is_value1,
        .is_obj1        = is_obj1,
        .obj1_type      = obj1_type,
        .is_optional1   = is_optional1,
        .has_ret_err    = isErrorUnion(fn_info.return_type),
        .is_ret_void    = isVoid(fn_info.return_type),
        .is_ret_json    = isReturnType(fn_info.return_type, JsonStr),
        .is_ret_dresult = isReturnType(fn_info.return_type, DispatchResult),
    };
}

/// Make a tuple type from the parameters of a function.
/// Each parameter becomes a field of the tuple.
inline fn ArgsTupleType(comptime params: []const Type.Fn.Param) type {
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

    // Create the tuple type. A tuple is a struct with is_tuple set.
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
    const t_info: Type = @typeInfo(@TypeOf(handler_fn));
    return switch (t_info) {
        .@"fn"  => |info_fn| info_fn,
        else    => @compileError("handler_fn must be a function.  Got: " ++ @typeName(handler_fn)),
    };
}

inline fn getReturnType(comptime T: ?type) ?type {
    if (T)|t| {
        const t_info: Type = @typeInfo(t);
        switch (t_info) {
            .error_union => |eu| return eu.payload, // get the type wrapped in the error union.
            else => return t,
        }
    }
    return null;
}

inline fn isVoid(comptime FT: ?type) bool {
    return getReturnType(FT) == void;
}

inline fn isReturnType(comptime FT: ?type, comptime return_type: type) bool {
    return getReturnType(FT) == return_type;
}

inline fn isErrorUnion(comptime T: ?type) bool {
    if (T)|t| {
        const t_info: Type = @typeInfo(t);
        return t_info == .error_union;      // e.g., !void, !u8, or FooErrorSet!void
    } else {
        return false;
    }
}

inline fn isOptional(comptime T: ?type) bool {
    if (T) |t| {
        const t_info: Type = @typeInfo(t);
        return t_info == .optional;
    } else {
        return false;
    }
}

inline fn unwrapOptionalType(comptime T: ?type) ?type {
    if (T) |t| {
        const t_info: Type = @typeInfo(t);
        return if (t_info == .optional) t_info.optional.child else t;
    } else {
        return null;
    }
}

inline fn isValue(comptime T: ?type) bool {
    return unwrapOptionalType(T) == std.json.Value;
}

inline fn isStruct(comptime T: ?type) bool {
    if (unwrapOptionalType(T)) |t| {
        const t_info: Type = @typeInfo(t);
        return t_info == .@"struct";
    } else {
        return false;
    }
}

fn callOnPrimitive(comptime F: anytype, comptime hinfo: HandlerInfo, ctx: ?*anyopaque, alloc: Allocator,
                   json_primitive: Value) anyerror!DispatchResult {
    // @compileLog(F);

    if (hinfo.params.len != hinfo.user_idx + 1) {
        std.debug.print("hinfo.params.len: {}, hinfo.user_idx + 1: {}\n", .{hinfo.params.len, hinfo.user_idx + 1});
        return DispatchErrors.MismatchedParamCounts;
    }

    // Pack the JSON param into a tuple for F's params.
    const args: hinfo.tuple_type = try primitiveToTuple(hinfo, ctx, alloc, json_primitive);
    return callF(F, hinfo, args, alloc);
}

fn callOnValue(comptime F: anytype, comptime hinfo: HandlerInfo, ctx: ?*anyopaque, alloc: Allocator,
               params_value: Value) anyerror!DispatchResult {

    if (hinfo.params.len != hinfo.user_idx + 1) {
        std.debug.print("hinfo.params.len: {}, hinfo.user_idx + 1: {}\n", .{hinfo.params.len, hinfo.user_idx + 1});
        return DispatchErrors.MismatchedParamCounts;
    }

    // Pack the JSON params into a tuple for F's params.
    const args: hinfo.tuple_type = jsonValueToTuple(hinfo, ctx, alloc, params_value);
    return callF(F, hinfo, args, alloc);
}

fn callOnObject(comptime F: anytype, comptime hinfo: HandlerInfo, ctx: ?*anyopaque, alloc: Allocator,
                params_value: Value) anyerror!DispatchResult {
    if (hinfo.params.len != hinfo.user_idx + 1) {
        std.debug.print("hinfo.params.len: {}, hinfo.user_idx + 1: {}\n", .{hinfo.params.len, hinfo.user_idx + 1});
        return DispatchErrors.MismatchedParamCounts;
    }

    if (hinfo.is_optional1 and (isNull(params_value) or isEmptyArray(params_value))) {
        const args: hinfo.tuple_type = objectToTuple(hinfo, ctx, alloc, null);
        return callF(F, hinfo, args, alloc);
    }
    if (params_value != .object) {
        std.debug.print("Expecting an Value(.object) but got unexpected JSON params: {any}\n", .{params_value});
        return DispatchErrors.InvalidParams;
    }

    // Map the incoming Value (.object) into a struct object.
    // Alloc is an arena allocator; don't need to free the parsed result here.
    const parsed = try std.json.parseFromValue(hinfo.obj1_type, alloc, params_value, .{});
    const obj1: hinfo.obj1_type = parsed.value;

    // Pack JSON array params into a tuple for F's params.
    const args: hinfo.tuple_type = objectToTuple(hinfo, ctx, alloc, obj1);
    return callF(F, hinfo, args, alloc);
}

fn callOnArray(comptime F: anytype, comptime hinfo: HandlerInfo, ctx: ?*anyopaque, alloc: Allocator,
               array: Array) anyerror!DispatchResult {
    if (hinfo.is_optional1 and array.items.len == 0) {
        var nullArray = Array.init(alloc);
        try nullArray.append( .{ .null = {} } );
        const args: hinfo.tuple_type = try arrayToTuple(hinfo, ctx, alloc, nullArray);
        return callF(F, hinfo, args, alloc);
    }

    if (hinfo.params.len != hinfo.user_idx + array.items.len) {
        return DispatchErrors.MismatchedParamCounts;
    }

    // Pack the JSON array params into a tuple for F's params.
    const args: hinfo.tuple_type = try arrayToTuple(hinfo, ctx, alloc, array);
    return callF(F, hinfo, args, alloc);
}

// Finally calling the function with the args. Pack its result into DispatchResult.
fn callF(comptime F: anytype, comptime hinfo: HandlerInfo, args: hinfo.tuple_type,
         alloc: Allocator) anyerror!DispatchResult {
    if (hinfo.is_ret_void) {
        if (hinfo.has_ret_err) {
            try @call(.auto, F, args);
        } else {
            @call(.auto, F, args);
        }
        return DispatchResult.asNone();
    } else {
        if (hinfo.has_ret_err) {
            const result = @call(.auto, F, args) catch |e| return e;
            return toDispatchResult(hinfo, alloc, result);
        } else {
            const result = @call(.auto, F, args);
            return toDispatchResult(hinfo, alloc, result);
        }
    }
}

fn toDispatchResult(comptime hinfo: HandlerInfo, alloc: Allocator, result: anytype) DispatchErrors!DispatchResult {
    if (hinfo.is_ret_json) {
        // result is a JsonStr; return the JSON string.
        return DispatchResult.withResult(result.json);
    } else if (hinfo.is_ret_dresult) {
        // result is already a DispatchResult; just return it.
        return result;
    } else {
        // wrap the result in a JSON.
        const json = try std.json.Stringify.valueAlloc(alloc, result, .{});
        return DispatchResult.withResult(json);
    }
}

fn initArgsTuple(comptime hinfo: HandlerInfo, ctx: ?*anyopaque, alloc: Allocator) hinfo.tuple_type {
    var tuple: hinfo.tuple_type = undefined;

    // Assign the context and alloc to the appropriate function argument slots in the tuple.
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
    return tuple;
}

fn jsonValueToTuple(comptime hinfo: HandlerInfo, ctx: ?*anyopaque, alloc: Allocator,
                    value: Value) hinfo.tuple_type {
    var tuple: hinfo.tuple_type = initArgsTuple(hinfo, ctx, alloc);
    const tt_info = @typeInfo(hinfo.tuple_type).@"struct";
    const t_field = tt_info.fields[hinfo.user_idx];
    @field(tuple, t_field.name) = value;        // Value for the single argument.
    return tuple;
}

fn primitiveToTuple(comptime hinfo: HandlerInfo, ctx: ?*anyopaque, alloc: Allocator,
                    primitive_value: Value) !hinfo.tuple_type {

    var tuple: hinfo.tuple_type = initArgsTuple(hinfo, ctx, alloc);
    const tt_info = @typeInfo(hinfo.tuple_type).@"struct";
    const t_field = tt_info.fields[hinfo.user_idx];
    const value = try ValueAs(t_field.type).from(primitive_value);
    @field(tuple, t_field.name) = value;
    return tuple;
}

fn arrayToTuple(comptime hinfo: HandlerInfo, ctx: ?*anyopaque, alloc: Allocator,
                values: Array) !hinfo.tuple_type {
    var tuple: hinfo.tuple_type = initArgsTuple(hinfo, ctx, alloc);
    const tt_info = @typeInfo(hinfo.tuple_type).@"struct";
    const start_idx = hinfo.user_idx;
    // Fill in the rest of the user specific parameters.
    inline for (start_idx..tt_info.fields.len) |i| {
        const t_field = tt_info.fields[i];
        const j_value = values.items[i - start_idx];
        if (isValue(t_field.type)) {
            @field(tuple, t_field.name) = j_value;
        } else if (isStruct(t_field.type)) {
            const parsed = try std.json.parseFromValue(t_field.type, alloc, j_value, .{});
            @field(tuple, t_field.name) = parsed.value;
        // } else if (isArray(t_field.type)) {
        //     // TODO: handle Array function paramenter.
        } else {
            @field(tuple, t_field.name) = try ValueAs(t_field.type).from(j_value);
        }
    }
    return tuple;
}

// For optional paramenter, hinfo.obj1_type already has the optional type.
fn objectToTuple(comptime hinfo: HandlerInfo, ctx: ?*anyopaque, alloc: Allocator,
                 object: hinfo.obj1_type) hinfo.tuple_type {
    var tuple: hinfo.tuple_type = initArgsTuple(hinfo, ctx, alloc);
    const tt_info = @typeInfo(hinfo.tuple_type).@"struct";
    const t_field = tt_info.fields[hinfo.user_idx];
    @field(tuple, t_field.name) = object;
    return tuple;
}

/// Convert the std.json.Value to the primitive type (bool, i64, f64, []const u8),
/// within the scope of JSON data type.
fn ValueAs(comptime ParamType: type) type {
    const is_optional = @typeInfo(ParamType) == .optional;
    const OParamType = unwrapOptionalType(ParamType).?;
    const pt_info = @typeInfo(OParamType);

    // Validate supported primitive types for parameter value.
    validateSupportedPrimitiveTypes(pt_info);

    return struct {
        pub fn from(json_value: Value) !ParamType {
            return fromAlloc(json_value, .{});
        }

        pub fn fromAlloc(json_value: Value, opts: struct { alloc: ?Allocator = null }) !ParamType {
            if (is_optional and isNull(json_value)) {
                return null;
            }

            switch (pt_info) {
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

fn validateSupportedPrimitiveTypes(comptime paramType: std.builtin.Type) void {
    switch (paramType) {
        .bool => {},
        .int => {
            if (paramType.int.signedness == .unsigned)
                @compileError("Required signed integer, at least i64.");
            if (paramType.int.bits < 64)
                @compileError("Required at least i64 for integer.");
        },
        .float => {
            if (paramType.float.bits < 64)
                @compileError("Required at least f64 for floating point number.");
        },
        .pointer => |ptr| {
            if (ptr.child != u8)
                @compileError("String slice requires the '[]const u8' type.");
        },
        else => {
            @compileError(std.fmt.comptimePrint("Unsupported primitive parameter type: {any}", .{paramType}));
        }
    }
}

fn isNull(params_value: Value) bool {
    return params_value == .null;
}

fn isEmptyArray(params_value: Value) bool {
    return params_value == .array and params_value.array.items.len == 0;
}


test "Test simple JSON value conversion." {
    var gpa = std.heap.DebugAllocator(.{}){};
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
    var gpa = std.heap.DebugAllocator(.{}){};
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
    var gpa = std.heap.DebugAllocator(.{}){};
    const alloc = gpa.allocator();
    {
        const x = try ValueAs([]const u8).fromAlloc(.{ .string = "hello" }, .{ .alloc = alloc });
        try testing.expectEqualSlices(u8, x, "hello");

        try testing.expectEqual(ValueAs(i64).fromAlloc(.{ .integer = 10 }, .{ .alloc = alloc }), 10);
        
        alloc.free(x);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}


