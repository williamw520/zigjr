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


pub const RegisterOptions = struct {
    context: ?*anyopaque = null,
    raw_params: bool = false,
};

pub const RpcRegistry = struct {
    const Self = @This();

    handlers:   StringHashMap(RpcHandler),

    pub fn init(alloc: Allocator) Self {
        return .{
            .handlers = StringHashMap(RpcHandler).init(alloc),
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        // Clean up any contexts owned by the RpcHandler entries
        var it = self.handlers.iterator();
        while (it.next()) |entry| {
            const rpc_handler = entry.value_ptr;
            rpc_handler.deinit(alloc);
        }
        self.handlers.deinit();
    }

    // TODO: Need to register a 'free' handler to free the result.
    // Call it after building the DispatchResult in invoke().
    pub fn register(self: *Self, method: []const u8, comptime handler_fn: anytype, opt: RegisterOptions) !void {
        const fn_info = getFnInfo(handler_fn);
        try validateHandler(fn_info, method, opt);
        const ctx_type = void;
        const h = makeRpcHandler(handler_fn, fn_info, ctx_type);
        try self.handlers.put(method, h);
    }

    pub fn registerWithCtx(self: *Self, method: []const u8, context: anytype, comptime handler_fn: anytype,
                           opt: RegisterOptions) !void {
        const fn_info = getFnInfo(handler_fn);
        const ctx_type = @TypeOf(context);
        try validateHandler(fn_info, method, opt);
        var h = makeRpcHandler(handler_fn, fn_info, ctx_type);
        h.setCtx(context);
        try self.handlers.put(method, h);
    }

    pub fn has(self: *Self, method: []const u8) bool {
        return self.handlers.get(method) != null;
    }

    /// Run a handler on the request and generate a DispatchResult.
    /// Return any error during the function call.  Caller handles any error.
    /// Call free() to free the DispatchResult.
    pub fn dispatch(self: *Self, alloc: Allocator, req: RpcRequest) anyerror!DispatchResult {
        const h = self.handlers.get(req.method) orelse return DispatchErrors.MethodNotFound;
        return h.invoke(alloc, req.params);
    }

    // TODO: rename free() to freeResult()
    pub fn free(_: *Self, alloc: Allocator, dresult: DispatchResult) void {
        switch (dresult) {
            .none => {},
            .result => |json_result| alloc.free(json_result),
            .result_lit => {},
            .err => |err| {
                if (err.msg_alloc) alloc.free(err.msg);
                if (err.data)|data| alloc.free(data);
            },
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
    // Poorman's pointer with an one-entry vtable.
    context: ?*anyopaque,
    call: *const fn(alloc: Allocator, context: ?*anyopaque, json_args: Value) anyerror!DispatchResult,

    fn setCtx(self: *RpcHandler, context: ?*anyopaque) void {
        self.context = context;
    }

    pub fn invoke(self: RpcHandler, alloc: Allocator, json_args: Value) anyerror!DispatchResult {
        return self.call(alloc, self.context, json_args);
    }

    pub fn deinit(self: RpcHandler, allocator: Allocator) void {
        // TODO: deinit on context.
        _=self;
        _=allocator;
    }
};

fn makeRpcHandler(comptime F: anytype, comptime fn_info: Type.Fn, comptime ctx_type: type) RpcHandler {
    const param_ttype = ParamTupleType(fn_info.params);
    const is_void = isVoid(fn_info.return_type);
    const has_err = isErrorUnion(fn_info.return_type);
    const has_ctx = ctx_type != void;
    const is_objmap = isParamObjMap(fn_info.params, has_ctx);
    // @compileLog(is_objmap);

    return .{
        .context = null,
        .call = &struct {
            // Wrapping a specific function, its parameters, its return value, and its return error.
            fn call_wrapper(alloc: Allocator, ctx: ?*anyopaque, json_args: Value) anyerror!DispatchResult {
                // TODO: Handle std.json.Value func parameter
                // TODO: Handle std.json.Array func parameter
                // Handle std.json.ObjectMap func parameter
                if (is_objmap) {
                    switch (json_args) {
                        .object => |objmap| {
                            return callFnOnObjMap(F, fn_info, param_ttype, has_ctx, has_err, is_void,
                                                  ctx_type, alloc, ctx, objmap);
                        },
                        else    => {
                            std.debug.print("Expect ObjectMap but get unexpected JSON params: {any}\n", .{json_args});
                            return DispatchErrors.InvalidParams;
                        },
                    }
                } else {
                    switch (json_args) {
                        .null   => {
                            const array = Array.init(alloc);
                            return callFnOnArray(F, fn_info, param_ttype, has_ctx, has_err, is_void,
                                                 ctx_type, alloc, ctx, array);
                        },
                        .array  => |array| {
                            return callFnOnArray(F, fn_info, param_ttype, has_ctx, has_err, is_void,
                                                 ctx_type, alloc, ctx, array);
                        },
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

// Note: these functions must be inline to force evaluation in comptime.
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

fn callFnOnObjMap(comptime F: anytype, comptime fn_info: Type.Fn, comptime param_ttype: type, 
                  comptime has_ctx: bool, comptime has_err: bool, comptime is_void: bool, comptime ctx_type: type,
                  alloc: Allocator, ctx: ?*anyopaque, objmap: ObjectMap) anyerror!DispatchResult {

    const extra_param = if (has_ctx) 1 else 0;
    if (fn_info.params.len != 1 + extra_param)
        return DispatchErrors.MismatchedParamCounts;

    // Pack JSON array params to a tuple for fn params.
    const args: param_ttype = if (has_ctx)
        objmapToTupleCtx(param_ttype, objmap, ctx.?, ctx_type)
    else
        objmapToTuple(param_ttype, objmap);

    if (is_void) {
        if (has_err)
            try @call(.auto, F, args)
        else
            @call(.auto, F, args);
        return DispatchResult.asNone();
    } else {
        const res = if (has_err)
            try @call(.auto, F, args)
        else
            @call(.auto, F, args);
        return DispatchResult.withResult(try std.json.stringifyAlloc(alloc, res, .{}));
    }
}

fn callFnOnArray(comptime F: anytype, comptime fn_info: Type.Fn, comptime param_ttype: type, 
                 comptime has_ctx: bool, comptime has_err: bool, comptime is_void: bool, comptime ctx_type: type,
                 alloc: Allocator, ctx: ?*anyopaque, array: Array) anyerror!DispatchResult {

    const extra_param = if (has_ctx) 1 else 0;
    if (fn_info.params.len != array.items.len + extra_param)
        return DispatchErrors.MismatchedParamCounts;

    // Pack JSON array params to a tuple for fn params.
    const args: param_ttype = if (has_ctx)
        try valuesToTupleCtx(param_ttype, array, ctx.?, ctx_type)
    else
        try valuesToTuple(param_ttype, array);

    if (is_void) {
        if (has_err)
            try @call(.auto, F, args)
        else
            @call(.auto, F, args);
        return DispatchResult.asNone();
    } else {
        const res = if (has_err)
            try @call(.auto, F, args)
        else
            @call(.auto, F, args);
        return DispatchResult.withResult(try std.json.stringifyAlloc(alloc, res, .{}));
    }
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

inline fn isParamObjMap(comptime params: []const Type.Fn.Param, comptime has_ctx: bool) bool {
    // @compileLog("param[0].type == ObjectMap?", params[0].type.? == ObjectMap, params[0].type);
    if (has_ctx) {
        return params.len > 1 and params[1].type.? == ObjectMap;
    } else {
        return params.len > 0 and params[0].type.? == ObjectMap;
    }
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


