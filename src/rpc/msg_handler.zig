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

const parseRpcRequest = zigjr.parseRpcRequest;
const RpcRequest = zigjr.RpcRequest;
const RpcId = zigjr.RpcId;

const parseRpcResponse = zigjr.parseRpcResponse;
const RpcResponse = zigjr.RpcResponse;
const RpcResponseResult = zigjr.RpcResponseResult;
const RpcResponseMessage = zigjr.RpcResponseMessage;

const ErrorCode = zigjr.errors.ErrorCode;
const JrErrors = zigjr.errors.JrErrors;
const AllocError = zigjr.errors.AllocError;

const messages = zigjr.messages;


/// The returning result from dispatcher.dispatch(), expected by handleRpcRequest() below.
/// For the result JSON string and the err.data JSON string, it's best that they're produced by
/// std.json.stringifyAlloc() to ensure a valid JSON string.
/// The DispatchResult object is cleaned up at the dispatchEnd() stage.
pub const DispatchResult = union(enum) {
    const Self = @This();

    none:           void,               // No result, for notification call.
    result:         []const u8,         // JSON string for result value.
    err:            struct {
        code:       ErrorCode,
        msg:        []const u8 = "",    // Error text string.
        data:       ?[]const u8 = null, // JSON string for additional error data value.
    },

    pub fn asNone() Self {
        return .{ .none = {} };
    }

    pub fn withResult(result: []const u8) Self {
        return .{ .result = result };
    }

    pub fn withErr(code: ErrorCode, msg: []const u8) Self {
        return .{
            .err = .{
                .code = code,
                .msg = msg,
            }
        };
    }

    pub fn withRequestErr(req: RpcRequest) Self {
        return .{
            .err = .{
                .code = req.err().code,
                .msg = req.err().err_msg,
            },
        };
    }

    fn withAnyErr(err: anyerror) Self {
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

pub const DispatchErrors = error {
    NoHandlerForArrayParam,
    NoHandlerForObjectParam,
    MismatchedParamCounts,
    MethodNotFound,
    InvalidParams,
    WrongRequestParamTypeForRawParams,
    OutOfMemory,
};


/// RequestDispatcher interface
pub const RequestDispatcher = struct {
    impl_ptr:       *anyopaque,
    dispatch_fn:    *const fn(impl_ptr: *anyopaque, alloc: Allocator, req: RpcRequest) anyerror!DispatchResult,
    dispatchEnd_fn: *const fn(impl_ptr: *anyopaque, alloc: Allocator, req: RpcRequest, dresult: DispatchResult) void,

    // Interface is implemented by the 'impl' object.
    pub fn impl_by(impl: anytype) RequestDispatcher {
        const ImplType = @TypeOf(impl);

        const Thunk = struct {
            fn dispatch(impl_ptr: *anyopaque, alloc: Allocator, req: RpcRequest) anyerror!DispatchResult {
                const implementation: ImplType = @ptrCast(@alignCast(impl_ptr));
                return implementation.dispatch(alloc, req);
            }

            fn dispatchEnd(impl_ptr: *anyopaque, alloc: Allocator, req: RpcRequest, dresult: DispatchResult) void {
                const implementation: ImplType = @ptrCast(@alignCast(impl_ptr));
                return implementation.dispatchEnd(alloc, req, dresult);
            }
        };

        return .{
            .impl_ptr = impl,
            .dispatch_fn = Thunk.dispatch,
            .dispatchEnd_fn = Thunk.dispatchEnd,
        };
    }

    fn dispatch(self: @This(), alloc: Allocator, req: RpcRequest) anyerror!DispatchResult {
        return self.dispatch_fn(self.impl_ptr, alloc, req);
    }

    fn dispatchEnd(self: @This(), alloc: Allocator, req: RpcRequest, dresult: DispatchResult) void {
        return self.dispatchEnd_fn(self.impl_ptr, alloc, req, dresult);
    }
};

pub const HandlePipeline = struct {
};

/// Parse the JSON-RPC request message, run the dispatcher on request(s), 
/// and write the JSON-RPC response(s) to the writer.
/// The JSON request message can contain a single request or a batch of requests.
/// Error is turned into a JSON-RPC error response message.
/// The function returns a boolean flag indicating whether any responses have been written,
/// as notification requests have no response.
///
/// The 'anytype' dispatcher needs to have a dispatch() method returning a DispatchResult.
/// The 'anytype' dispatcher needs to have a free() method to free the DispatchResult.
pub fn handleJsonRequest(alloc: Allocator, request_json: []const u8, writer: anytype,
                         dispatcher: RequestDispatcher) AllocError!bool {
    var parsed_result = parseRpcRequest(alloc, request_json);
    defer parsed_result.deinit();
    switch (parsed_result.request_msg) {
        .request    => |req| {
            return try handleRpcRequest(alloc, req, writer, "", "", dispatcher);
        },
        .batch      => |reqs| {
            try handleRpcRequests(alloc, reqs, dispatcher, writer);
            return true;
        },
    }
}

/// Parse the JSON-RPC request message, run the dispatcher on request(s), 
/// and return the JSON-RPC response(s) as a JSON string.
/// The JSON request message can contain a single request or a batch of requests.
/// Error is turned into a JSON-RPC error response message.
/// The function can return null, as notification requests have no response.
///
/// The 'anytype' dispatcher needs to have a dispatch() method returning a DispatchResult.
/// The 'anytype' dispatcher needs to have a free() method to free the DispatchResult.
pub fn handleRequestToJson(alloc: Allocator, request_json: []const u8, dispatcher: RequestDispatcher) AllocError!?[]const u8 {
    var response_buf = ArrayList(u8).init(alloc);
    if (try handleJsonRequest(alloc, request_json, response_buf.writer(), dispatcher)) {
        return try response_buf.toOwnedSlice();
    } else {
        response_buf.deinit();
        return null;
    }
}

/// Parse the JSON-RPC request message, run the dispatcher on request(s), 
/// parse the JSON-RPC response message, and return the RpcResponseResult.
/// Usually after handling the request, the JSON-RPC response message is sent back to the client.
/// The client then parses the JSON-RPC response message.  This skips all those and directly
/// parses the JSON-RPC response message in one shot.  This is mainly for testing.
pub fn handleRequestToResponse(alloc: Allocator, request_json: []const u8, dispatcher: RequestDispatcher) !RpcResponseResult {
    const response_json = try handleRequestToJson(alloc, request_json, dispatcher) orelse "";
    defer alloc.free(response_json);
    return try parseRpcResponse(alloc, response_json);
}

/// Parse the JSON response message and run the dispatcher on RpcResponse(s).
/// The JSON response message can contain a single response or a batch of responses.
/// The 'anytype' dispatcher needs to have a dispatch() method with !void return type.
/// Any parse error is returned to the caller and the dispatcher is not called.
/// Any error coming from the dispatcher is passed back to caller.
/// For batch responses, the first error from the dispatcher stops the processing.
pub fn handleJsonResponse(alloc: Allocator, response_json: ?[]const u8, dispatcher: anytype) !void {
    var parsed_result: RpcResponseResult = try parseRpcResponse(alloc, response_json);
    defer parsed_result.deinit();
    const response_msg: RpcResponseMessage = parsed_result.response_msg;
    return switch (response_msg) {
        .response   => |rpc_response|  try dispatcher.dispatch(alloc, rpc_response),
        .batch      => |rpc_responses| for (rpc_responses)|rpc_response| {
            try dispatcher.dispatch(alloc, rpc_response);
        },
        .none       => {},
    };
}


/// Run the dispatcher on the RpcRequest and write the response JSON to the writer.
/// Returns true if a response message is written, false for not as notification has no response.
/// Any error coming from the dispatcher is passed back to caller.
///
/// The prefix and suffix are written to the writer before and after the response message
/// if it's written.  Prefix and suffix would not be written for a notification request.
///
/// The 'anytype' dispatcher needs to have a dispatch() method returning a DispatchResult.
/// The 'anytype' dispatcher needs to have a free() method to free the DispatchResult.
fn handleRpcRequest(alloc: Allocator, req: RpcRequest, writer: anytype,
                    prefix: []const u8, suffix: []const u8, dispatcher: RequestDispatcher) AllocError!bool {
    if (req.hasError()) {
        // Return an error response for the parsing or validation error on the request.
        try messages.writeErrorResponseJson(req.id, req.err().code, req.err().err_msg, writer);
        return true;
    }

    // Call the request dispatcher to handle the request.
    const dresult: DispatchResult = call: {
        break :call dispatcher.dispatch(alloc, req) catch |err| {
            // Turn dispatching error into DispatchResult.err.
            // Handle errors here so dispatchers don't have to worry about error handling.
            break :call DispatchResult.withAnyErr(err);
        };
    };
    // Do clean up on the result at the end of dispatching.
    defer dispatcher.dispatchEnd(alloc, req, dresult);

    switch (dresult) {
        .none => {
            return false;   // notification request has no result.
        },
        .result => |json| {
            if (req.id.isNotification()) {
                return false;
            }
            try writer.writeAll(prefix);
            try messages.writeResponseJson(req.id, json, writer);
            try writer.writeAll(suffix);
            return true;
        },
        .err => |err| {
            try writer.writeAll(prefix);
            if (err.data)|data_json| {
                try messages.writeErrorDataResponseJson(req.id, err.code, err.msg, data_json, writer);
            } else {
                try messages.writeErrorResponseJson(req.id, err.code, err.msg, writer);
            }
            try writer.writeAll(suffix);
            return true;
        },
    }
}

/// Run the dispatcher on the list of requests one by one and generate 
/// an array of responses for the requests in one JSON response string.
/// Each request has one response item except for notification.
/// Errors are returned as array items in the JSON.
/// Caller needs to call alloc.free() on the returned message to free the memory.
/// Any error coming from the dispatcher is passed back to caller.
///
/// The 'anytype' dispatcher needs to have a dispatch() method returning a DispatchResult.
/// The 'anytype' dispatcher needs to have a free() method to free the DispatchResult.
fn handleRpcRequests(alloc: Allocator, batch: []const RpcRequest, dispatcher: RequestDispatcher,
                     writer: anytype) AllocError!void { // TODO: swap dispatcher and writer
    var count: usize = 0;
    try writer.writeAll("[");
    for (batch) |req| {
        const delimiter = if (count > 0) ", " else "";
        if (try handleRpcRequest(alloc, req, writer, delimiter, "", dispatcher)) {
            count += 1;
        }
    }
    try writer.writeAll("]");
}


