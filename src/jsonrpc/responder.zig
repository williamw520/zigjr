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


/// Return value from dispatcher.run() expected by respond() below.
/// The result and data json, if set, will be freed by respond().  It's best that
/// they're produced by std.json.stringifyAlloc() using the passed in allocator to run().
pub const DispatchResult = union(enum) {
    none:       void,               // No result, for notification call.
    result:     []const u8,         // Result json string.  Will be freed by respond().
    err:        struct {
        code:   ErrorCode,
        msg:    []const u8 = "",    // Constant error message.  Will NOT be freed by respond().
        data:   ?[]const u8 = null, // Error data json string.  Will be freed by respond().
    },
};

/// Run a handler on the request and generate a Response JSON string.
/// Caller needs to call alloc.free() on the returned message to free the memory.
pub fn respond(alloc: Allocator, req: RpcRequest, dispatcher: anytype) !?[]const u8 {
    if (req.hasError()) {
        // For parsing or validation error on the request, return an error response.
        return try responseError(alloc, req.id, req.err.code, req.err.err_msg);
    }

    // Limit the 'anytype' dispatcher to have a .run() method returning DispatchResult.
    // Callers need to handle any errors coming from their dispatcher.
    const retval: DispatchResult = try dispatcher.run(alloc, req);
    switch (retval) {
        .none   => {
            return null;            // null for no result on a notification request.
        },
        .result => |result_json| {
            defer alloc.free(result_json);
            return try responseOk(alloc, req.id, result_json);
        },
        .err    => |err| {
            if (err.data)|data_json| {
                defer alloc.free(data_json);
                return try responseErrorData(alloc, req.id, err.code, err.msg, data_json);
            } else {
                return try responseError(alloc, req.id, err.code, err.msg);
            }
        },
    }
}

/// Build a normal response message.
/// Caller needs to call alloc.free() on the returned message to free the memory.
pub fn responseOk(alloc: Allocator, id: RpcId, result_json: []const u8) ![]const u8 {
    switch (id) {
        .num => return allocPrint(alloc,
            \\{{ "jsonrpc": "2.0", "result": {s}, "id": {} }}
            , .{result_json, id.num}),
        .str => return allocPrint(alloc,
            \\{{ "jsonrpc": "2.0", "result": {s}, "id": "{s}" }}
            , .{result_json, id.str}),
        .none => return JrErrors.MissingIdForResponse,  // No id for notification.
        .null => return JrErrors.MissingIdForResponse,  // Notification does not have a response.
    }
}

/// Build an error response message.
/// Caller needs to call alloc.free() on the returned message to free the memory.
pub fn responseError(alloc: Allocator, id: RpcId, errCode: ErrorCode, msg: []const u8) ![]const u8 {
    const code: i32 = @intFromEnum(errCode);
    switch (id) {
        .num => return allocPrint(alloc,
            \\{{ "jsonrpc": "2.0", "id": {}, "error": {{ "code": {}, "message": "{s}" }} }}
            , .{id.num, code, msg}),
        .str => return allocPrint(alloc,
            \\{{ "jsonrpc": "2.0", "id": "{s}", "error": {{ "code": {}, "message": "{s}" }} }}
            , .{id.str, code, msg}),
        .none => return allocPrint(alloc,
            \\{{ "jsonrpc": "2.0", "id": null, "error": {{ "code": {}, "message": "{s}" }} }}
            , .{code, msg}),
        .null => return allocPrint(alloc,
            \\{{ "jsonrpc": "2.0", "id": null, "error": {{ "code": {}, "message": "{s}" }} }}
            , .{code, msg}),
    }
}

/// Build an error response message, with the error data field set.
/// Caller needs to call alloc.free() on the returned message to free the memory.
pub fn responseErrorData(alloc: Allocator, id: RpcId, errCode: ErrorCode,
                         msg: []const u8, data: []const u8) ![]const u8 {
    const code: i32 = @intFromEnum(errCode);
    switch (id) {
        .num => return allocPrint(alloc,
            \\{{ "jsonrpc": "2.0", "id": {}, "error": {{ "code": {}, "message": "{s}", "data": {s} }} }}
            , .{id.num, code, msg, data}),
        .str => return allocPrint(alloc,
            \\{{ "jsonrpc": "2.0", "id": "{s}", "error": {{ "code": {}, "message": "{s}", "data": {s} }} }}
            , .{id.str, code, msg, data}),
        .none => return allocPrint(alloc,
            \\{{ "jsonrpc": "2.0", "id": null, "error": {{ "code": {}, "message": "{s}", "data": {s} }} }}
            , .{code, msg, data}),
        .null => return allocPrint(alloc,
            \\{{ "jsonrpc": "2.0", "id": null, "error": {{ "code": {}, "message": "{s}", "data": {s} }} }}
            , .{code, msg, data}),
    }
}


