// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William W. Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const Allocator = std.mem.Allocator;
const allocPrint = std.fmt.allocPrint;
const ArrayList = std.ArrayList;

const zigjr = @import("../zigjr.zig");
const RpcRequest = zigjr.RpcRequest;
const RpcResponse = zigjr.RpcResponse;
const ErrorCode = zigjr.errors.ErrorCode;


pub const nop_request = RpcRequest{};


pub const DispatchCtxImpl = struct {
    arena:          Allocator,      // per-request arena allocator
    logger:         zigjr.Logger,   // logger is usually set to the passed in logger in RequestPipeline or in the stream API.
    // per-request request and result
    request:        *const zigjr.RpcRequest = &nop_request,
    result:         zigjr.DispatchResult = .asNone(),
    err:            ?anyerror = null,
    // per-request user data; set up by the pre-request and cleaned up by the end-request hook.
    user_props:     *anyopaque = undefined,

    // TODO: add session id, session manager, and others.
    // session_id:     SessionId,
    // session_mgr:    *SessionMgr,
    // session_arena:  Allocator,

    pub fn reset(self: *DispatchCtxImpl) void {
        self.request = &nop_request;
        self.result = .asNone();
        self.err = null;
        // TODO: clean up self.user_props?
    }
};


/// RequestDispatcher interface
/// This is for the request handlers in a RPC server handling the incoming requests.
pub const RequestDispatcher = struct {
    impl_ptr:       *anyopaque,
    dispatch_fn:    *const fn(impl_ptr: *anyopaque, dc: *DispatchCtxImpl) anyerror!DispatchResult,
    dispatchEnd_fn: *const fn(impl_ptr: *anyopaque, dc: *DispatchCtxImpl) void,

    // Interface is implemented by the 'impl' object.
    pub fn implBy(impl_obj: anytype) RequestDispatcher {
        const ImplType = @TypeOf(impl_obj);
        if (@typeInfo(ImplType) != .pointer)
            @compileError("impl_obj should be a pointer, but its type is " ++ @typeName(ImplType));

        const Delegate = struct {
            fn dispatch(impl_ptr: *anyopaque, dc: *DispatchCtxImpl) anyerror!DispatchResult {
                const impl: ImplType = @ptrCast(@alignCast(impl_ptr));
                return impl.dispatch(dc);
            }

            fn dispatchEnd(impl_ptr: *anyopaque, dc: *DispatchCtxImpl) void {
                const impl: ImplType = @ptrCast(@alignCast(impl_ptr));
                return impl.dispatchEnd(dc);
            }
        };

        return .{
            .impl_ptr = impl_obj,
            .dispatch_fn = Delegate.dispatch,
            .dispatchEnd_fn = Delegate.dispatchEnd,
        };
    }

    // The implementation must have these methods.

    pub fn dispatch(self: RequestDispatcher, dc: *DispatchCtxImpl) anyerror!DispatchResult {
        return self.dispatch_fn(self.impl_ptr, dc);
    }

    pub fn dispatchEnd(self: RequestDispatcher, dc: *DispatchCtxImpl) void {
        return self.dispatchEnd_fn(self.impl_ptr, dc);
    }
};


/// ResponseDispatcher interface
/// This is for the response handlers in a RPC client handling the returned responses.
pub const ResponseDispatcher = struct {
    impl_ptr:       *anyopaque,
    dispatch_fn:    *const fn(impl_ptr: *anyopaque, alloc: Allocator, res: RpcResponse) anyerror!bool,

    // Interface is implemented by the 'impl' object.
    pub fn implBy(impl_obj: anytype) ResponseDispatcher {
        const ImplType = @TypeOf(impl_obj);

        const Delegate = struct {
            fn dispatch(impl_ptr: *anyopaque, alloc: Allocator, res: RpcResponse) anyerror!bool {
                const impl: ImplType = @ptrCast(@alignCast(impl_ptr));
                return impl.dispatch(alloc, res);
            }
        };

        return .{
            .impl_ptr = impl_obj,
            .dispatch_fn = Delegate.dispatch,
        };
    }

    pub fn dispatch(self: @This(), alloc: Allocator, res: RpcResponse) anyerror!bool {
        return self.dispatch_fn(self.impl_ptr, alloc, res);
    }
};


/// The returning result from dispatcher.dispatch().
/// For the result JSON string and the err.data JSON string, it's best that they're produced by
/// std.json.stringifyAlloc() to ensure a valid JSON string.
/// The DispatchResult object is cleaned up at the dispatchEnd() stage.
pub const DispatchResult = union(enum) {
    const Self = @This();

    none:           void,               // No result, for notification call.
    end_stream:     void,               // Handler wants to end the current streaming session.
    result:         []const u8,         // JSON string for result value.
    err:            struct {
        code:       ErrorCode,
        msg:        []const u8 = "",    // Error text string.
        data:       ?[]const u8 = null, // JSON string for additional error data value.
    },

    /// Create a DispatchResult with no result, for JSON-RPC notification.
    pub fn asNone() Self {
        return .{ .none = {} };
    }

    /// Create a DispatchResult with end_stream to end the current streaming session.
    pub fn asEndStream() Self {
        return .{ .end_stream = {} };
    }

    /// Create a DispatchResult with a result encoded in a JSON string.
    pub fn withResult(json: []const u8) Self {
        return .{ .result = json };
    }

    /// Create a DispatchResult with an error.
    pub fn withErr(code: ErrorCode, msg: []const u8) Self {
        return .{
            .err = .{
                .code = code,
                .msg = msg,
            }
        };
    }

    /// Create a DispatchResult with the parse error from RpcRequest.
    /// DispatchResult references memory in RpcRequest. Their lifetime must be managed together.
    pub fn withRequestErr(req: *const RpcRequest) Self {
        return .{
            .err = .{
                .code = req.err().code,
                .msg = req.err().err_msg,
            },
        };
    }

    /// Create a DispatchResult with the error of anyerror type.
    pub fn withAnyErr(err: anyerror) Self {
        return switch (err) {
            DispatchErrors.MethodNotFound => Self.withErr(
                ErrorCode.MethodNotFound, "Method not found."),
            DispatchErrors.InvalidParams => Self.withErr(
                ErrorCode.InvalidParams, "Invalid parameters."),
            DispatchErrors.NoHandlerForObjectParam => Self.withErr(
                ErrorCode.InvalidParams, "Handler expecting an object parameter but got non-object parameters."),
            DispatchErrors.MismatchedParamCounts => Self.withErr(
                ErrorCode.InvalidParams, "The number of parameters of the request does not match the parameter count of the handler."),
            else => Self.withErr(ErrorCode.ServerError, @errorName(err)),
        };
    }

};

// Force a pointer type to a const pointer type.
fn ptrToConstPtrType(comptime T: type) type {
    var ptr = @typeInfo(T).pointer;
    ptr.is_const = true;
    return @Type(.{
        .pointer = ptr,
    });
}


pub const DispatchErrors = error {
    NoHandlerForArrayParam,
    NoHandlerForObjectParam,
    MismatchedParamCounts,
    MethodNotFound,
    InvalidParams,
    WrongRequestParamTypeForRawParams,
    OutOfMemory,
};


