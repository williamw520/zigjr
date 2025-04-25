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
const Value = std.json.Value;

const parser = @import("parser.zig");
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
    };
}


pub const RpcResponse = struct {
    const Self = @This();
    alloc:      Allocator,
    parsed:     ?std.json.Parsed(RpcResponseBody) = null,
    body:       RpcResponseBody,

    pub fn deinit(self: *Self) void {
        if (self.parsed) |parsed| parsed.deinit();
    }

    pub fn hasResult(self: *Self) bool {
        return self.body.result != .null;
    }

    pub fn isErr(self: *Self) bool {
        return self.body.@"error".code != 0;
    }

    pub fn result(self: *Self) !Value {
        return if (self.hasResult()) self.body.result else JrErrors.NotResultResponse;
    }

    pub fn err(self: *Self) !RpcResponseErr {
        return if (self.isErr()) self.body.@"error" else JrErrors.NotErrResponse;
    }
};

pub const RpcResponseBody = struct {
    jsonrpc:    [3]u8 = .{ '0', '.', '0' }, // default to fail validation.
    id:         RpcId = .{ .null = {} },    // default for optional field.
    result:     Value = .{ .null = {} },    // default for optional field.
    @"error":   RpcResponseErr = .{},       // parse error and validation error.
};

pub const RpcResponseErr = struct {
    code:       i32 = 0,
    message:    []const u8 = "",
    data:       ?Value = null,
};

pub fn parseResponse(alloc: Allocator, json_str: []const u8) !RpcResponse {
    const parsed = try std.json.parseFromSlice(RpcResponseBody, alloc, json_str, .{});
    return .{
        .alloc = alloc,
        .parsed = parsed,
        .body = parsed.value,
    };
}


