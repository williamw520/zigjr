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
const RpcRequest = zigjr.RpcRequest;
const DispatchResult = zigjr.DispatchResult;
const DispatchErrors = zigjr.DispatchErrors;

const dispatcher = @import("dispatcher.zig");
const DispatchCtxImpl = dispatcher.DispatchCtxImpl;



pub inline fn asPtr(T: type, opaque_ptr: *anyopaque) *T {
    return @as(*T, @ptrCast(@alignCast(opaque_ptr)));
}

pub inline fn asTPtr(T: type, opaque_ptr: *anyopaque) T {
    return @as(T, @ptrCast(@alignCast(opaque_ptr)));
}


/// P as the type of the user_props.
pub fn DispatchCtx(P: type) type {
    return struct {
        const Self = @This();

        dc_impl:    *DispatchCtxImpl,

        pub fn arena(self: *const Self) Allocator {
            return self.dc_impl.arena;
        }
        pub fn logger(self: *const Self) zigjr.Logger {
            return self.dc_impl.logger;
        }
        pub fn request(self: *const Self) *const zigjr.RpcRequest {
            return self.dc_impl.request;
        }
        pub fn result(self: *const Self) ?*const zigjr.DispatchResult {
            return self.dc_impl.result;
        }
        pub fn setResult(self: *Self, res: *const zigjr.DispatchResult) void {
            self.dc_impl.result = res;
        }
        pub fn props(self: *Self) *P {
            return asPtr(P, self.dc_impl.user_props);
        }
        pub fn setProps(self: *Self, p: *P) void {
            self.dc_impl.user_props = p;
        }
    };
}


/// Uniform call object that can be stored in a hash map.
/// makeRpcHandler will deal with the parameter unpacking of specific function at comptime.
/// RpcHandler and its invoke() calls are thread-safe in general; 
/// the only caveat is the user context and the user defined handler need to be thread-safe.
pub fn RpcHandler(P: type) type {
    return struct {
        const Self = @This();

        context: ?*anyopaque,
        call: *const fn(context: ?*anyopaque, cc: *DispatchCtx(P), params_value: Value) anyerror!DispatchResult,

        /// Call the handler call fn with the JSON Value parameters.
        pub fn invoke(self: *const Self, cc: *DispatchCtx(P), params_value: Value) anyerror!DispatchResult {
            return self.call(self.context, cc, params_value);
        }

        /// Call the handler call fn with the JSON string parameters, convenient method for testing.
        pub fn invokeJson(self: *const Self, cc: *DispatchCtx(P), params_json: []const u8) anyerror!DispatchResult {
            const trimmed = std.mem.trim(u8, params_json, " ");
            if (trimmed.len == 0) {
                return self.call(self.context, cc, .{ .null = {} });
            } else {
                const parsed = try std.json.parseFromSlice(Value, cc.arena(), trimmed, .{});
                defer parsed.deinit();
                return self.call(self.context, cc, parsed.value);
            }
        }
    };
}

/// Package a user context, a DispatchCtx type, a handler function along with its parameters,
/// its return type, and its return error type into a RpcHandler object.
/// This collects all the handler function's information in a comptime struct
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
/// The first parameter type of the handler function and the registered context type need to be the same.
/// The lifetime of the context object is the same as the registered handler itself, i.e.
/// it lasts for the duration of the running program. The lifetime exceeds beyond each request and each session.
///
/// If the handler function has a DispatchCtx(P) parameter as its first, second, or third parameter,
/// the dispatch context is passed in during invocation. The handler can use its functionality during the call.
/// Use DispatchCtx(P).arena allocator for any memory allocation during the request handling.
/// The arena memory will be reset at the end of the request by a higher level caller.
/// Use DispatchCtx(P).logger for logging, set up by a higher level caller.
/// DispatchCtx(P).user_data contains a user data object of type U. The user data object has a lifetime
/// of the request. It's set up by a pre-request hook and cleaned upu by a post-request hook.
///
/// (Deprecated: Use DispatchCtx(P).arena instead.) 
/// If the handler function has an Allocator parameter as its first, second, or third parameter,
/// an arena allocator is passed in during invocation. The handler can use it for memory allocation.
/// The arena memory will be reset at the end of the request by a higher level caller.
///
/// If std.json.Value is declared as a single user parameter of the handler function,
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
pub fn makeRpcHandler(context: anytype, comptime P: type, comptime F: anytype) RpcHandler(P) {
    const hinfo = getHandlerInfo(context, P, F);

    const wrapper = struct {
        fn call(ctx: ?*anyopaque, cc: *DispatchCtx(P), params_value: Value) anyerror!DispatchResult {
            // Function expects a single Value or a single struct object.
            if (hinfo.is_value1) {
                return callOnValue(F, hinfo, ctx, cc, params_value);
            } else if (hinfo.is_obj1) {
                return callOnObject(F, hinfo, ctx, cc, params_value);
            }
            // Function expects no parameter or an array of parameters.
            switch (params_value) {
                .null   => {
                    return callOnNull(F, hinfo, ctx, cc);
                },
                .array  => {
                    return callOnArray(F, hinfo, ctx, cc, params_value.array);
                },
                .bool, .integer, .float, .string => {
                    // JSON-RPC spec doesn't support primitive JSON types for the "params" property.
                    // Add them here for completeness.
                    return callOnPrimitive(F, hinfo, ctx, cc, params_value);
                },
                else    => {
                    std.debug.print("Unexpected JSON params: {any}\n", .{params_value});
                    return DispatchErrors.InvalidParams;
                },
            }
        }
    };

    return .{
        .context = if (hinfo.has_ctx()) context else null,
        .call = wrapper.call,
    };
}


/// Wrapper struct on a JSON string, for tagging a string with JSON data.
pub const JsonStr = struct {
    json:   []const u8
};

// This is a comptime struct capturing the needed comptime info to do the call on the handler.
const HandlerInfo = struct {
    DCP:            type,                   // The type of the user_props in a DispatchCtx(P).
    CTX:            type,                   // The type of the context object (the self pointer type).
    fn_info:        Type.Fn,                // Info on the handler function.
    params:         []const Type.Fn.Param,  // The parameter array of the handler function.
    tuple_type:     type,                   // The type of parameter tuple for calling the handler function.
    ctx_idx:        ?usize,
    cc_idx:         ?usize,
    alloc_idx:      ?usize,
    user_idx:       usize,                  // The index of the first user parameter of the handler.
    is_value1:      bool,                   // The only user parameter is a std.json.Value.
    is_obj1:        bool,                   // The only user parameter is an object of a struct type.
    obj1_type:      type,                   // The struct type of the object.
    is_optional1:   bool,                   // The only user parameter is optional, for optional "params" in a request.
    has_ret_err:    bool,                   // The function has a error union in the return type.
    is_ret_void:    bool,                   // The function has a void return type.
    is_ret_json:    bool,                   // The function has a JsonStr return type.
    is_ret_dresult: bool,                   // The function has a DispatchResult return type.

    // Whether the handler function has the following argument types.
    inline fn has_ctx(self: HandlerInfo) bool      { return self.ctx_idx != null; }
    inline fn has_cc(self: HandlerInfo) bool       { return self.cc_idx != null; }
    inline fn has_alloc(self: HandlerInfo) bool    { return self.alloc_idx != null; }
};

// Note: the following functions must be inline to force evaluation in comptime for makeRpcHandler.

inline fn getHandlerInfo(context: anytype, comptime P: type, comptime handler_fn: anytype) HandlerInfo {
    const fn_info       = getFnInfo(handler_fn);
    const params        = fn_info.params;
    const CTX           = @TypeOf(context);
    const ctx_idx       = typeInParams(params, CTX);
    const cc_idx        = typeInParams(params, *DispatchCtx(P));
    const alloc_idx     = typeInParams(params, std.mem.Allocator);
    const user_idx      = findUserIdx(ctx_idx, cc_idx, alloc_idx);
    const is_value1     = params.len == user_idx + 1 and isValue(params[user_idx].type);
    const is_struct     = params.len == user_idx + 1 and isStruct(params[user_idx].type);
    const is_optional1  = params.len == user_idx + 1 and isOptional(params[user_idx].type);
    const is_obj1       = is_struct and !is_value1;
    const obj1_type     = if (is_obj1) params[user_idx].type.? else void;

    return .{
        .DCP            = P,
        .CTX            = CTX,
        .fn_info        = fn_info,
        .params         = params,
        .tuple_type     = ArgsTupleType(params),
        .ctx_idx        = ctx_idx,
        .cc_idx         = cc_idx,
        .alloc_idx      = alloc_idx,
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


// Note: the following functions must be inline to force evaluation in comptime for makeRpcHandler.

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

inline fn typeInParams(comptime params: []const Type.Fn.Param, of_type: type) ?usize {
    if (params.len > 0 and params[0].type.? == of_type) return 0;
    if (params.len > 1 and params[1].type.? == of_type) return 1;
    if (params.len > 2 and params[2].type.? == of_type) return 2;
    return null;
}

inline fn findUserIdx(ctx_idx: ?usize, cc_idx: ?usize, alc_idx: ?usize) usize {
    // The user params start after the max index of any of the three arguments.
    comptime var user_idx = 0;
    if (ctx_idx)|i| { user_idx = @max(user_idx, i + 1); }
    if (cc_idx)|i|  { user_idx = @max(user_idx, i + 1); }
    if (alc_idx)|i| { user_idx = @max(user_idx, i + 1); }
    return user_idx;
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

inline fn isPointer(comptime T: ?type) bool {
    if (T) |t| {
        const t_info: Type = @typeInfo(t);
        return t_info == .pointer;
    } else {
        return false;
    }
}

inline fn unwrapPtrType(comptime T: ?type) type {
    if (T) |t| {
        const t_info: Type = @typeInfo(t);
        return if (t_info == .pointer) t_info.pointer.child else t;
    }
    return T;
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

inline fn hasField(comptime T: type, f_name: []const u8) bool {
    if (isStruct(T)) {
        comptime for (std.meta.fields(T)) |field| {
            if (std.mem.eql(u8, field.name, f_name))
                return true;
        };
    }
    return false;
}

fn callOnPrimitive(comptime F: anytype, comptime hinfo: HandlerInfo, ctx: ?*anyopaque,
                   cc: *DispatchCtx(hinfo.DCP), json_primitive: Value) anyerror!DispatchResult {
    if (hinfo.params.len != hinfo.user_idx + 1) {
        return DispatchErrors.MismatchedParamCounts;
    }

    // Pack the JSON param into a tuple for F's params.
    const args: hinfo.tuple_type = try primitiveToTuple(hinfo, ctx, cc, json_primitive);
    return callF(F, hinfo, args, cc.arena());
}

fn callOnValue(comptime F: anytype, comptime hinfo: HandlerInfo, ctx: ?*anyopaque,
               cc: *DispatchCtx(hinfo.DCP), params_value: Value) anyerror!DispatchResult {

    if (hinfo.params.len != hinfo.user_idx + 1) {
        return DispatchErrors.MismatchedParamCounts;
    }

    // Pack the JSON params into a tuple for F's params.
    const args: hinfo.tuple_type = jsonValueToTuple(hinfo, ctx, cc, params_value);
    return callF(F, hinfo, args, cc.arena());
}

fn callOnObject(comptime F: anytype, comptime hinfo: HandlerInfo, ctx: ?*anyopaque, 
                cc: *DispatchCtx(hinfo.DCP), params_value: Value) anyerror!DispatchResult {
    if (hinfo.params.len != hinfo.user_idx + 1) {
        return DispatchErrors.MismatchedParamCounts;
    }

    if (hinfo.is_optional1 and (isNull(params_value) or isEmptyArray(params_value))) {
        const args: hinfo.tuple_type = objectToTuple(hinfo, ctx, cc, null);
        return callF(F, hinfo, args, cc.arena());
    }
    if (params_value != .object) {
        return DispatchErrors.InvalidParams;
    }

    // Map the incoming Value (.object) into a struct object.
    // Alloc is an arena allocator; don't need to free the parsed result here.
    const parsed = try std.json.parseFromValue(hinfo.obj1_type, cc.arena(), params_value, .{
        .ignore_unknown_fields = true,
    });
    const obj1: hinfo.obj1_type = parsed.value;

    // Pack JSON array params into a tuple for F's params.
    const args: hinfo.tuple_type = objectToTuple(hinfo, ctx, cc, obj1);
    return callF(F, hinfo, args, cc.arena());
}

fn callOnNull(comptime F: anytype, comptime hinfo: HandlerInfo, ctx: ?*anyopaque,
              cc: *DispatchCtx(hinfo.DCP)) anyerror!DispatchResult {
    var nullArray = Array.init(cc.arena());
    try nullArray.append( .{ .null = {} } );
    const args: hinfo.tuple_type = try arrayToTuple(hinfo, ctx, cc, nullArray);
    return callF(F, hinfo, args, cc.arena());
}

fn callOnArray(comptime F: anytype, comptime hinfo: HandlerInfo, ctx: ?*anyopaque,
               cc: *DispatchCtx(hinfo.DCP), array: Array) anyerror!DispatchResult {
    if (hinfo.is_optional1 and array.items.len == 0) {
        var nullArray = Array.init(cc.arena());
        try nullArray.append( .{ .null = {} } );
        const args: hinfo.tuple_type = try arrayToTuple(hinfo, ctx, cc, nullArray);
        return callF(F, hinfo, args, cc.arena());
    }

    if (hinfo.params.len != hinfo.user_idx + array.items.len) {
        return DispatchErrors.MismatchedParamCounts;
    }

    // Pack the JSON array params into a tuple for F's params.
    const args: hinfo.tuple_type = try arrayToTuple(hinfo, ctx, cc, array);
    return callF(F, hinfo, args, cc.arena());
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
        const json = try std.json.Stringify.valueAlloc(alloc, result, .{
            .emit_null_optional_fields = false,
            .emit_nonportable_numbers_as_strings = true,
        });
        return DispatchResult.withResult(json);
    }
}

fn initArgsTuple(comptime hinfo: HandlerInfo, ctx: ?*anyopaque, cc: *DispatchCtx(hinfo.DCP)) hinfo.tuple_type {
    var tuple: hinfo.tuple_type = undefined;

    // Assign the context and alloc to the appropriate function argument slots in the tuple.
    if (hinfo.has_ctx()) {
        const ctx_ptr: hinfo.CTX = @ptrCast(@alignCast(ctx.?));
        const idx = idxStr(hinfo.ctx_idx.?);
        @field(tuple, idx) = ctx_ptr;
    }
    if (hinfo.has_cc()) {
        const idx = idxStr(hinfo.cc_idx.?);
        @field(tuple, idx) = cc;
    }
    if (hinfo.has_alloc()) {
        const idx = idxStr(hinfo.alloc_idx.?);
        @field(tuple, idx) = cc.arena();
    }
    return tuple;
}

inline fn idxStr(comptime idx: usize) []const u8 {
    if (idx == 0) return "0";
    if (idx == 1) return "1";
    if (idx == 2) return "2";
    unreachable;
}

fn jsonValueToTuple(comptime hinfo: HandlerInfo, ctx: ?*anyopaque, cc: *DispatchCtx(hinfo.DCP),
                    value: Value) hinfo.tuple_type {
    var tuple: hinfo.tuple_type = initArgsTuple(hinfo, ctx, cc);
    const tt_info = @typeInfo(hinfo.tuple_type).@"struct";
    const t_field = tt_info.fields[hinfo.user_idx];
    @field(tuple, t_field.name) = value;        // Value for the single argument.
    return tuple;
}

fn primitiveToTuple(comptime hinfo: HandlerInfo, ctx: ?*anyopaque, cc: *DispatchCtx(hinfo.DCP),
                    primitive_value: Value) !hinfo.tuple_type {
    var tuple: hinfo.tuple_type = initArgsTuple(hinfo, ctx, cc);
    const tt_info = @typeInfo(hinfo.tuple_type).@"struct";
    const t_field = tt_info.fields[hinfo.user_idx];
    const value = try valueAs(t_field.type).from(primitive_value);
    @field(tuple, t_field.name) = value;
    return tuple;
}

fn arrayToTuple(comptime hinfo: HandlerInfo, ctx: ?*anyopaque, cc: *DispatchCtx(hinfo.DCP),
                values: Array) !hinfo.tuple_type {
    var tuple: hinfo.tuple_type = initArgsTuple(hinfo, ctx, cc);
    const tt_info = @typeInfo(hinfo.tuple_type).@"struct";
    const start_idx = hinfo.user_idx;
    // Fill in the rest of the user specific parameters.
    inline for (start_idx.. tt_info.fields.len) |i| {
        const t_field = tt_info.fields[i];
        const j_value = values.items[i - start_idx];
        if (isValue(t_field.type)) {
            @field(tuple, t_field.name) = j_value;
        } else if (isStruct(t_field.type)) {
            const parsed = try std.json.parseFromValue(t_field.type, cc.arena(), j_value, .{
                .ignore_unknown_fields = true,
            });
            @field(tuple, t_field.name) = parsed.value;
        // } else if (isArray(t_field.type)) {
        //     // TODO: handle Array function paramenter.
        } else {
            @field(tuple, t_field.name) = try valueAs(t_field.type).from(j_value);
        }
    }
    return tuple;
}

// For optional paramenter, hinfo.obj1_type already has the optional type.
fn objectToTuple(comptime hinfo: HandlerInfo, ctx: ?*anyopaque, cc: *DispatchCtx(hinfo.DCP),
                 object: hinfo.obj1_type) hinfo.tuple_type {
    var tuple: hinfo.tuple_type = initArgsTuple(hinfo, ctx, cc);
    const tt_info = @typeInfo(hinfo.tuple_type).@"struct";
    const t_field = tt_info.fields[hinfo.user_idx];
    @field(tuple, t_field.name) = object;
    return tuple;
}

/// Convert the std.json.Value to the primitive type (bool, i64, f64, []const u8),
/// within the scope of JSON data type.
fn valueAs(comptime ParamType: type) type {
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
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    _=alloc;

    try testing.expectEqual(valueAs(i64).from(.{ .integer = 10 }), 10);
    try testing.expectEqual(valueAs(i128).from(.{ .integer = 10 }), 10);

    try testing.expectEqual(valueAs(bool).from(.{ .bool = true }), true);
    try testing.expectEqual(valueAs(bool).from(.{ .bool = false }), false);
    try testing.expectEqual(valueAs(bool).from(.{ .integer = 0 }), false);
    try testing.expectEqual(valueAs(bool).from(.{ .integer = 1 }), true);
    try testing.expectEqual(valueAs(bool).from(.{ .integer = 2 }), true);
    try testing.expectEqual(valueAs(bool).from(.{ .integer = -2 }), true);
    try testing.expectEqual(valueAs(bool).from(.{ .float = 0 }), false);
    try testing.expectEqual(valueAs(bool).from(.{ .float = 1 }), true);
    try testing.expectEqual(valueAs(bool).from(.{ .float = -1 }), true);
    try testing.expectEqual(valueAs(bool).from(.{ .float = -1.2 }), true);

    try testing.expectEqual(valueAs(f64).from(.{ .float = 1.2 }), 1.2);
    try testing.expectEqual(valueAs(f64).from(.{ .float = -1.2 }), -1.2);
    try testing.expectEqual(valueAs(f128).from(.{ .float = 10 }), 10);
    try testing.expectEqual(valueAs(f64).from(.{ .integer = 12 }), 12);

    try testing.expectEqualSlices(u8, try valueAs([]const u8).from(.{ .string = "hello" }), "hello");
}

test "Test simple JSON value conversion on invalid JSON values." {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    _=alloc;
    try testing.expectEqual(valueAs(i64).from(.{ .float = 0 }), JrErrors.InvalidJsonValueType);
    try testing.expectEqual(valueAs(i128).from(.{ .bool = true }), JrErrors.InvalidJsonValueType);
    try testing.expectEqual(valueAs(i64).from(.{ .string = "abc" }), error.InvalidCharacter);

    try testing.expectEqual(valueAs(f128).from(.{ .bool = true }), JrErrors.InvalidJsonValueType);
    try testing.expectEqual(valueAs(f64).from(.{ .string = "abc" }), error.InvalidCharacter);
}

test "Test JSON value conversion with alloc." {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const x = try valueAs([]const u8).fromAlloc(.{ .string = "hello" }, .{ .alloc = alloc });
    try testing.expectEqualSlices(u8, x, "hello");

    try testing.expectEqual(valueAs(i64).fromAlloc(.{ .integer = 10 }, .{ .alloc = alloc }), 10);
    
    alloc.free(x);
}


