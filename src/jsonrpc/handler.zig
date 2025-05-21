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


/// Run the dispatcher on the request and generate a response JSON string.
/// A 'null' return value signifies the request is a notification.
/// Caller needs to call alloc.free() on the returned message to free the memory.
/// Any error coming from the dispatcher is passed back to caller.
///
/// The 'anytype' dispatcher needs to have a dispatch() method returning a DispatchResult.
/// The 'anytype' dispatcher needs to have a free() method to free the DispatchResult.
pub fn handleRpcRequest(alloc: Allocator, req: RpcRequest, dispatcher: anytype) AllocError!?[]const u8 {
    if (req.hasError()) {
        // Return an error response for the parsing or validation error on the request.
        return try messages.toErrorResponseJson(alloc, req.id, req.err().code, req.err().err_msg);
    }

    const dresult: DispatchResult = call: {
        break :call dispatcher.dispatch(alloc, req) catch |err| {
            break :call DispatchResult.withAnyErr(err); // turn dispatching error into DispatchResult.err.
        };
    };

    switch (dresult) {
        .none => {
            return null;            // notification request has no result.
        },
        .result => |json| {
            defer dispatcher.free(alloc, dresult);
            return try messages.toResponseJson(alloc, req.id, json);  // no id, no result
        },
        .result_lit => |json| {
            return try messages.toResponseJson(alloc, req.id, json);  // no id, no result
        },
        .err => |err| {
            defer dispatcher.free(alloc, dresult);
            if (err.data)|data_json| {
                return try messages.toErrorDataResponseJson(alloc, req.id, err.code, err.msg, data_json);
            } else {
                return try messages.toErrorResponseJson(alloc, req.id, err.code, err.msg);
            }
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
pub fn handleRpcRequests(alloc: Allocator, batch: []const RpcRequest, dispatcher: anytype) AllocError![]const u8 {
    var count: usize = 0;
    var buffer = ArrayList(u8).init(alloc);
    defer buffer.deinit();

    try buffer.appendSlice("[");
    for (batch) |req| {
        const response_json = try handleRpcRequest(alloc, req, dispatcher);
        if (response_json)|res_json| {
            defer alloc.free(res_json);
            if (count > 0) try buffer.appendSlice(", ");
            try buffer.appendSlice(res_json);
            count += 1;
        }
    }
    try buffer.appendSlice("]");

    return try alloc.dupe(u8, buffer.items);
}

/// Parse the JSON request message, run the dispatcher on request(s), 
/// returns the response in one JSON string.
/// The JSON request message can contain a single request or a batch of requests.
/// Errors are returned as array items in the JSON.
/// Caller needs to call alloc.free() on the returned message to free the memory.
/// Any error coming from the dispatcher is passed back to caller.
///
/// The 'anytype' dispatcher needs to have a dispatch() method returning a DispatchResult.
/// The 'anytype' dispatcher needs to have a free() method to free the DispatchResult.
pub fn handleRequestJson(alloc: Allocator, request_json: []const u8, dispatcher: anytype) AllocError!?[]const u8 {
    var parsed_result = parseRpcRequest(alloc, request_json);
    defer parsed_result.deinit();
    return switch (parsed_result.request_msg) {
        .request    => |req|  try handleRpcRequest(alloc, req, dispatcher),
        .batch      => |reqs| try handleRpcRequests(alloc, reqs, dispatcher),
    };
}


/// Parse the JSON response message, run the dispatcher on response(s), 
/// The JSON response message can contain a single response or a batch of responses.
/// Any error coming from the dispatcher is passed back to caller.
/// The 'anytype' dispatcher needs to have a dispatch() method with !void return type.
pub fn handleResponseJson(alloc: Allocator, response_json: []const u8, dispatcher: anytype) !void {
    var parsed_result = try parseRpcResponse(alloc, response_json);
    defer parsed_result.deinit();
    return switch (parsed_result.response_msg) {
        .response   => |res|   try dispatcher.dispatch(alloc, res),
        .batch      => |batch| for (batch)|res| try dispatcher.dispatch(alloc, res),
    };
}


