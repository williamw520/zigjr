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

const request = @import("../jsonrpc/request.zig");
const RpcRequest = request.RpcRequest;

const dispatcher = @import("dispatcher.zig");
const RequestDispatcher = dispatcher.RequestDispatcher;
const DispatchResult = dispatcher.DispatchResult;
const DispatchErrors = dispatcher.DispatchErrors;
const DispatchCtxImpl = dispatcher.DispatchCtxImpl;

const json_call = @import("json_call.zig");
const DispatchCtx = json_call.DispatchCtx;

/// Handler names for hooks on different stages of request handling:
pub const H_PRE_REQUEST = "rpc.pre-request";    // called before a request is handled.
pub const H_FALLBACK    = "rpc.fallback";       // called when no handler is found for the request.
pub const H_END_REQUEST = "rpc.end-request";    // called after the result is sent back.
pub const H_ON_ERROR    = "rpc.on-error";       // called when handler returns an error.

/// Maintain a list of handlers to handle the RPC requests.
/// Implements the RequestDispatcher interface.
/// The dispatcher is thread-safe in general once it's set up, as long as
/// the addXX and setXX() methods are not called afterward.
/// P is the type of data struct for the per-request user props.
pub fn RpcDispatcher(_: type) type {
    const RpcHandlerP = json_call.RpcHandler;
    const DispatchCtxP = DispatchCtx;

    return struct {
        const Self = @This();

        handlers:   StringHashMap(RpcHandlerP),

        pub fn init(alloc: Allocator) RegistrationErrors!Self {
            var self: Self = .{
                .handlers = StringHashMap(RpcHandlerP).init(alloc),
            };
            try self.add(H_PRE_REQUEST, defaultPreRequest);
            try self.add(H_FALLBACK, defaultFallback);
            try self.add(H_END_REQUEST, defaultEndRequest);
            try self.add(H_ON_ERROR, defaultOnError);
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
        pub fn dispatch(self: *const Self, dc: *DispatchCtxImpl) anyerror!DispatchResult {
            var dcp: DispatchCtxP = .{ .dc_impl = dc };

            self.callHook(&dcp, H_PRE_REQUEST);

            const result = self.callMethod(&dcp) catch |err| {
                // TODO: set err as anyerror in dc?
                const result = DispatchResult.withAnyErr(err);
                dcp.setResult(result);
                self.callHook(&dcp, H_ON_ERROR);
                return result;
            };
            dcp.setResult(result);
            return result;
        }

        fn callMethod(self: *const Self, dcp: *DispatchCtxP) anyerror!DispatchResult {
            return if (self.handlers.getPtr(dcp.request().method)) |h| blk1: {
                break :blk1 try h.invoke(dcp, dcp.request().params);
            } else blk2: {
                if (self.handlers.getPtr(H_FALLBACK)) |h| {
                    // Call fallback handler as a regular handler, with its returning result and error.
                    break :blk2 try h.invoke(dcp, .{ .null = {}});
                }
                unreachable;
            };
        }

        fn callHook(self: *const Self, dcp: *DispatchCtxP, method: []const u8) void {
            if (self.handlers.getPtr(method)) |h| {
                _ = h.invoke(dcp, .{ .null = {} }) catch |e| {
                    std.debug.print("Pre-request handler {s} cannot return an error, but got error: {any}\n", .{method, e});
                    unreachable;
                };
            } else {
                unreachable;
            }
        }

        pub fn dispatchEnd(self: *const Self, dc: *DispatchCtxImpl) void {
            var dcp: DispatchCtxP = .{ .dc_impl = dc };
            self.callHook(&dcp, H_END_REQUEST);
            dc.reset();
            // Caller is responsible to reset the arena after this point.
            // Caller might be batch-processing several requests before reseting the arena.
        }
    };
}

fn validateMethod(method: []const u8) RegistrationErrors!void {
    if (std.mem.startsWith(u8, method, "rpc.")) {   // By the JSON-RPC spec, "rpc." is reserved.
        const well_known_hooks =
            std.mem.eql(u8, method, H_PRE_REQUEST) or
            std.mem.eql(u8, method, H_FALLBACK) or
            std.mem.eql(u8, method, H_END_REQUEST) or
            std.mem.eql(u8, method, H_ON_ERROR);
        if (!well_known_hooks)
            return RegistrationErrors.InvalidMethodName;
    }
}

fn defaultPreRequest() void {}
fn defaultEndRequest() void {}
fn defaultOnError() void {}
fn defaultFallback() anyerror!DispatchResult {
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


