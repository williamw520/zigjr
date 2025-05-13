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
const assert = std.debug.assert;

const parser = @import("request.zig");
const RpcId = parser.RpcId;

const errors = @import("errors.zig");
const ErrorCode = errors.ErrorCode;
const JrErrors = errors.JrErrors;
const AllocError = errors.AllocError;


/// Build a request message in JSON.
/// Caller needs to call alloc.free() on the returned message to free the memory.
pub fn requestJson(alloc: Allocator, method: []const u8, params: anytype, id: RpcId) JrErrors![]const u8 {
    const pinfo = @typeInfo(@TypeOf(params));
    if (pinfo != .array and pinfo != .@"struct" and pinfo != .null) {
        return JrErrors.InvalidParamsType;
    }
    if (pinfo != .null) {
        const params_json = try std.json.stringifyAlloc(alloc, params, .{});
        defer alloc.free(params_json);
        switch (id) {
            .num => return allocPrint(alloc,
                \\{{"jsonrpc": "2.0", "method": "{s}", "params": {s}, "id": {}}}
                , .{method, params_json, id.num}),
            .str => return allocPrint(alloc,
                \\{{"jsonrpc": "2.0", "method": "{s}", "params": {s}, "id": "{s}"}}
                , .{method, params_json, id.str}),
            .null => return allocPrint(alloc,
                \\{{"jsonrpc": "2.0", "method": "{s}", "params": {s}, "id": null}}
                , .{method, params_json}),
            .none => return allocPrint(alloc,
                \\{{"jsonrpc": "2.0", "method": "{s}", "params": {s}}}
                , .{method, params_json}),
        }
    } else {
        switch (id) {
            .num => return allocPrint(alloc,
                \\{{"jsonrpc": "2.0", "method": "{s}", "id": {}}}
                , .{method, id.num}),
            .str => return allocPrint(alloc,
                \\{{"jsonrpc": "2.0", "method": "{s}", "id": "{s}"}}
                , .{method, id.str}),
            .null => return allocPrint(alloc,
                \\{{"jsonrpc": "2.0", "method": "{s}", "id": null}}
                , .{method}),
            .none => return allocPrint(alloc,
                \\{{"jsonrpc": "2.0", "method": "{s}"}}
                , .{method}),
        }
    }
}

/// Build a batch message of request JSONS.
/// Caller needs to call alloc.free() on the returned message to free the memory.
pub fn batchJson(alloc: Allocator, request_jsons: []const []const u8) JrErrors![]const u8 {
    var count: usize = 0;
    var buffer = ArrayList(u8).init(alloc);
    defer buffer.deinit();

    try buffer.appendSlice("[");
    for (request_jsons) |json| {
        if (count > 0) try buffer.appendSlice(", ");
        try buffer.appendSlice(json);
        count += 1;
    }
    try buffer.appendSlice("]");

    return try alloc.dupe(u8, buffer.items);
}

/// Build a normal response message in JSON.
/// Caller needs to call alloc.free() on the returned message to free the memory.
pub fn responseJson(alloc: Allocator, id: RpcId, result_json: []const u8) AllocError!?[]const u8 {
    return switch (id) {
        .num => try allocPrint(alloc,
            \\{{"jsonrpc": "2.0", "result": {s}, "id": {}}}
            , .{result_json, id.num}),
        .str => try allocPrint(alloc,
            \\{{"jsonrpc": "2.0", "result": {s}, "id": "{s}"}}
            , .{result_json, id.str}),
        .none => null,  // No id for notification.  No response JSON.
        .null => null,  // Notification does not have a response.  No response JSON.
    };
}

/// Build an error response message in JSON.
/// Caller needs to call alloc.free() on the returned message to free the memory.
pub fn responseErrorJson(alloc: Allocator, id: RpcId, errCode: ErrorCode, msg: []const u8) AllocError![]const u8 {
    const code: i32 = @intFromEnum(errCode);
    const msg_txt = if (msg.len == 0) @tagName(errCode) else msg;
    switch (id) {
        .num => return allocPrint(alloc,
            \\{{"jsonrpc": "2.0", "id": {}, "error": {{"code": {}, "message": "{s}"}}}}
            , .{id.num, code, msg_txt}),
        .str => return allocPrint(alloc,
            \\{{"jsonrpc": "2.0", "id": "{s}", "error": {{"code": {}, "message": "{s}"}}}}
            , .{id.str, code, msg_txt}),
        .none => return allocPrint(alloc,
            \\{{"jsonrpc": "2.0", "id": null, "error": {{"code": {}, "message": "{s}"}}}}
            , .{code, msg_txt}),
        .null => return allocPrint(alloc,
            \\{{"jsonrpc": "2.0", "id": null, "error": {{"code": {}, "message": "{s}"}}}}
            , .{code, msg_txt}),
    }
}

/// Build an error response message in JSON, with the error data field set.
/// Caller needs to call alloc.free() on the returned message to free the memory.
pub fn responseErrorDataJson(alloc: Allocator, id: RpcId, errCode: ErrorCode,
                             msg: []const u8, data: []const u8) AllocError![]const u8 {
    const code: i32 = @intFromEnum(errCode);
    switch (id) {
        .num => return allocPrint(alloc,
            \\{{"jsonrpc": "2.0", "id": {}, "error": {{"code": {}, "message": "{s}", "data": {s}}}}}
            , .{id.num, code, msg, data}),
        .str => return allocPrint(alloc,
            \\{{"jsonrpc": "2.0", "id": "{s}", "error": {{"code": {}, "message": "{s}", "data": {s}}}}}
            , .{id.str, code, msg, data}),
        .none => return allocPrint(alloc,
            \\{{"jsonrpc": "2.0", "id": null, "error": {{"code": {}, "message": "{s}", "data": {s}}}}}
            , .{code, msg, data}),
        .null => return allocPrint(alloc,
            \\{{"jsonrpc": "2.0", "id": null, "error": {{"code": {}, "message": "{s}", "data": {s}}}}}
            , .{code, msg, data}),
    }
}


