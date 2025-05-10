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

const runner = @import("runner.zig");
const DispatchResult = runner.DispatchResult;

const errors = @import("errors.zig");
const ErrorCode = errors.ErrorCode;
const JrErrors = errors.JrErrors;


pub const RegisterOptions = struct {
    raw_params: bool = false,
};

pub const Registry = struct {
    const Self = @This();

    alloc:      Allocator,
    handlers:   StringHashMap(HandlerFn),

    pub fn init(allocator: Allocator) Self {
        return .{
            .alloc = allocator,
            .handlers = StringHashMap(HandlerFn).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.handlers.deinit();
    }

    pub fn register(self: *Self, method: []const u8, handler_fn: anytype, opt: RegisterOptions) !void {
        std.debug.print("register {s}\n", .{method});
        if (std.mem.startsWith(u8, method, "rpc.")) {
            return RegistrationErrors.InvalidMethodName;    // By spec, "rpc." is reserved.
        }
        try self.handlers.put(method, try toHandlerFn(handler_fn, opt));
    }

    pub fn has(self: *Self, method: []const u8) bool {
        return self.handlers.get(method) != null;
    }

    /// Run a handler on the request and generate a Response JSON string.
    /// Call freeResponse() to free the string.
    pub fn run(self: *Self, alloc: Allocator, req: RpcRequest) !DispatchResult {
        return self.dispatch(alloc, req) catch |dispatch_err| {
            return toResultError(dispatch_err);     // dispatch error returned as error response.
        };
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

    fn dispatch(self: *Self, alloc: Allocator, req: RpcRequest) anyerror!DispatchResult {
        const h_fn = self.handlers.get(req.method) orelse
            return toResultError(DispatchErrors.MethodNotFound);

        switch (req.params) {
            .array  => |array|  return dispatchOnArray(alloc, h_fn, array),
            .null   => {
                switch(h_fn) {
                    .fn0    =>  |f| return f(alloc),
                    else    =>      return toResultError(DispatchErrors.MismatchedParamCounts),
                }
            },
            .object => |object| {
                switch (h_fn) {
                    .fnRaw  =>  |f| return f(alloc, req.params),
                    .fnObj  =>  |f| return f(alloc, object),
                    else    =>      return toResultError(DispatchErrors.NoHandlerForObjectParam),
                }
            },
            else    => return toResultError(DispatchErrors.InvalidParams),
        }
    }

    fn dispatchOnArray(alloc: Allocator, handler_fn: HandlerFn, array: Array) anyerror!DispatchResult {
        // Dispatch on array based parameter.
        if (handler_fn == .fnArr) return handler_fn.fnArr(alloc, array);

        // Dispatch on fixed-length based parameters.
        const p = array.items;
        if (paramLen(handler_fn) != p.len) return toResultError(DispatchErrors.MismatchedParamCounts);
        return switch (handler_fn) {
            .fn0 => |f| f(alloc),
            .fn1 => |f| f(alloc, p[0]),
            .fn2 => |f| f(alloc, p[0], p[1]),
            .fn3 => |f| f(alloc, p[0], p[1], p[2]),
            .fn4 => |f| f(alloc, p[0], p[1], p[2], p[3]),
            .fn5 => |f| f(alloc, p[0], p[1], p[2], p[3], p[4]),
            .fn6 => |f| f(alloc, p[0], p[1], p[2], p[3], p[4], p[5]),
            .fnArr => unreachable,  // already handled previously; shouldn't here.
            .fnObj => unreachable,  // already handled previously; shouldn't here.
            .fnRaw => unreachable,  // already handled previously; shouldn't here.
        };
    }

};

// 4 JSON primitive types.
// bool: bool,
// integer: i64,
// float: f64,
// string: []const u8,

/// The returned JSON string must be allocated with the passed in allocator.
/// The caller will free it with the allocator after using it in the Response message.
/// Call std.json.stringifyAlloc() to build the returned JSON will take care of it.
const HandlerFn = union(enum) {
    fn0: *const fn(Allocator) anyerror!DispatchResult,
    fn1: *const fn(Allocator, Value) anyerror!DispatchResult,
    fn2: *const fn(Allocator, Value, Value) anyerror!DispatchResult,
    fn3: *const fn(Allocator, Value, Value, Value) anyerror!DispatchResult,
    fn4: *const fn(Allocator, Value, Value, Value, Value) anyerror!DispatchResult,
    fn5: *const fn(Allocator, Value, Value, Value, Value, Value) anyerror!DispatchResult,
    fn6: *const fn(Allocator, Value, Value, Value, Value, Value, Value) anyerror!DispatchResult,
    fnArr: *const fn(Allocator, Array) anyerror!DispatchResult,
    fnObj: *const fn(Allocator, ObjectMap) anyerror!DispatchResult,
    fnRaw: *const fn(Allocator, Value) anyerror!DispatchResult,
};

fn toHandlerFn(handler_fn: anytype, opt: RegisterOptions) !HandlerFn {
    const fn_type_info: Type = @typeInfo(@TypeOf(handler_fn));
    const params = switch (fn_type_info) {
        .@"fn"  => |info_fn| info_fn.params,
        else    => return RegistrationErrors.HandlerNotFunction,
    };
    if (params.len == 0) return RegistrationErrors.MissingAllocator;
    const param0_type = params[0].type orelse return RegistrationErrors.MissingAllocatorParameter;
    if (param0_type != Allocator) return RegistrationErrors.MissingAllocatorParameter;

    const nparams = params.len - 1; // skip one param for the Allocator param.

    // handler taking the raw-params as a Value can only have one parameter.
    if (opt.raw_params) {
        if (nparams != 1) return RegistrationErrors.MismatchedParameterCountsForRawParams;
        const param1_type = params[1].type orelse return RegistrationErrors.InvalidParamTypeForRawParams;
        if (param1_type != Value) return RegistrationErrors.InvalidParamTypeForRawParams;
        return HandlerFn { .fnRaw = handler_fn };
    }

    switch (nparams) {
        0 => return HandlerFn { .fn0 = handler_fn },
        1 => {
            // Single-param handler can be a Value, Array, or Object handler.
            if (params[1].type)|typ| {
                switch (typ) {
                    Value =>    return HandlerFn { .fn1 = handler_fn },
                    Array =>    return HandlerFn { .fnArr = handler_fn },
                    ObjectMap=> return HandlerFn { .fnObj = handler_fn },
                    else =>     return RegistrationErrors.HandlerInvalidParameterType,
                }
            }
            return RegistrationErrors.HandlerInvalidParameter;
        },
        2 => return HandlerFn { .fn2 = handler_fn },
        3 => return HandlerFn { .fn3 = handler_fn },
        4 => return HandlerFn { .fn4 = handler_fn },
        5 => return HandlerFn { .fn5 = handler_fn },
        6 => return HandlerFn { .fn6 = handler_fn },
        else => return RegistrationErrors.HandlerTooManyParams,
    }
}

fn paramLen(handler: HandlerFn) ?usize {
    return switch (handler) {
        .fn0 => 0,
        .fn1 => 1,
        .fn2 => 2,
        .fn3 => 3,
        .fn4 => 4,
        .fn5 => 5,
        .fn6 => 6,
        else => null,
    };
}

fn toResultError(err: anyerror) DispatchResult {
    return switch (err) {
        DispatchErrors.MethodNotFound => DispatchResult.withErr(
            ErrorCode.MethodNotFound, "Method not found."),
        DispatchErrors.InvalidParams => DispatchResult.withErr(
            ErrorCode.InvalidParams, "Invalid parameters."),
        DispatchErrors.NoHandlerForObjectParam => DispatchResult.withErr(
            ErrorCode.InvalidParams, "Handler expecting an object parameter but got non-object parameters."),
        DispatchErrors.MismatchedParamCounts => DispatchResult.withErr(
            ErrorCode.InvalidParams, "The number of parameters of the request does not match the parameter count of the handler."),
        else => DispatchResult.withErr(ErrorCode.ServerError, @errorName(err)),
    };
}

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

pub const DispatchErrors = error {
    MethodNotFound,
    InvalidParams,
    NoHandlerForObjectParam,
    MismatchedParamCounts,
    OutOfMemory,
};


