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

const json_call = @import("json_call.zig");


/// Implements the RequestDispatcher interface.
pub const RpcRegistry = struct {
    const Self = @This();

    alloc:          Allocator,
    handlers:       StringHashMap(json_call.RpcHandler),
    ext_handlers:   ?ExtHandlers = null,

    pub fn init(alloc: Allocator) Self {
        return .{
            .alloc = alloc,
            .handlers = StringHashMap(json_call.RpcHandler).init(alloc),
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

    /// Install the extended handlers: pre-dispatch, post-dispatch, and fallback handler.
    /// 'ext_handlers_obj' must adhere to the 'ExtHandlers' interface.
    pub fn setExtHandlers(self: *Self, ext_handlers_obj: anytype) void {
        self.ext_handlers = ExtHandlers.implBy(ext_handlers_obj);
    }

    pub fn add(self: *Self, method: []const u8, comptime handler_fn: anytype) RegistrationErrors!void {
        return self.addWithCtx(method, null, handler_fn);
    }    

    pub fn addWithCtx(self: *Self, method: []const u8, context: anytype,
                      comptime handler_fn: anytype) RegistrationErrors!void {
        try validateMethod(method);

        // Free any existing handler of the same method name.
        if (self.handlers.fetchRemove(method))|entry| {
            var rpc_handler = entry.value;
            rpc_handler.deinit();
        }

        var nul_context = {};   // dummy empty struct for no context.
        const ctx = if (@typeInfo(@TypeOf(context)) == .null) &nul_context else context;
        const h = try json_call.makeRpcHandler(ctx, handler_fn, self.alloc);
        try self.handlers.put(method, h);
    }

    pub fn has(self: *const Self, method: []const u8) bool {
        return self.handlers.getPtr(method) != null;
    }

    /// Run a handler on the request and generate a DispatchResult.
    /// Return any error during the function call.  Caller handles any error.
    /// Call free() to free the DispatchResult.
    pub fn dispatch(self: *const Self, _: Allocator, req: RpcRequest) anyerror!DispatchResult {
        if (self.ext_handlers) |eh| {
            eh.onBefore(self.alloc, req);
        }

        var result: DispatchResult = undefined;
        if (self.handlers.getPtr(req.method)) |h| {
            result = try h.invoke(req.params);
        } else if (self.ext_handlers) |eh| {
            result = try eh.fallback(self.alloc, req);
        } else {
            return DispatchErrors.MethodNotFound;
        }

        if (self.ext_handlers) |eh| {
            eh.onAfter(self.alloc, req, result);
        }
        return result;
    }

    pub fn dispatchEnd(self: *const Self, alloc: Allocator, req: RpcRequest, dresult: DispatchResult) void {
        // RpcHandler uses ArenaAllocator so no need to explicitly free the dresult.
        _=alloc;
        _=dresult;
        if (self.handlers.getPtr(req.method))|h| {
            h.reset();
        }
    }

};

fn validateMethod(method: []const u8) RegistrationErrors!void {
    if (std.mem.startsWith(u8, method, "rpc.")) {   // By the JSON-RPC spec, "rpc." is reserved.
        return RegistrationErrors.InvalidMethodName;
    }
}


/// Interface for extended handlers: pre-dispatch, post-dispatch, and fallback handler.
pub const ExtHandlers = struct {
    impl_ptr:       *anyopaque,
    // Call on every request before dispatching and after dispatching.
    onBefore_fn:    *const fn(impl_ptr: *anyopaque, alloc: Allocator, request: RpcRequest) void,
    onAfter_fn:     *const fn(impl_ptr: *anyopaque, alloc: Allocator, request: RpcRequest,
                              result: DispatchResult) void,
    // Fallback handler for handling unregistered request methods.
    fallback_fn:    *const fn(impl_ptr: *anyopaque, alloc: Allocator, request: RpcRequest) anyerror!DispatchResult,

    pub fn implBy(impl_obj: anytype) ExtHandlers {
        const Delegate = struct {
            fn onBefore(impl_ptr: *anyopaque, alloc: Allocator, request: RpcRequest) void {
                const impl: @TypeOf(impl_obj) = @ptrCast(@alignCast(impl_ptr));
                impl.onBefore(alloc, request);
            }
            fn onAfter(impl_ptr: *anyopaque, alloc: Allocator, request: RpcRequest, result: DispatchResult) void {
                const impl: @TypeOf(impl_obj) = @ptrCast(@alignCast(impl_ptr));
                impl.onAfter(alloc, request, result);
            }
            fn fallback(impl_ptr: *anyopaque, alloc: Allocator, request: RpcRequest) anyerror!DispatchResult {
                const impl: @TypeOf(impl_obj) = @ptrCast(@alignCast(impl_ptr));
                return try impl.fallback(alloc, request);
            }
        };

        return .{
            .impl_ptr = impl_obj,
            .onBefore_fn = Delegate.onBefore,
            .onAfter_fn = Delegate.onAfter,
            .fallback_fn = Delegate.fallback,
        };
    }

    // The implementation must have these methods.
    pub fn onBefore(self: @This(), alloc: Allocator, request: RpcRequest) void {
        self.onBefore_fn(self.impl_ptr, alloc, request);
    }

    pub fn onAfter(self: @This(), alloc: Allocator, request: RpcRequest, result: DispatchResult) void {
        self.onAfter_fn(self.impl_ptr, alloc, request, result);
    }

    pub fn fallback(self: @This(), alloc: Allocator, request: RpcRequest) anyerror!DispatchResult {
        return try self.fallback_fn(self.impl_ptr, alloc, request);
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
    FallbackHandlerMustHaveValueParam,
    OutOfMemory,
};


