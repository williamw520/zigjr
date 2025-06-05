// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const assert = std.debug.assert;
const Type = std.builtin.Type;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const StringHashMap = std.hash_map.StringHashMap;
const AutoHashMap = std.hash_map.AutoHashMap;
const allocPrint = std.fmt.allocPrint;
const Value = std.json.Value;
const Array = std.json.Array;
const ObjectMap = std.json.ObjectMap;

const req_parser = @import("request.zig");
const RpcRequest = req_parser.RpcRequest;
const RpcId = req_parser.RpcId;

const handler = @import("handler.zig");
const DispatchResult = handler.DispatchResult;
const DispatchErrors = handler.DispatchErrors;

const errors = @import("errors.zig");
const ErrorCode = errors.ErrorCode;
const JrErrors = errors.JrErrors;

const ValueAs = @import("jsonutil.zig").ValueAs;


// TODO: remove
pub const RegisterOptions = struct {
    context: ?*anyopaque = null,
    raw_params: bool = false,
};

pub const RpcRegistry = struct {
    const Self = @This();

    alloc:      Allocator,
    handlers:   StringHashMap(RpcHandler),

    pub fn init(alloc: Allocator) Self {
        return .{
            .alloc = alloc,
            .handlers = StringHashMap(RpcHandler).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up any contexts owned by the RpcHandler entries
        var it = self.handlers.iterator();
        while (it.next()) |entry| {
            var rpc_handler = entry.value_ptr;
            rpc_handler.deinit();
        }
        self.handlers.deinit();
    }

    // TODO: Need to register a 'free' handler to free the result.
    // Call it after building the DispatchResult in invoke().
    pub fn register(self: *Self, method: []const u8, comptime handler_fn: anytype, opt: RegisterOptions) !void {
        const ctx_type = void;
        const hinfo = getHandlerInfo(handler_fn, ctx_type);
        // @compileLog(hinfo);
        try validateHandler(hinfo.fn_info, method, opt);
        const h = try makeRpcHandler(handler_fn, hinfo, self.alloc);
        try self.handlers.put(method, h);
    }

    pub fn registerWithCtx(self: *Self, method: []const u8, context: anytype, comptime handler_fn: anytype,
                           opt: RegisterOptions) !void {
        const ctx_type = @TypeOf(context);
        const hinfo = getHandlerInfo(handler_fn, ctx_type);
        try validateHandler(hinfo.fn_info, method, opt);
        var h = try makeRpcHandler(handler_fn, hinfo, self.alloc);
        h.setCtx(context);
        try self.handlers.put(method, h);
    }

    pub fn has(self: *Self, method: []const u8) bool {
        return self.handlers.get(method) != null;
    }

    /// Run a handler on the request and generate a DispatchResult.
    /// Return any error during the function call.  Caller handles any error.
    /// Call free() to free the DispatchResult.
    pub fn dispatch(self: *Self, _: Allocator, req: RpcRequest) anyerror!DispatchResult {
        var h = self.handlers.getPtr(req.method) orelse return DispatchErrors.MethodNotFound;
        return h.invoke(req.params);
    }

    pub fn dispatchEnd(self: *Self, alloc: Allocator, req: RpcRequest, dresult: DispatchResult) void {
        _=alloc;
        _=dresult;

        if (self.handlers.getPtr(req.method))|h| {
            h.invokeEnd();
        }
    }

};


pub const RegistrationErrors = error {
    InvalidMethodName,
    HandlerNotFunction,
    MissingAllocatorParameter,
    MissingParameterType,
    UnsupportedParameterType,
    HandlerInvalidParameter,
    HandlerInvalidParameterType,
    HandlerTooManyParams,
    MismatchedParameterCountsForRawParams,
    InvalidParamTypeForRawParams,
};


// Uniform callback object that can be stored in the hash map.
// makeRpcHandler will deal with the parameter unpacking of specific function at comptime.
const RpcHandler = struct {
    arena: *ArenaAllocator,     // arena needs to be a ptr to the struct to survive copying.
    arena_alloc: Allocator,
    context: ?*anyopaque,
    call: *const fn(alloc: Allocator, context: ?*anyopaque, json_args: Value) anyerror!DispatchResult,

    fn setCtx(self: *RpcHandler, context: ?*anyopaque) void {
        self.context = context;
    }

    fn invoke(self: *RpcHandler, json_args: Value) anyerror!DispatchResult {
        return self.call(self.arena_alloc, self.context, json_args);
    }

    fn invokeEnd(self: *RpcHandler) void {
        // Reset arena memory at the end of each invocation.
        _ = self.arena.reset(.{ .retain_with_limit = 1024 });
    }

    fn deinit(self: *RpcHandler) void {
        // TODO: deinit on context.

        self.arena.deinit();
        const backing_alloc = self.arena.child_allocator;
        backing_alloc.destroy(self.arena);
    }
};

fn makeRpcHandler(comptime F: anytype, hinfo: HandlerInfo, backing_alloc: Allocator) !RpcHandler {
    const arena_ptr = try backing_alloc.create(ArenaAllocator);
    arena_ptr.* = ArenaAllocator.init(backing_alloc);

    return .{
        .arena = arena_ptr,
        .arena_alloc = arena_ptr.allocator(),
        .context = null,
        .call = &struct {
            // Wrapping a specific function, its parameters, its return value, and its return error.
            fn call_wrapper(alloc: Allocator, ctx: ?*anyopaque, json_args: Value) anyerror!DispatchResult {
                if (hinfo.is_value) {
                    return callFnOnValue(F, hinfo, alloc, ctx, json_args);
                } else if (hinfo.is_objmap) {
                    switch (json_args) {
                        .object => |objmap| return callFnOnObjMap(F, hinfo, alloc, ctx, objmap),
                        else    => {
                            std.debug.print("Expect ObjectMap but get unexpected JSON params: {any}\n", .{json_args});
                            return DispatchErrors.InvalidParams;
                        },
                    }
                } else {
                    switch (json_args) {
                        .null   => return callFnOnArray(F, hinfo, alloc, ctx, Array.init(alloc)),
                        .array  => |array| return callFnOnArray(F, hinfo, alloc, ctx, array),
                        else    => {
                            std.debug.print("Unexpected JSON params: {any}\n", .{json_args});
                            return DispatchErrors.InvalidParams;
                        },
                    }
                }
            }
        }.call_wrapper,
    };
}


fn validateHandler(comptime fn_info: Type.Fn, method: []const u8, opt: RegisterOptions) !void {
    if (std.mem.startsWith(u8, method, "rpc.")) {   // By the JSON-RPC spec, "rpc." is reserved.
        return RegistrationErrors.InvalidMethodName;
    }

    // handler taking the raw-params as a Value can only have one parameter.
    if (opt.raw_params) {
        if (fn_info.params.len != 1) return RegistrationErrors.MismatchedParameterCountsForRawParams;
        const p_type = fn_info.params[0].type orelse return RegistrationErrors.InvalidParamTypeForRawParams;
        if (p_type != Value) return RegistrationErrors.InvalidParamTypeForRawParams;
        // TODO: Does this need special handling?
    }
}

// Note: the following functions must be inline to force evaluation in comptime for makeRpcHandler.

// This is a comptime struct capturing the needed comptime info to do call the handler.
const HandlerInfo = struct {
    ctx_type:       type,
    fn_info:        Type.Fn,
    params:         []const Type.Fn.Param,
    tuple_type:     type,
    has_ctx:        bool,
    has_alloc:      bool,
    alloc_idx:      usize,
    user_idx:       usize,
    is_value:       bool,
    is_objmap:      bool,
    is_array:       bool,
    has_err:        bool,
    is_void:        bool,
};

inline fn getHandlerInfo(comptime handler_fn: anytype, comptime ctx_type: type) HandlerInfo {
    const fn_info = getFnInfo(handler_fn);
    const params = fn_info.params;
    const has_ctx = ctx_type != void;
    const after_ctx_idx = if (has_ctx) 1 else 0;            // index of the parameter after context;
    const alloc_idx = after_ctx_idx;                        // index of the allocator parameter.
    const has_alloc = params.len > alloc_idx and params[alloc_idx].type.? == std.mem.Allocator;
    const user_idx = alloc_idx + if (has_alloc) 1 else 0;   // index of the first user parameter.

    return .{
        .ctx_type   = ctx_type,
        .fn_info    = fn_info,
        .params     = params,
        .tuple_type = ParamTupleType(params),
        .has_ctx    = has_ctx,
        .has_alloc  = has_alloc,
        .alloc_idx  = alloc_idx,
        .user_idx   = user_idx,
        .is_value   = params.len > user_idx and params[user_idx].type.? == std.json.Value,
        .is_objmap  = params.len > user_idx and params[user_idx].type.? == std.json.ObjectMap,
        .is_array   = params.len > user_idx and params[user_idx].type.? == std.json.Array,
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
        else    => @compileError("Param handler_fn must be a function.  Got: " ++ @typeName(handler_fn)),
    };
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

inline fn isVoid(comptime T: ?type) bool {
    if (T)|t| {
        const type_info: Type = @typeInfo(t);
        switch (type_info) {
            .error_union => |eu| return eu.payload == void,
            .void => return true,
            else =>  return false,
        }
    } else {
        return false;
    }
}

fn callFnOnValue(comptime F: anytype, comptime hinfo: HandlerInfo,
                 alloc: Allocator, ctx: ?*anyopaque, json_args: Value) anyerror!DispatchResult {

    const extra_param = if (hinfo.has_ctx) 1 else 0;
    if (hinfo.fn_info.params.len != 1 + extra_param)
        return DispatchErrors.MismatchedParamCounts;

    // Pack JSON array params to a tuple for fn params.
    const args: hinfo.tuple_type = if (hinfo.has_ctx)
        valueToTupleCtx(hinfo.tuple_type, json_args, ctx.?, hinfo.ctx_type)
    else
        valueToTuple(hinfo.tuple_type, json_args);

    if (hinfo.is_void) {
        if (hinfo.has_err)
            try @call(.auto, F, args)
        else
            @call(.auto, F, args);
        return DispatchResult.asNone();
    } else {
        const res = if (hinfo.has_err)
            try @call(.auto, F, args)
        else
            @call(.auto, F, args);
        return DispatchResult.withResult(try std.json.stringifyAlloc(alloc, res, .{}));
    }
}

fn callFnOnObjMap(comptime F: anytype, comptime hinfo: HandlerInfo,
                  alloc: Allocator, ctx: ?*anyopaque, objmap: ObjectMap) anyerror!DispatchResult {

    const extra_param = if (hinfo.has_ctx) 1 else 0;
    if (hinfo.fn_info.params.len != 1 + extra_param)
        return DispatchErrors.MismatchedParamCounts;

    // Pack JSON array params to a tuple for fn params.
    const args: hinfo.tuple_type = if (hinfo.has_ctx)
        objmapToTupleCtx(hinfo.tuple_type, objmap, ctx.?, hinfo.ctx_type)
    else
        objmapToTuple(hinfo.tuple_type, objmap);

    if (hinfo.is_void) {
        if (hinfo.has_err)
            try @call(.auto, F, args)
        else
            @call(.auto, F, args);
        return DispatchResult.asNone();
    } else {
        const res = if (hinfo.has_err)
            try @call(.auto, F, args)
        else
            @call(.auto, F, args);
        return DispatchResult.withResult(try std.json.stringifyAlloc(alloc, res, .{}));
    }
}

fn callFnOnArray(comptime F: anytype, hinfo: HandlerInfo,
                 alloc: Allocator, ctx: ?*anyopaque, array: Array) anyerror!DispatchResult {

    const extra_param = if (hinfo.has_ctx) 1 else 0;
    if (hinfo.fn_info.params.len != array.items.len + extra_param)
        return DispatchErrors.MismatchedParamCounts;

    // Pack JSON array params to a tuple for fn params.
    const args: hinfo.tuple_type = if (hinfo.has_ctx)
        try valuesToTupleCtx(hinfo.tuple_type, array, ctx.?, hinfo.ctx_type)
    else
        try valuesToTuple(hinfo.tuple_type, array);

    if (hinfo.is_void) {
        if (hinfo.has_err)
            try @call(.auto, F, args)
        else
            @call(.auto, F, args);
        return DispatchResult.asNone();
    } else {
        const res = if (hinfo.has_err)
            try @call(.auto, F, args)
        else
            @call(.auto, F, args);
        return DispatchResult.withResult(try std.json.stringifyAlloc(alloc, res, .{}));
    }
}

fn valueToTuple(comptime tuple_type: type, value: Value) tuple_type {
    var tuple: tuple_type = undefined;
    @field(tuple, "0") = value;
    return tuple;
}

fn valueToTupleCtx(comptime tuple_type: type, value: Value,
                   ctx: *anyopaque, comptime ctx_type: type) tuple_type {
    var tuple: tuple_type = undefined;
    const ctx_ptr: ctx_type = @ptrCast(@alignCast(ctx));

    @field(tuple, "0") = ctx_ptr;
    @field(tuple, "1") = value;
    return tuple;
}

fn objmapToTuple(comptime tuple_type: type, objmap: ObjectMap) tuple_type {
    var tuple: tuple_type = undefined;
    @field(tuple, "0") = objmap;
    return tuple;
}

fn objmapToTupleCtx(comptime tuple_type: type, objmap: ObjectMap,
                    ctx: *anyopaque, comptime ctx_type: type) tuple_type {
    var tuple: tuple_type = undefined;
    const ctx_ptr: ctx_type = @ptrCast(@alignCast(ctx));

    @field(tuple, "0") = ctx_ptr;
    @field(tuple, "1") = objmap;
    return tuple;
}

fn valuesToTuple(comptime tuple_type: type, values: Array) !tuple_type {
    const tt_info = @typeInfo(tuple_type).@"struct";
    var tuple: tuple_type = undefined;

    inline for (0..tt_info.fields.len)|i| {
        const field = tt_info.fields[i];
        const value = values.items[i];
        @field(tuple, field.name) = try ValueAs(field.type).from(value);
    }
    return tuple;
}

fn valuesToTupleCtx(comptime tuple_type: type, values: Array,
                    ctx: *anyopaque, comptime ctx_type: type) !tuple_type {
    const tt_info = @typeInfo(tuple_type).@"struct";
    var tuple: tuple_type = undefined;
    // const ctx_ptr: ctx_type = @ptrCast(@alignCast(@alignOf(ctx_type)), ));
    const ctx_ptr: ctx_type = @ptrCast(@alignCast(ctx));

    @field(tuple, "0") = ctx_ptr;
    inline for (1..tt_info.fields.len)|i| {
        const field = tt_info.fields[i];
        const value = values.items[i - 1];
        @field(tuple, field.name) = try ValueAs(field.type).from(value);
    }
    return tuple;
}


