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


/// Run a handler on the request and generate a Response JSON string.
/// Call freeResponse() to free the string.
pub fn response(alloc: Allocator, req: RpcRequest, dispatcher: anytype) ![]const u8 {
    if (req.hasError()) {
        // For parsing or validation error on the request, return an error response.
        return responseError(alloc, req.id, req.err.code, req.err.err_msg);
    }
    if (dispatcher.run(alloc, req)) |result_json| {
        defer alloc.free(result_json);
        return responseOk(alloc, req, result_json);
    } else |dispatch_err| {
        // Return any dispatching error as an error response.
        const code: ErrorCode, const msg: []const u8 = dispatcher.getErrorCodeMsg(dispatch_err);
        return responseError(alloc, req.id, code, msg);
    }
}

/// Build a Response message, or an Error message if there was a parse error.
/// Caller needs to call self.alloc.free() on the returned message free the memory.
fn responseOk(alloc: Allocator, req: RpcRequest, result_json: []const u8) ![]const u8 {
    if (req.hasError()) {
        return responseError(alloc, req.id, req.err.code, req.err.err_msg);
    }
    return switch (req.id) {
        .num => allocPrint(alloc,
            \\{{ "jsonrpc": "2.0", "result": {s}, "id": {} }}
            , .{result_json, req.id.num}),
        .str => allocPrint(alloc,
            \\{{ "jsonrpc": "2.0", "result": {s}, "id": "{s}" }}
            , .{result_json, req.id.str}),
        .null => JrErrors.NotificationHasNoResponse,
        .none => JrErrors.NotificationHasNoResponse,
    };
}

/// Build an Error message.
/// Caller needs to call self.alloc.free() on the returned message free the memory.
fn responseError(alloc: Allocator, id: RpcId, errCode: ErrorCode, msg: []const u8) ![]const u8 {
    const code: i32 = @intFromEnum(errCode);
    return switch (id) {
        .num => allocPrint(alloc,
            \\{{ "jsonrpc": "2.0", "id": {}, "error": {{ "code": {}, "message": "{s}" }} }}
            , .{id.num, code, msg}),
        .str => allocPrint(alloc,
            \\{{ "jsonrpc": "2.0", "id": "{s}", "error": {{ "code": {}, "message": "{s}" }} }}
            , .{id.str, code, msg}),
        .null => allocPrint(alloc,
            \\{{ "jsonrpc": "2.0", "id": null, "error": {{ "code": {}, "message": "{s}" }} }}
            , .{code, msg}),
        .none => allocPrint(alloc,
            \\{{ "jsonrpc": "2.0", "id": null, "error": {{ "code": {}, "message": "{s}" }} }}
            , .{code, msg}),
    };
}


