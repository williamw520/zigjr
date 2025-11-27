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

/// Handler names for hooks on different stages of request handling:
pub const H_PRE_REQUEST = "rpc.pre-request";    // called before a request is handled.
pub const H_FALLBACK    = "rpc.fallback";       // called when no handler is found for the request.
pub const H_END_REQUEST = "rpc.end-request";    // called after the result is sent back.
pub const H_ON_ERROR    = "rpc.on-error";       // called when handler returns an error.

/// Maintain a list of handlers to handle the RPC requests.
/// Implements the RequestDispatcher interface.
/// The dispatcher is thread-safe in general once it's set up, as long as
/// the addXX and setXX() methods are not called afterward.
pub const RpcDispatcher = struct {
    const Self = @This();

    handlers:           StringHashMap(json_call.RpcHandler),

    pub fn init(alloc: Allocator) error{OutOfMemory}!Self {
        var self: Self = .{
            .handlers = StringHashMap(json_call.RpcHandler).init(alloc),
        };
        try self.addInner(H_PRE_REQUEST, null, defaultPreRequest);
        try self.addInner(H_FALLBACK, null, defaultFallback);
        try self.addInner(H_END_REQUEST, null, defaultEndRequest);
        try self.addInner(H_ON_ERROR, null, defaultOnError);
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.handlers.deinit();
    }

    pub fn add(self: *Self, method: []const u8, comptime handler_fn: anytype) RegistrationErrors!void {
        return self.addWithCtx(method, null, handler_fn);
    }    

    pub fn addWithCtx(self: *Self, method: []const u8, context: anytype,
                      comptime handler_fn: anytype) RegistrationErrors!void {
        try validateMethod(method);

        // Free any existing handler of the same method name.
        _ = self.handlers.fetchRemove(method);
        try self.addInner(method, context, handler_fn);
    }

    fn addInner(self: *Self, method: []const u8, context: anytype,
                comptime handler_fn: anytype) error{OutOfMemory}!void {
        var dummy_null_ctx = {};
        const ctx = if (@typeInfo(@TypeOf(context)) == .null) &dummy_null_ctx else context;
        const h = json_call.makeRpcHandler(ctx, handler_fn);
        try self.handlers.put(method, h);
    }

    pub fn has(self: *const Self, method: []const u8) bool {
        return self.handlers.getPtr(method) != null;
    }

    /// Run a handler on the request and generate a DispatchResult.
    /// Return any error during the function call.  Caller handles any error.
    /// Call free() to free the DispatchResult.
    // TODO: remove anyerror. Remove DispatchResult; move it to dc.
    pub fn dispatch(self: *const Self, dc: *DispatchCtx, req: *const RpcRequest) anyerror!DispatchResult {
        dc.request = req;
        self.callHook(dc, H_PRE_REQUEST);

        return self.callMethod(dc) catch |err| {
            // TODO: set dc.err and result
            self.callHook(dc, H_ON_ERROR);
            return DispatchResult.withAnyErr(err);
        };
    }

    fn callMethod(self: *const Self, dc: *DispatchCtx) anyerror!DispatchResult {
        const result = if (self.handlers.getPtr(dc.request.method)) |h| blk: {
            break :blk try h.invoke(dc, dc.request.params);
        } else blk: {
            if (self.handlers.getPtr(H_FALLBACK)) |h| {
                break :blk try h.invoke(dc, .{ .null = {}});
            }
            unreachable;
        };
        // TODO: set dc.result
        return result;
    }

    fn callHook(self: *const Self, dc: *DispatchCtx, method: []const u8) void {
        if (self.handlers.getPtr(method)) |h| {
            _ = h.invoke(dc, .{ .null = {} }) catch |e| {
                std.debug.print("Pre-request handler {s} cannot return an error, but got error: {any}\n", .{method, e});
                unreachable;
            };
        } else {
            unreachable;
        }
    }

    pub fn dispatchEnd(self: *const Self, dc: *DispatchCtx) void {
        self.callHook(dc, H_END_REQUEST);
        dc.reset();
        // Caller is responsible to reset the arena after this point.
        // Caller might batch processing several requests before reseting the arena.
    }
};

fn validateMethod(method: []const u8) RegistrationErrors!void {
    if (std.mem.startsWith(u8, method, "rpc.")) {   // By the JSON-RPC spec, "rpc." is reserved.
        return RegistrationErrors.InvalidMethodName;
    }
}

// var NopCtx = {};
// fn onBeforeNop(_: *anyopaque, _: Allocator, _: RpcRequest) void {}
// fn onAfterNop(_: *anyopaque, _: Allocator, _: RpcRequest, _: DispatchResult) void {}
// fn onEndNop(_: *anyopaque, _: Allocator, _: RpcRequest, _: DispatchResult) void {}
// fn onErrorNop(_: *anyopaque, _: Allocator, _: RpcRequest, _: anyerror) void {}

fn defaultPreRequest(_: *DispatchCtx) void {}
fn defaultEndRequest(_: *DispatchCtx) void {}
fn defaultOnError(_: *DispatchCtx) void {}
fn defaultFallback(_: *DispatchCtx) anyerror!DispatchResult {
    return DispatchErrors.MethodNotFound;
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
    FallbackHandlerMustHaveValueParam,
    OutOfMemory,
};


