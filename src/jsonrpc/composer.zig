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
const assert = std.debug.assert;

const RpcId = @import("request.zig").RpcId;
const errors = @import("errors.zig");
const ErrorCode = errors.ErrorCode;
const JrErrors = errors.JrErrors;
const AllocError = errors.AllocError;


/// Write a request message in JSON string to the writer.
pub fn writeRequestJson(method: []const u8, params_json: ?[]const u8,
                        id: RpcId, writer: anytype) JrErrors!void {
    if (params_json) |params| {
        switch (id) {
            .num => try writer.print(
                \\{{"jsonrpc": "2.0", "method": "{s}", "params": {s}, "id": {}}}
                    , .{method, params, id.num}),
            .str => try writer.print(
                \\{{"jsonrpc": "2.0", "method": "{s}", "params": {s}, "id": "{s}"}}
                    , .{method, params, id.str}),
            .null => try writer.print(
                \\{{"jsonrpc": "2.0", "method": "{s}", "params": {s}, "id": null}}
                    , .{method, params}),
            .none => try writer.print(
                \\{{"jsonrpc": "2.0", "method": "{s}", "params": {s}}}
                    , .{method, params}),
        }
    } else {
        switch (id) {
            .num => try writer.print(
                \\{{"jsonrpc": "2.0", "method": "{s}", "id": {}}}
                    , .{method, id.num}),
            .str => try writer.print(
                \\{{"jsonrpc": "2.0", "method": "{s}", "id": "{s}"}}
                    , .{method, id.str}),
            .null => try writer.print(
                \\{{"jsonrpc": "2.0", "method": "{s}", "id": null}}
                    , .{method}),
            .none => try writer.print(
                \\{{"jsonrpc": "2.0", "method": "{s}"}}
                    , .{method}),
        }
    }
}

/// Build a request message in JSON string.
/// Caller needs to call alloc.free() on the returned message to free the memory.
pub fn makeRequestJson(alloc: Allocator, method: []const u8, params: anytype,
                       id: RpcId) JrErrors![]const u8 {
    const pinfo = @typeInfo(@TypeOf(params));
    if (pinfo != .array and pinfo != .@"struct" and pinfo != .null) {
        return JrErrors.InvalidParamsType;
    }

    var output_buf = std.ArrayList(u8).init(alloc);
    if (pinfo != .null) {
        const params_json = try std.json.stringifyAlloc(alloc, params, .{});
        defer alloc.free(params_json);
        try writeRequestJson(method, params_json, id, output_buf.writer());
    } else {
        try writeRequestJson(method, null, id, output_buf.writer());
    }
    return try output_buf.toOwnedSlice();
}

/// Write a batch message of request JSONS to the writer.
pub fn writeBatchRequestJson(request_jsons: []const []const u8, writer: anytype) AllocError!void {
    var count: usize = 0;
    try writer.writeAll("[");
    for (request_jsons) |json| {
        if (count > 0) try writer.writeAll(", ");
        try writer.writeAll(json);
        count += 1;
    }
    try writer.writeAll("]");
}

/// Build a batch message of request JSONS.
/// Caller needs to call alloc.free() on the returned message to free the memory.
pub fn makeBatchRequestJson(alloc: Allocator, request_jsons: []const []const u8) JrErrors![]const u8 {
    var output_buf = std.ArrayList(u8).init(alloc);
    try writeBatchRequestJson(request_jsons, output_buf.writer());
    return try output_buf.toOwnedSlice();
}


/// Write a normal response message in JSON to the writer.
/// Return true for valid response.  For message id that shouldn't have a response, false is returned.
pub fn writeResponseJson(id: RpcId, result_json: []const u8, writer: anytype) AllocError!void {
    switch (id) {
        .num => try writer.print(
            \\{{"jsonrpc": "2.0", "result": {s}, "id": {}}}
                , .{result_json, id.num}),
        .str => try writer.print(
            \\{{"jsonrpc": "2.0", "result": {s}, "id": "{s}"}}
                , .{result_json, id.str}),
        else => unreachable,        // Response must have an ID.
    }
}

/// Build a normal response message in JSON string.
/// For message id that shouldn't have a response, null is returned.
/// Caller needs to call alloc.free() on the returned message to free the memory.
pub fn makeResponseJson(alloc: Allocator, id: RpcId, result_json: []const u8) AllocError!?[]const u8 {
    if (id.isNotification())
        return null;
    var output_buf = std.ArrayList(u8).init(alloc);
    try writeResponseJson(id, result_json, output_buf.writer());
    return try output_buf.toOwnedSlice();
}

/// Writer an error response message in JSON to the writer.
pub fn writeErrorResponseJson(id: RpcId, err_code: ErrorCode, msg: []const u8,
                              writer: anytype) AllocError!void {
    const code: i32 = @intFromEnum(err_code);
    const err_msg = if (msg.len == 0) @tagName(err_code) else msg;
    switch (id) {
        .num => try writer.print(
            \\{{"jsonrpc": "2.0", "id": {}, "error": {{"code": {}, "message": "{s}"}}}}
                , .{id.num, code, err_msg}),
        .str => try writer.print(
            \\{{"jsonrpc": "2.0", "id": "{s}", "error": {{"code": {}, "message": "{s}"}}}}
                , .{id.str, code, err_msg}),
        .none => try writer.print(
            \\{{"jsonrpc": "2.0", "id": null, "error": {{"code": {}, "message": "{s}"}}}}
                , .{code, err_msg}),
        .null => try writer.print(
            \\{{"jsonrpc": "2.0", "id": null, "error": {{"code": {}, "message": "{s}"}}}}
                , .{code, err_msg}),
    }
}

/// Build an error response message in JSON string.
/// Caller needs to call alloc.free() on the returned message to free the memory.
pub fn makeErrorResponseJson(alloc: Allocator, id: RpcId, err_code: ErrorCode,
                           msg: []const u8) AllocError![]const u8 {
    var output_buf = std.ArrayList(u8).init(alloc);
    try writeErrorResponseJson(id, err_code, msg, output_buf.writer());
    return try output_buf.toOwnedSlice();
}

/// Build an error response message in JSON, with the error data field set.
/// Caller needs to call alloc.free() on the returned message to free the memory.
pub fn writeErrorDataResponseJson(id: RpcId, err_code: ErrorCode, msg: []const u8,
                                  data: []const u8, writer: anytype) AllocError!void {
    const code: i32 = @intFromEnum(err_code);
    switch (id) {
        .num => try writer.print(
            \\{{"jsonrpc": "2.0", "id": {}, "error": {{"code": {}, "message": "{s}", "data": {s}}}}}
                , .{id.num, code, msg, data}),
        .str => try writer.print(
            \\{{"jsonrpc": "2.0", "id": "{s}", "error": {{"code": {}, "message": "{s}", "data": {s}}}}}
                , .{id.str, code, msg, data}),
        .none => try writer.print(
            \\{{"jsonrpc": "2.0", "id": null, "error": {{"code": {}, "message": "{s}", "data": {s}}}}}
                , .{code, msg, data}),
        .null => try writer.print(
            \\{{"jsonrpc": "2.0", "id": null, "error": {{"code": {}, "message": "{s}", "data": {s}}}}}
                , .{code, msg, data}),
    }
}

/// Build an error response message in JSON, with the error data field set.
/// Caller needs to call alloc.free() on the returned message to free the memory.
pub fn makeErrorDataResponseJson(alloc: Allocator, id: RpcId, err_code: ErrorCode,
                                 msg: []const u8, data: []const u8) AllocError![]const u8 {
    var output_buf = std.ArrayList(u8).init(alloc);
    try writeErrorDataResponseJson(id, err_code, msg, data, output_buf.writer());
    return try output_buf.toOwnedSlice();
}


