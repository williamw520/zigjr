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

const parser = @import("../jsonrpc/parser.zig");
const RpcRequest = parser.RpcRequest;
const RpcId = parser.RpcId;

const jsonrpc_errors = @import("../jsonrpc/jsonrpc_errors.zig");
const ErrorCode = jsonrpc_errors.ErrorCode;
const JrErrors = jsonrpc_errors.JrErrors;

const dispatcher_errors = @import("dispatch_erros.zig");
pub const RegistrationErrors = dispatcher_errors.RegistrationErrors;
pub const DispatchErrors = dispatcher_errors.DispatchErrors;


pub const RegisterOptions = struct {
    raw_params: bool = false,
};

pub const Registry = struct {
    const Self = @This();

    alloc:      Allocator,
    handlers:   StringHashMap(HandlerInfo),

    pub fn init(allocator: Allocator) Self {
        return .{
            .alloc = allocator,
            .handlers = StringHashMap(HandlerInfo).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.handlers.deinit();
    }

    pub fn register(self: *Self, method: []const u8, handler_fn: anytype, opt: RegisterOptions) !void {
        if (std.mem.startsWith(u8, method, "rpc.")) {
            return RegistrationErrors.InvalidMethodName;    // By spec, "rpc." is reserved.
        }
        const handle_info = HandlerInfo {
            .handler_fn = try toHandlerFn(handler_fn, opt),
            .raw_params = opt.raw_params,
        };
        try self.handlers.put(method, handle_info);
    }

    pub fn get(self: *Self, method: []const u8) ?HandlerInfo {
        return self.handlers.get(method);
    }

    /// Run a handler on the request and generate a Response JSON string.
    /// Call freeResponse() to free the string.
    pub fn run(self: *Self, req: RpcRequest) ![]const u8 {
        if (req.hasError()) {
            // For parsing or validation error on the request, return an error response.
            return self.responseError(req.id, @intFromEnum(req.err.code), req.err.err_msg);
        }
        if (self.dispatch(req)) |result_json| {
            defer self.alloc.free(result_json);
            return self.response(req, result_json);
        } else |dispatch_err| {
            // Return any dispatching error as an error response.
            const code, const msg = errorToMsg(dispatch_err);
            return self.responseError(req.id, code, msg);
        }
    }

    /// Free the Response JSON string returned by run().
    pub fn freeResponse(self: *Self, response_json: []const u8) void {
        self.alloc.free(response_json);
    }

    fn dispatch(self: *Self, req: RpcRequest) anyerror![]const u8 {
        const handler_info  = self.get(req.method) orelse return DispatchErrors.MethodNotFound;
        const handler_fn    = handler_info.handler_fn;

        if (handler_info.raw_params) {
            if (req.params != .object) return DispatchErrors.WrongRequestParamTypeForRawParams;
            return handler_fn.fnVal(self.alloc, req.params);
        } else {
            return switch (req.params) {
                .null   =>          self.dispatchOnNone(req, handler_fn),
                .array  => |array|  self.dispatchOnArray(req, handler_fn, array),
                .object => |object| self.dispatchOnObject(req, handler_fn, object),
                else    => DispatchErrors.InvalidParams,
            };
        }
    }

    fn dispatchOnNone(self: *Self, req: RpcRequest, handler_fn: HandlerFn) anyerror![]const u8 {
        _=req;
        if (paramLen(handler_fn)) |nparams| {
            if (nparams > 0) return DispatchErrors.MismatchedParameterCounts;
        } else {
            return DispatchErrors.MismatchedParameterCounts;
        }
        return switch (handler_fn) {
            .fn0 => |f| f(self.alloc),
            else => DispatchErrors.MismatchedParameterCounts,
        };
    }

    fn dispatchOnArray(self: *Self, req: RpcRequest, handler_fn: HandlerFn, array: Array) anyerror![]const u8 {
        _=req;

        // Dispatch on array based parameter.
        if (handler_fn == .fnArr) return handler_fn.fnArr(self.alloc, array);

        // Dispatch on fixed-length based parameters.
        const p = array.items;
        if (paramLen(handler_fn) != p.len) return DispatchErrors.MismatchedParameterCounts;
        return switch (handler_fn) {
            .fn0 => |f| f(self.alloc),
            .fn1 => |f| f(self.alloc, p[0]),
            .fn2 => |f| f(self.alloc, p[0], p[1]),
            .fn3 => |f| f(self.alloc, p[0], p[1], p[2]),
            .fn4 => |f| f(self.alloc, p[0], p[1], p[2], p[3]),
            .fn5 => |f| f(self.alloc, p[0], p[1], p[2], p[3], p[4]),
            .fn6 => |f| f(self.alloc, p[0], p[1], p[2], p[3], p[4], p[5]),
            .fn7 => |f| f(self.alloc, p[0], p[1], p[2], p[3], p[4], p[5], p[6]),
            .fn8 => |f| f(self.alloc, p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7]),
            .fn9 => |f| f(self.alloc, p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8]),
            .fnArr => unreachable,  // already handled previously; shouldn't here.
            .fnObj => unreachable,  // already handled previously; shouldn't here.
            .fnVal => unreachable,  // already handled previously; shouldn't here.
        };
    }

    fn dispatchOnObject(self: *Self, req: RpcRequest, handler_fn: HandlerFn, obj: ObjectMap) anyerror![]const u8 {
        _=req;
        return switch (handler_fn) {
            .fnObj  => |f| f(self.alloc, obj),
            else    => DispatchErrors.NoHandlerForObjectParam,
        };
    }

    /// Build a Response message, or an Error message if there was a parse error.
    /// Caller needs to call self.alloc.free() on the returned message free the memory.
    fn response(self: Self, req: RpcRequest, result_json: []const u8) ![]const u8 {
        if (req.hasError()) {
            return self.responseError(req.id, @intFromEnum(req.err.code), req.err.err_msg);
        }
        return switch (req.id) {
            .num => allocPrint(self.alloc, \\{{ "jsonrpc": "2.0", "result": {s}, "id": {} }}
                                   , .{result_json, req.id.num}),
            .str => allocPrint(self.alloc, \\{{ "jsonrpc": "2.0", "result": {s}, "id": "{s}" }}
                                   , .{result_json, req.id.str}),
            .null => JrErrors.NotificationHasNoResponse,
        };
    }

    /// Build an Error message.
    /// Caller needs to call self.alloc.free() on the returned message free the memory.
    fn responseError(self: Self, id: RpcId, code: i64, msg: []const u8) ![]const u8 {
        return switch (id) {
            .num => allocPrint(self.alloc,
                               \\{{ "jsonrpc": "2.0",  "id": {},
                               \\   "error": {{ "code": {}, "message": "{s}" }}
                               \\}}
                               , .{id.num, code, msg}),
            .str => allocPrint(self.alloc,
                               \\{{ "jsonrpc": "2.0",  "id": "{s}",
                               \\   "error": {{ "code": {}, "message": "{s}" }}
                               \\}}
                               , .{id.str, code, msg}),
            .null => allocPrint(self.alloc,
                               \\{{ "jsonrpc": "2.0",  "id": null,
                               \\   "error": {{ "code": {}, "message": "{s}" }}
                               \\}}
                               , .{code, msg}),
        };
    }

};

const HandlerInfo = struct {
    handler_fn: HandlerFn,
    raw_params: bool,
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
    fn0: *const fn(Allocator) anyerror![]const u8,
    fn1: *const fn(Allocator, Value) anyerror![]const u8,
    fn2: *const fn(Allocator, Value, Value) anyerror![]const u8,
    fn3: *const fn(Allocator, Value, Value, Value) anyerror![]const u8,
    fn4: *const fn(Allocator, Value, Value, Value, Value) anyerror![]const u8,
    fn5: *const fn(Allocator, Value, Value, Value, Value, Value) anyerror![]const u8,
    fn6: *const fn(Allocator, Value, Value, Value, Value, Value, Value) anyerror![]const u8,
    fn7: *const fn(Allocator, Value, Value, Value, Value, Value, Value, Value) anyerror![]const u8,
    fn8: *const fn(Allocator, Value, Value, Value, Value, Value, Value, Value, Value) anyerror![]const u8,
    fn9: *const fn(Allocator, Value, Value, Value, Value, Value, Value, Value, Value, Value) anyerror![]const u8,
    fnArr: *const fn(Allocator, Array) anyerror![]const u8,
    fnObj: *const fn(Allocator, ObjectMap) anyerror![]const u8,
    fnVal: *const fn(Allocator, Value) anyerror![]const u8,
};

fn toHandlerFn(handler_fn: anytype, opt: RegisterOptions) !HandlerFn {
    const fn_type_info: Type = @typeInfo(@TypeOf(handler_fn));
    const params = switch (fn_type_info) {
        .@"fn" =>|info_fn| info_fn.params,
        else => return RegistrationErrors.HandlerNotFunction,
    };
    if (params.len == 0) {
        return RegistrationErrors.MissingAllocator;
    }
    const p0type = params[0].type orelse return RegistrationErrors.MissingAllocator;
    if (p0type != Allocator) return RegistrationErrors.MissingAllocator;

    const nparams = params.len - 1;  // one less for the Allocator param

    // Raw-params handler.
    if (opt.raw_params) {
        if (nparams != 1)
            return RegistrationErrors.MismatchedParameterCountsForRawParams;
        const p1type = params[1].type orelse return RegistrationErrors.InvalidParamTypeForRawParams;
        if (p1type != Value) return RegistrationErrors.InvalidParamTypeForRawParams;
        return HandlerFn { .fnVal = handler_fn };
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
        7 => return HandlerFn { .fn7 = handler_fn },
        8 => return HandlerFn { .fn8 = handler_fn },
        9 => return HandlerFn { .fn9 = handler_fn },
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
        .fn7 => 7,
        .fn8 => 8,
        .fn9 => 9,
        else => null,
    };
}

fn errorToMsg(err: anyerror) struct {i32, []const u8} {
    return switch (err) {
        DispatchErrors.MethodNotFound => .{
            @intFromEnum(ErrorCode.MethodNotFound),
            "Method not found.",
        },
        DispatchErrors.InvalidParams => .{
            @intFromEnum(ErrorCode.InvalidParams),
            "Invalid parameters.",
        },
        DispatchErrors.NoHandlerForArrayParam => .{
            @intFromEnum(ErrorCode.InvalidParams),
            "Handler expecting array parameters but got non-array parameters.",
        },
        DispatchErrors.NoHandlerForObjectParam => .{
            @intFromEnum(ErrorCode.InvalidParams),
            "Handler expecting an object parameter but got non-object parameters.",
        },
        DispatchErrors.MismatchedParameterCounts => .{
            @intFromEnum(ErrorCode.InvalidParams),
            "The number of parameters of the request does not match the parameter count of the handler.",
        },
        else => .{
            @intFromEnum(ErrorCode.ServerError),
            @errorName(err),    // return the dispatching error as text msg.
        },
    };
}


