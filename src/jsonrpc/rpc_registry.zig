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
            entry.value_ptr.deinit(alloc);
        }
        self.handlers.deinit();
    }

    pub fn register(self: *Self, method: []const u8, comptime handler_fn: anytype, opt: RegisterOptions) !void {
        const fn_info = getFnInfo(handler_fn);
        try validateHandler(fn_info, method, opt);
        const h = makeRpcHandler(handler_fn, fn_info);
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

        switch (req.params) {
            // .array  => |array|  return callOnArray(alloc, h, array),
            .null   => {
                if (h.nparams != 0) return DispatchErrors.MismatchedParamCounts;
                return h.invoke(alloc, req.params);
            },
            // .object => |object| {
            //     switch (h) {
            //         .fnRaw  =>  |f| return f(alloc, req.params),
            //         .fnObj  =>  |f| return f(alloc, object),
            //         else    =>      return DispatchErrors.NoHandlerForObjectParam,
            //     }
            // },
            else    => return DispatchErrors.InvalidParams,
        }
    }

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



    // fn callOnArray(alloc: Allocator, handler: RpcHandler, array: Array) anyerror!DispatchResult {
    //     _=alloc;
    //     _=handler;
    //     _=array;
    // }


    // fn callOnArray(alloc: Allocator, handler_fn: HandlerFn, array: Array) anyerror!DispatchResult {
    //     // Call on array based parameter.
    //     if (handler_fn == .fnArr) return handler_fn.fnArr(alloc, array);

    //     // Call on fixed-length based parameters.
    //     const p = array.items;
    //     if (paramLen(handler_fn) != p.len) return DispatchErrors.MismatchedParamCounts;
    //     return switch (handler_fn) {
    //         .fn0 => |f| f(alloc),
    //         .fn1 => |f| f(alloc, p[0]),
    //         .fn2 => |f| f(alloc, p[0], p[1]),
    //         .fn3 => |f| f(alloc, p[0], p[1], p[2]),
    //         .fn4 => |f| f(alloc, p[0], p[1], p[2], p[3]),
    //         .fn5 => |f| f(alloc, p[0], p[1], p[2], p[3], p[4]),
    //         .fn6 => |f| f(alloc, p[0], p[1], p[2], p[3], p[4], p[5]),
    //         .fnArr => unreachable,  // already handled previously; shouldn't here.
    //         .fnObj => unreachable,  // already handled previously; shouldn't here.
    //         .fnRaw => unreachable,  // already handled previously; shouldn't here.
    //     };
    // }

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
    context: *anyopaque,
    nparams: usize,
    call: *const fn(context: *anyopaque, alloc: Allocator, json_args: Value) anyerror!DispatchResult,

    pub fn invoke(self: RpcHandler, alloc: Allocator, json_args: Value) anyerror!DispatchResult {
        return self.call(self.context, alloc, json_args);
    }

    pub fn deinit(self: RpcHandler, allocator: Allocator) void {
        _=self;
        _=allocator;
    }
};

fn makeRpcHandler(comptime F: anytype, comptime fn_info: Type.Fn) RpcHandler {
    // const param_ttype = ParamTupleType(fn_info.params);
    return .{
        .context = "",
        .nparams = fn_info.params.len,
        .call = &struct {
            // Wrapping a specific function, its parameters, its return value, and its return error.
            fn call_wrapper(context: *anyopaque, alloc: Allocator, json_args: Value) anyerror!DispatchResult {
                _ = context;
                _ = json_args;

                if (isVoid(fn_info.return_type)) {
                    // TODO: validate request with an id but function has a void return type. Check in high level.
                    if (isErrorUnion(fn_info.return_type)) {
                        try @call(.auto, F, .{});
                    } else {
                        @call(.auto, F, .{});
                    }
                    return DispatchResult.asNone();
                } else {
                    const result = if (isErrorUnion(fn_info.return_type))
                        try @call(.auto, F, .{})
                    else
                        @call(.auto, F, .{});
                    return DispatchResult.withResult(try std.json.stringifyAlloc(alloc, result, .{}));
                }
                // } else {
                //     if (return_type == void or return_type == null) {
                //         std.debug.print("3. return_type: {any}\n", .{@typeInfo(return_type.?)});
                //         // TODO: handle request with an id but function has a void return type.
                //         @call(.auto, F, .{});
                //         return DispatchResult.asNone();
                //     } else {
                //         std.debug.print("4. return_type: {any}\n", .{@typeInfo(return_type.?)});
                //         // TODO: handle request with an id but function has a void return type.
                //         const result = @call(.auto, F, .{});
                //         return .{ .result = try std.json.stringifyAlloc(alloc, result, .{}) };
                //     }
                // }
                // try @call(.auto, F, .{});
                // return DispatchResult.asNone();
                
                // switch (json_args) {
                //     .null   => {
                //         if (fn_info.params.len != 0) return DispatchErrors.MismatchedParamCounts;

                //         if (hasErrorSet(return_type)) {
                //             if (return_type == void or return_type == null) {
                //                 // TODO: handle request with an id but function has a void return type.
                //                 std.debug.print("1. return_type: {any}\n", .{@typeInfo(return_type.?)});
                //                 // @call(.auto, F, .{});
                //                 // return DispatchResult.asNone();
                //             } else {
                //                 std.debug.print("2. return_type: {any}\n", .{@typeInfo(return_type.?)});
                //                 // const result = try @call(.auto, F, .{});
                //                 // return .{ .result = try std.json.stringifyAlloc(alloc, result, .{}) };
                //             }
                //         } else {
                //             if (return_type == void or return_type == null) {
                //                 std.debug.print("3. return_type: {any}\n", .{@typeInfo(return_type.?)});
                //                 // TODO: handle request with an id but function has a void return type.
                //                 @call(.auto, F, .{});
                //                 return DispatchResult.asNone();
                //             } else {
                //                 std.debug.print("4. return_type: {any}\n", .{@typeInfo(return_type.?)});
                //                 // TODO: handle request with an id but function has a void return type.
                //                 const result = @call(.auto, F, .{});
                //                 return .{ .result = try std.json.stringifyAlloc(alloc, result, .{}) };
                //             }
                //         }
                //         try @call(.auto, F, .{});
                //         return DispatchResult.asNone();
                //     },
                // .array  => |array| {
                //     // Pack the JSON values as the parameters for the function.
                //     const args_tuple = try valuesToTuple(param_ttype, array);
                //     // TODO: handle error.
                //     const result = @call(.auto, F, args_tuple);
                //     return .{ .result = try std.json.stringifyAlloc(alloc, result, .{}) };
                // },
                // .object => |object| {
                //     switch (h) {
                //         .fnRaw  =>  |f| return f(alloc, req.params),
                //         .fnObj  =>  |f| return f(alloc, object),
                //         else    =>      return DispatchErrors.NoHandlerForObjectParam,
                //     }
                // },
                // TODO: Handle std.json.Value func parameter
                // TODO: Handle std.json.Array func parameter
                // TODO: Handle std.json.ObjectMap func parameter
                // else    => return DispatchErrors.InvalidParams,
                // }
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

/// Make a tuple type from the parameters of a function.
/// Each parameter becomes a field of the tuple.
fn ParamTupleType(comptime params: []const Type.Fn.Param) type {
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

fn valuesToTuple(comptime tuple_type: type, values: Array) !tuple_type {
    const tt_info = @typeInfo(tuple_type).@"struct";
    var tuple: tuple_type = undefined;
    inline for (tt_info.fields, 0..)|field, i| {
        const value = values.items[i];
        @field(tuple, field.name) = try ValueAs(field.type).from(value);
    }
    return tuple;
}


