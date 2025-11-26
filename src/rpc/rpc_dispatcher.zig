// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William W. Wong. All rights reserved.
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

const zigjr = @import("../zigjr.zig");

const RpcRequest = zigjr.RpcRequest;
const RequestDispatcher = zigjr.RequestDispatcher;
const DispatchResult = zigjr.DispatchResult;
const DispatchErrors = zigjr.DispatchErrors;
const DispatchCtx = zigjr.DispatchCtx;

const json_call = @import("json_call.zig");


/// Extended handler: pre-dispatch handler, called before the request is dispatched.
pub const OnBeforeFn    = fn(ctx: *anyopaque, alloc: Allocator, request: RpcRequest) void;
/// Extended handler: post-dispatch handler, called after the request has been dispatched.
pub const OnAfterFn     = fn(ctx: *anyopaque, alloc: Allocator, request: RpcRequest, dresult: DispatchResult) void;
/// Extended handler: on-dispatch-end, called when dispatchEnd() is called.
pub const OnEndFn       = fn(ctx: *anyopaque, alloc: Allocator, request: RpcRequest, dresult: DispatchResult) void;
/// Extended handler: on-error handler, called when the request causes an error.
pub const OnErrorFn     = fn(ctx: *anyopaque, alloc: Allocator, request: RpcRequest, err: anyerror) void;
/// Extended handler: fallback handler, called when no handler is found for the request's method.
pub const OnFallbackFn  = fn(ctx: *anyopaque, alloc: Allocator, request: RpcRequest) anyerror!DispatchResult;


/// Maintain a list of handlers to handle the RPC requests.
/// Implements the RequestDispatcher interface.
/// The dispatcher is thread-safe in general once it's set up, as long as
/// the addXX and setXX() methods are not called afterward.
pub const RpcDispatcher = struct {
    const Self = @This();

    handlers:           StringHashMap(json_call.RpcHandler),
    on_before_fn:       *const OnBeforeFn,
    on_after_fn:        *const OnAfterFn,
    on_end_fn:          *const OnEndFn,
    on_error_fn:        *const OnErrorFn,
    on_fallback_fn:     ?*const OnFallbackFn = null,
    on_before_ctx:      *anyopaque,
    on_after_ctx:       *anyopaque,
    on_end_ctx:         *anyopaque,
    on_error_ctx:       *anyopaque,
    on_fallback_ctx:    *anyopaque,

    pub fn init(alloc: Allocator) Self {
        return .{
            .handlers = StringHashMap(json_call.RpcHandler).init(alloc),
            .on_before_fn   = onBeforeNop,
            .on_after_fn    = onAfterNop,
            .on_end_fn      = onEndNop,
            .on_error_fn    = onErrorNop,
            .on_fallback_fn = null,
            .on_before_ctx  = &NopCtx,
            .on_after_ctx   = &NopCtx,
            .on_end_ctx     = &NopCtx,
            .on_error_ctx   = &NopCtx,
            .on_fallback_ctx= &NopCtx,
        };
    }

    pub fn deinit(self: *Self) void {
        self.handlers.deinit();
    }

    /// Install the pre-dispatch extended handler, called before the request is dispatched.
    pub fn setOnBefore(self: *Self, ctx: ?*anyopaque, on_before_fn: *const OnBeforeFn) void {
        self.on_before_ctx = ctx orelse &NopCtx;
        self.on_before_fn = on_before_fn;
    }

    /// Install the post-dispatch extended handler, called after the request has been handled 
    /// successfully by a registered handler or the fallback handler.
    /// This won't be called with request resulted in error.  See setOnError().
    pub fn setOnAfter(self: *Self, ctx: ?*anyopaque, on_after_fn: *const OnAfterFn) void {
        self.on_after_ctx = ctx orelse &NopCtx;
        self.on_after_fn = on_after_fn;
    }

    /// Install the DispatchEnd extended handler, called after the result has been sent back.
    /// This is for doing any cleanup per-request.
    pub fn setOnEnd(self: *Self, ctx: ?*anyopaque, on_end_fn: *const OnEndFn) void {
        self.on_end_ctx = ctx orelse &NopCtx;
        self.on_end_fn = on_end_fn;
    }

    /// Install the on-error extended handler, called when the request causes an error.
    pub fn setOnError(self: *Self, ctx: ?*anyopaque, on_error_fn: *const OnErrorFn) void {
        self.on_error_ctx = ctx orelse &NopCtx;
        self.on_error_fn = on_error_fn;
    }

    /// Install the extended handler: fallback handler, called when no handler is found for the request's method.
    pub fn setOnFallback(self: *Self, ctx: ?*anyopaque, on_fallback_fn: *const OnFallbackFn) void {
        self.on_fallback_ctx = ctx orelse &NopCtx;
        self.on_fallback_fn = on_fallback_fn;
    }

    pub fn add(self: *Self, method: []const u8, comptime handler_fn: anytype) RegistrationErrors!void {
        return self.addWithCtx(method, null, handler_fn);
    }    

    pub fn addWithCtx(self: *Self, method: []const u8, context: anytype,
                      comptime handler_fn: anytype) RegistrationErrors!void {
        try validateMethod(method);

        // Free any existing handler of the same method name.
        _ = self.handlers.fetchRemove(method);

        var nul_context = {};   // dummy empty struct for no context.
        const ctx = if (@typeInfo(@TypeOf(context)) == .null) &nul_context else context;
        const h = try json_call.makeRpcHandler(ctx, handler_fn);
        try self.handlers.put(method, h);
    }

    pub fn has(self: *const Self, method: []const u8) bool {
        return self.handlers.getPtr(method) != null;
    }

    /// Run a handler on the request and generate a DispatchResult.
    /// Return any error during the function call.  Caller handles any error.
    /// Call free() to free the DispatchResult.
    pub fn dispatch(self: *const Self, dc: *DispatchCtx, req: RpcRequest) anyerror!DispatchResult {
        self.on_before_fn(self.on_before_ctx, dc.arena, req);
        return self.dispatchInner(dc, req) catch |err| {
            self.on_error_fn(self.on_error_ctx, dc.arena, req, err);
            return err;
        };
    }

    fn dispatchInner(self: *const Self, dc: *DispatchCtx, req: RpcRequest) anyerror!DispatchResult {
        if (self.handlers.getPtr(req.method)) |h| {
            const result = try h.invoke(dc, req.params);
            self.on_after_fn(self.on_after_ctx, dc.arena, req, result);
            return result;
        } else if (self.on_fallback_fn) |fallback_fn| {
            const result = try fallback_fn(self.on_fallback_ctx, dc.arena, req);
            self.on_after_fn(self.on_after_ctx, dc.arena, req, result);
            return result;
        } else {
            return DispatchErrors.MethodNotFound;
        }
    }

    pub fn dispatchEnd(self: *const Self, dc: *DispatchCtx, req: RpcRequest, dresult: DispatchResult) void {
        self.on_end_fn(self.on_end_ctx, dc.arena, req, dresult);
    }

};

fn validateMethod(method: []const u8) RegistrationErrors!void {
    if (std.mem.startsWith(u8, method, "rpc.")) {   // By the JSON-RPC spec, "rpc." is reserved.
        return RegistrationErrors.InvalidMethodName;
    }
}


fn onBeforeNop(_: *anyopaque, _: Allocator, _: RpcRequest) void {}
fn onAfterNop(_: *anyopaque, _: Allocator, _: RpcRequest, _: DispatchResult) void {}
fn onEndNop(_: *anyopaque, _: Allocator, _: RpcRequest, _: DispatchResult) void {}
fn onErrorNop(_: *anyopaque, _: Allocator, _: RpcRequest, _: anyerror) void {}
fn onFallbackNop(_: *anyopaque, _: Allocator, _: RpcRequest) anyerror!DispatchResult {
    return DispatchResult.asNone();
}
var NopCtx = {};


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
    FallbackHandlerMustHaveValueParam,
    OutOfMemory,
};


