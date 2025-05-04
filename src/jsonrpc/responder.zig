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

const req_parser = @import("request_parser.zig");
const RpcRequest = req_parser.RpcRequest;
const RpcId = req_parser.RpcId;

const jsonrpc_errors = @import("jsonrpc_errors.zig");
const ErrorCode = jsonrpc_errors.ErrorCode;
const JrErrors = jsonrpc_errors.JrErrors;

const messages = @import("messages.zig");


/// Return value from dispatcher.run() expected by respond() below.
/// For the result JSON and data JSON string, it's best that they're produced by
/// std.json.stringifyAlloc() to ensure a valid JSON string.
pub const DispatchResult = union(enum) {
    none:       void,               // No result, for notification call.
    result:     []const u8,         // JSON string for the result value.
    err:        struct {
        code:   ErrorCode,
        msg:    []const u8 = "",    // Error text string.
        data:   ?[]const u8 = null, // JSON string for additional error data value.
    },
};

/// Run the dispatcher on the request and generate a response JSON string.
/// A 'null' return value signifies the request is a notification.
/// Caller needs to call alloc.free() on the returned message to free the memory.
/// Any error coming from the dispatcher is passed back to caller.
///
/// The 'anytype' dispatcher needs to have a run() method returning a DispatchResult.
/// The 'anytype' dispatcher needs to have a free() method to free the DispatchResult.
pub fn runRequest(alloc: Allocator, req: RpcRequest, dispatcher: anytype) !?[]const u8 {
    if (req.hasError()) {
        // Return an error response for the parsing or validation error on the request.
        return try messages.responseErrorJson(alloc, req.id, req.err().code, req.err().err_msg);
    }

    const dresult: DispatchResult = try dispatcher.run(alloc, req);
    switch (dresult) {
        .none => {
            return null;            // notification request has no result.
        },
        .result => |json| {
            defer dispatcher.free(alloc, dresult);
            return try messages.responseJson(alloc, req.id, json);
        },
        .err => |err| {
            defer dispatcher.free(alloc, dresult);
            if (err.data)|data_json| {
                return try messages.responseErrorDataJson(alloc, req.id, err.code, err.msg, data_json);
            } else {
                return try messages.responseErrorJson(alloc, req.id, err.code, err.msg);
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
/// The 'anytype' dispatcher needs to have a run() method returning a DispatchResult.
/// The 'anytype' dispatcher needs to have a free() method to free the DispatchResult.
pub fn runBatch(alloc: Allocator, reqs: []const RpcRequest, dispatcher: anytype) ![]const u8 {
    var count: usize = 0;
    var buffer = ArrayList(u8).init(alloc);
    defer buffer.deinit();

    try buffer.appendSlice("[");
    for (reqs) |req| {
        const response_json = try runRequest(alloc, req, dispatcher);
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
/// The 'anytype' dispatcher needs to have a run() method returning a DispatchResult.
/// The 'anytype' dispatcher needs to have a free() method to free the DispatchResult.
pub fn runMessage(alloc: Allocator, request_json: []const u8, dispatcher: anytype) !?[]const u8 {
    var req_result = req_parser.parseRequest(alloc, request_json);
    defer req_result.deinit();
    return switch (req_result.request_msg) {
        .request    => |request|  try runRequest(alloc, request, dispatcher),
        .batch      => |requests| try runBatch(alloc, requests, dispatcher),
    };
}


