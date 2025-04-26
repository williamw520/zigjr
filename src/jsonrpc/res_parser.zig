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

const req_parser = @import("req_parser.zig");
const RpcId = req_parser.RpcId;

const jsonrpc_errors = @import("jsonrpc_errors.zig");
const ErrorCode = jsonrpc_errors.ErrorCode;
const JrErrors = jsonrpc_errors.JrErrors;


pub fn parseResponse(alloc: Allocator, json_str: []const u8) !RpcResponse {
    const parsed = try std.json.parseFromSlice(RpcResponseBody, alloc, json_str, .{});
    return .{
        .alloc = alloc,
        .parsed = parsed,
        .jsonrpc = parsed.value.jsonrpc,
        .id = parsed.value.id,
        .result = parsed.value.result,
        .err = parsed.value.@"error",
    };
}

pub const RpcResponse = struct {
    const Self = @This();
    alloc:      Allocator,
    parsed:     ?std.json.Parsed(RpcResponseBody) = null,
    jsonrpc:    [3]u8,
    id:         RpcId,
    result:     Value,
    err:        RpcResponseErr,

    pub fn deinit(self: *Self) void {
        if (self.parsed) |parsed| parsed.deinit();
    }

    pub fn hasResult(self: *Self) bool {
        return self.result != .null;
    }

    pub fn hasErr(self: *Self) bool {
        return self.err.code != 0;
    }
};

const RpcResponseBody = struct {
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



