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
const Scanner = std.json.Scanner;
const ParseOptions = std.json.ParseOptions;
const innerParse = std.json.innerParse;
const ParseError = std.json.ParseError;
const Value = std.json.Value;

const req_parser = @import("request_parser.zig");
const RpcId = req_parser.RpcId;

const jsonrpc_errors = @import("jsonrpc_errors.zig");
const ErrorCode = jsonrpc_errors.ErrorCode;
const JrErrors = jsonrpc_errors.JrErrors;


pub fn parseResponse(alloc: Allocator, json_str: []const u8) !ResponseResult {
    // Parse error is passed back to the caller directly.
    const parsed = try std.json.parseFromSlice(RpcResponseMessage, alloc, json_str, .{});
    return .{
        .alloc = alloc,
        .parsed = parsed,
        .response_msg = parsed.value,
    };
}

pub const ResponseResult = struct {
    const Self = @This();
    alloc:          Allocator,
    parsed:         ?std.json.Parsed(RpcResponseMessage) = null,
    response_msg:   RpcResponseMessage,

    pub fn deinit(self: *Self) void {
        if (self.parsed) |parsed| parsed.deinit();
    }

    pub fn isResponse(self: Self) bool {
        return self.response_msg == .response;
    }

    pub fn isBatch(self: Self) bool {
        return self.response_msg == .batch;
    }

    /// Shortcut to access the inner tagged union invariant response.
    pub fn response(self: *Self) !RpcResponse {
        return if (self.isResponse()) self.response_msg.response else JrErrors.NotSingleRpcResponse;
    }

    /// Shortcut to access the inner tagged union invariant batch.
    pub fn batch(self: *Self) ![]const RpcResponse {
        return if (self.isBatch()) self.response_msg.batch else JrErrors.NotBatchRpcResponse;
    }
    
};

pub const RpcResponseMessage = union(enum) {
    response:   RpcResponse,                // JSON-RPC's single response
    batch:      []RpcResponse,              // JSON-RPC's batch of responses.

    // Custom parsing when the JSON parser encounters a field of this type.
    pub fn jsonParse(alloc: Allocator, source: anytype, options: ParseOptions) !RpcResponseMessage {
        return switch (try source.peekNextTokenType()) {
            .object_begin => .{ .response = try innerParse(RpcResponse, alloc, source, options) },
            .array_begin => .{ .batch = try innerParse([]RpcResponse, alloc, source, options) },
            else => error.UnexpectedToken,  // there're only two cases; any others are error.
        };
    }
};

pub const RpcResponse = struct {
    const Self = @This();
    jsonrpc:    [3]u8 = .{ '0', '.', '0' }, // default to fail validation.
    id:         RpcId = .{ .null = {} },    // default for optional field.
    result:     Value = .{ .null = {} },    // default for optional field.
    @"error":   RpcResponseErr = .{},       // parse error and validation error.

    pub fn err(self: Self) RpcResponseErr {
        return self.@"error";
    }

    pub fn hasResult(self: Self) bool {
        return self.result != .null;
    }

    pub fn hasErr(self: Self) bool {
        return self.err().code != 0 or !self.isValid();
    }

    pub fn isValid(self: Self) bool {
        if (!std.mem.eql(u8, &self.jsonrpc, "2.0")) {
            return false;
        }
        return true;
    }
    
};

pub const RpcResponseErr = struct {
    code:       i32 = 0,
    message:    []const u8 = "",
    data:       ?Value = null,
};



