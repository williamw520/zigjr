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

const parser = @import("req_parser.zig");
const RpcId = parser.RpcId;

const jsonrpc_errors = @import("jsonrpc_errors.zig");
const ErrorCode = jsonrpc_errors.ErrorCode;
const JrErrors = jsonrpc_errors.JrErrors;


/// Build a request message.
/// Caller needs to call alloc.free() on the returned message to free the memory.
pub fn requestJson(alloc: Allocator, method: []const u8, params: anytype, id: RpcId) ![]const u8 {
    const pinfo = @typeInfo(@TypeOf(params));
    if (pinfo != .array and pinfo != .@"struct" and pinfo != .null) {
        return JrErrors.InvalidParamsType;
    }
    if (pinfo != .null) {
        const params_json = try std.json.stringifyAlloc(alloc, params, .{});
        defer alloc.free(params_json);
        switch (id) {
            .num => return allocPrint(alloc,
                \\{{ "jsonrpc": "2.0", "method": "{s}", "params": {s}, "id": {} }}
                , .{method, params_json, id.num}),
            .str => return allocPrint(alloc,
                \\{{ "jsonrpc": "2.0", "method": "{s}", "params": {s}, "id": "{s}" }}
                , .{method, params_json, id.str}),
            .null => return allocPrint(alloc,
                \\{{ "jsonrpc": "2.0", "method": "{s}", "params": {s}, "id": null }}
                , .{method, params_json}),
            .none => return allocPrint(alloc,
                \\{{ "jsonrpc": "2.0", "method": "{s}", "params": {s} }}
                , .{method, params_json}),
        }
    } else {
        switch (id) {
            .num => return allocPrint(alloc,
                \\{{ "jsonrpc": "2.0", "method": "{s}", "id": {} }}
                , .{method, id.num}),
            .str => return allocPrint(alloc,
                \\{{ "jsonrpc": "2.0", "method": "{s}", "id": "{s}" }}
                , .{method, id.str}),
            .null => return allocPrint(alloc,
                \\{{ "jsonrpc": "2.0", "method": "{s}", "id": null }}
                , .{method}),
            .none => return allocPrint(alloc,
                \\{{ "jsonrpc": "2.0", "method": "{s}" }}
                , .{method}),
        }
    }
}

/// Build a batch message of request jsons.
/// Caller needs to call alloc.free() on the returned message to free the memory.
pub fn batchJson(alloc: Allocator, request_jsons: []const []const u8) !ArrayList(u8) {
    var buffer = ArrayList(u8).init(alloc);
    try buffer.appendSlice("[");
    const joined = try std.mem.join(alloc, ",", request_jsons);
    defer alloc.free(joined);
    try buffer.appendSlice(joined);
    try buffer.appendSlice("]");
    return buffer;
}

/// Build a normal response message.
/// Caller needs to call alloc.free() on the returned message to free the memory.
pub fn responseJson(alloc: Allocator, id: RpcId, result_json: []const u8) ![]const u8 {
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
pub fn responseErrorJson(alloc: Allocator, id: RpcId, errCode: ErrorCode, msg: []const u8) ![]const u8 {
    const code: i32 = @intFromEnum(errCode);
    const msg_txt = if (msg.len == 0) @tagName(errCode) else msg;
    switch (id) {
        .num => return allocPrint(alloc,
            \\{{ "jsonrpc": "2.0", "id": {}, "error": {{ "code": {}, "message": "{s}" }} }}
            , .{id.num, code, msg_txt}),
        .str => return allocPrint(alloc,
            \\{{ "jsonrpc": "2.0", "id": "{s}", "error": {{ "code": {}, "message": "{s}" }} }}
            , .{id.str, code, msg_txt}),
        .none => return allocPrint(alloc,
            \\{{ "jsonrpc": "2.0", "id": null, "error": {{ "code": {}, "message": "{s}" }} }}
            , .{code, msg_txt}),
        .null => return allocPrint(alloc,
            \\{{ "jsonrpc": "2.0", "id": null, "error": {{ "code": {}, "message": "{s}" }} }}
            , .{code, msg_txt}),
    }
}

/// Build an error response message, with the error data field set.
/// Caller needs to call alloc.free() on the returned message to free the memory.
pub fn responseErrorDataJson(alloc: Allocator, id: RpcId, errCode: ErrorCode,
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


