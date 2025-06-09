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
const Value = std.json.Value;
const Array = std.json.Array;
const ObjectMap = std.json.ObjectMap;

const zigjr = @import("../zigjr.zig");

const RpcRequest = zigjr.request.RpcRequest;
const DispatchResult = zigjr.DispatchResult;
const DispatchErrors = zigjr.DispatchErrors;

const json_call = @import("json_call.zig");


pub const RpcRegistry = struct {
    const Self = @This();

    alloc:      Allocator,
    handlers:   StringHashMap(json_call.RpcHandler),

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

    pub fn register(self: *Self, method: []const u8, context: anytype, comptime handler_fn: anytype) !void {
        try validateMethod(method);
        if (@typeInfo(@TypeOf(context)) == .null) {
            var nul_context = {};                   // empty struct for no context.
            const h = try json_call.makeRpcHandler(&nul_context, handler_fn, self.alloc);
            try self.handlers.put(method, h);
        } else {
            const h = try json_call.makeRpcHandler(context, handler_fn, self.alloc);
            try self.handlers.put(method, h);
        }
    }

    pub fn has(self: *Self, method: []const u8) bool {
        return self.handlers.getPtr(method) != null;
    }

    /// Run a handler on the request and generate a DispatchResult.
    /// Return any error during the function call.  Caller handles any error.
    /// Call free() to free the DispatchResult.
    pub fn dispatch(self: *Self, _: Allocator, req: RpcRequest) anyerror!DispatchResult {
        var h = self.handlers.getPtr(req.method) orelse return DispatchErrors.MethodNotFound;
        return h.invoke(req.params);
    }

    pub fn dispatchEnd(self: *Self, alloc: Allocator, req: RpcRequest, dresult: DispatchResult) void {
        // RpcHandler uses ArenaAllocator so no need to explicitly free the dresult.
        _=alloc;
        _=dresult;
        if (self.handlers.getPtr(req.method))|h| {
            h.reset();
        }
    }

};

fn validateMethod(method: []const u8) !void {
    if (std.mem.startsWith(u8, method, "rpc.")) {   // By the JSON-RPC spec, "rpc." is reserved.
        return RegistrationErrors.InvalidMethodName;
    }
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


