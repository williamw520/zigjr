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

const parser = @import("req_parser.zig");
const RpcRequest = parser.RpcRequest;
const RpcId = parser.RpcId;

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

/// Run a handler on the request and generate a Response JSON string.
/// Caller needs to call alloc.free() on the returned message to free the memory.
pub fn respond(alloc: Allocator, req: RpcRequest, dispatcher: anytype) !?[]const u8 {
    if (req.hasError()) {
        // Return an error response for the parsing or validation error on the request.
        return try messages.responseErrorJson(alloc, req.id, req.err.code, req.err.err_msg);
    }

    // Limit the 'anytype' dispatcher to have a run() method returning a DispatchResult.
    // Limit the 'anytype' dispatcher to have a free() method to free the DispatchResult.
    // Callers of respond() need to handle any errors coming from their dispatcher.
    // The dispatcher can use 'alloc' to allocate memory for the result data fields.
    // They should be freed in the dispatcher.free() callback.
    const dresult: DispatchResult = try dispatcher.run(alloc, req);
    switch (dresult) {
        .none => {
            return null;            // null for no result on a notification request.
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

