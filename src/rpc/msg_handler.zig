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

const RequestDispatcher = zigjr.RequestDispatcher;
const ResponseDispatcher = zigjr.ResponseDispatcher;
const DispatchResult = zigjr.DispatchResult;
const DispatchErrors = zigjr.DispatchErrors;

const messages = zigjr.messages;


/// Parse the JSON-RPC request message, run the dispatcher on request(s), 
/// and write the JSON-RPC response(s) to the writer.
/// The JSON request message can contain a single request or a batch of requests.
/// Error is turned into a JSON-RPC error response message.
/// The function returns a boolean flag indicating whether any responses have been written,
/// as notification requests have no response.
///
/// The 'anytype' dispatcher needs to have a dispatch() method returning a DispatchResult.
/// The 'anytype' dispatcher needs to have a free() method to free the DispatchResult.
pub fn runRequest(alloc: Allocator, request_json: []const u8, writer: anytype,
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
pub fn runRequestToJson(alloc: Allocator, request_json: []const u8, dispatcher: RequestDispatcher) AllocError!?[]const u8 {
    var response_buf = ArrayList(u8).init(alloc);
    if (try runRequest(alloc, request_json, response_buf.writer(), dispatcher)) {
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
pub fn runRequestToResponse(alloc: Allocator, request_json: []const u8, dispatcher: RequestDispatcher) !RpcResponseResult {
    const response_json = try runRequestToJson(alloc, request_json, dispatcher) orelse "";
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


