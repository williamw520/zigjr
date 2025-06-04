// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const Allocator = std.mem.Allocator;
const allocPrint = std.fmt.allocPrint;
const ArrayList = std.ArrayList;

const request = @import("request.zig");
const parseRpcRequest = request.parseRpcRequest;
const RpcRequest = request.RpcRequest;
const RpcId = request.RpcId;

const response = @import("response.zig");
const parseRpcResponse = response.parseRpcResponse;
const RpcResponse = response.RpcResponse;
const RpcResponseResult = response.RpcResponseResult;
const RpcResponseMessage = response.RpcResponseMessage;

const errors = @import("errors.zig");
const ErrorCode = errors.ErrorCode;
const JrErrors = errors.JrErrors;
const AllocError = errors.AllocError;

const messages = @import("messages.zig");


/// The returning result from dispatcher.dispatch(), expected by handleRpcRequest() below
/// For the result JSON and data JSON string, it's best that they're produced by
/// std.json.stringifyAlloc() to ensure a valid JSON string.
pub const DispatchResult = union(enum) {
    const Self = @This();

    none:           void,               // No result, for notification call.
    result:         []const u8,         // JSON string for result value, allocated, needed freeing.
    result_lit:     []const u8,         // JSON string literal for result, not needed to be freed.
    err:            struct {
        code:       ErrorCode,
        msg:        []const u8 = "",    // Error text string.
        data:       ?[]const u8 = null, // JSON string for additional error data value, allocated.
        msg_alloc:  bool = false,       // Indicate the 'msg' field is allocated or not.
    },

    pub fn asNone() Self {
        return .{ .none = {} };
    }

    pub fn withResult(result: []const u8) Self {
        return .{ .result = result };
    }

    pub fn withResultLit(result_lit: []const u8) Self {
        return .{ .result_lit = result_lit };
    }

    pub fn withErr(code: ErrorCode, msg: []const u8) Self {
        return .{
            .err = .{
                .code = code,
                .msg = msg,
            }
        };
    }

    pub fn withErrAlloc(code: ErrorCode, msg: []const u8, data: []const u8) Self {
        return .{
            .err = .{
                .code = code,
                .msg = msg,
                .msg_alloc = true,
                .data = data,
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
                     dispatcher: anytype) AllocError!bool {
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
pub fn handleRequestToJson(alloc: Allocator, request_json: []const u8, dispatcher: anytype) AllocError!?[]const u8 {
    var response_buf = ArrayList(u8).init(alloc);
    if (try handleJsonRequest(alloc, request_json, response_buf.writer(), dispatcher)) {
        return try response_buf.toOwnedSlice();
    } else {
        response_buf.deinit();
        return null;
    }
}

pub fn handleRequestToResponse(alloc: Allocator, request_json: []const u8, dispatcher: anytype) !RpcResponseResult {
    var response_buf = ArrayList(u8).init(alloc);
    defer response_buf.deinit();
    _ = try handleJsonRequest(alloc, request_json, response_buf.writer(), dispatcher);
    return try parseRpcResponse(alloc, response_buf.items);
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
pub fn handleRpcRequest(alloc: Allocator, req: RpcRequest, writer: anytype,
                        prefix: []const u8, suffix: []const u8, dispatcher: anytype) AllocError!bool {
    if (req.hasError()) {
        // Return an error response for the parsing or validation error on the request.
        try messages.writeErrorResponseJson(req.id, req.err().code, req.err().err_msg, writer);
        return true;
    }

    const dresult: DispatchResult = call: {
        break :call dispatcher.dispatch(alloc, req) catch |err| {
            // Turn dispatching error into DispatchResult.err.
            // Handle errors here so dispatchers don't have to worry about error handling.
            break :call DispatchResult.withAnyErr(err);
        };
    };

    switch (dresult) {
        .none => {
            return false;   // notification request has no result.
        },
        .result => |json| {
            defer dispatcher.free(alloc, dresult);
            if (req.id.isNotification()) {
                return false;
            }
            try writer.writeAll(prefix);
            try messages.writeResponseJson(req.id, json, writer);
            try writer.writeAll(suffix);
            return true;
        },
        .result_lit => |json| {
            if (req.id.isNotification()) {
                return false;
            }
            try writer.writeAll(prefix);
            try messages.writeResponseJson(req.id, json, writer);
            try writer.writeAll(suffix);
            return true;
        },
        .err => |err| {
            defer dispatcher.free(alloc, dresult);
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
pub fn handleRpcRequests(alloc: Allocator, batch: []const RpcRequest, dispatcher: anytype,
                         writer: anytype) AllocError!void {
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


