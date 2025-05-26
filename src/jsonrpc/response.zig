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

const req_parser = @import("request.zig");
const RpcId = req_parser.RpcId;

const errors = @import("errors.zig");
const ErrorCode = errors.ErrorCode;
const JrErrors = errors.JrErrors;


pub fn parseRpcResponse(alloc: Allocator, json_str: ?[]const u8) !RpcResponseResult {
    const json = std.mem.trim(u8, json_str orelse "", " ");
    if (json.len > 0) {
        // Parse error is passed back to the caller directly.
        const parsed = try std.json.parseFromSlice(RpcResponseMessage, alloc, json, .{});
        return .{
            .parsed = parsed,
            .response_msg = parsed.value,
        };
    }
    return .{
        .parsed = null,
        .response_msg = .{ .none = {} },
    };
}

pub const RpcResponseResult = struct {
    const Self = @This();
    parsed:         ?std.json.Parsed(RpcResponseMessage) = null,
    response_msg:   RpcResponseMessage = .{ .none = {} },

    pub fn deinit(self: *Self) void {
        if (self.parsed) |parsed| parsed.deinit();
    }

    pub fn isResponse(self: Self) bool {
        return self.response_msg == .response;
    }

    pub fn isBatch(self: Self) bool {
        return self.response_msg == .batch;
    }

    pub fn isNone(self: Self) bool {
        return self.response_msg == .none;
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
    response:   RpcResponse,                // JSON-RPC's single response.
    batch:      []RpcResponse,              // JSON-RPC's batch of responses.
    none:       void,                       // signifies no response, i.e. notification.

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
    @"error":   RpcResponseError = .{},     // parse error and validation error.

    pub fn err(self: Self) RpcResponseError {
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

    pub fn resultEql(self: Self, value: anytype) bool {
        return jsonValueEql(self.result, value);
    }

};

pub const RpcResponseError = struct {
    code:       i32 = 0,
    message:    []const u8 = "",
    data:       ?Value = null,
};

/// Best effort comparison against the JSON Value.
pub fn jsonValueEql(json_value: Value, value: anytype) bool {
    const value_info = @typeInfo(@TypeOf(value));
    switch (value_info) {
        .null       => {
            switch (json_value) {
                .null       => return true,
                else        => return false,
            }
        },
        .bool       => {
            switch (json_value) {
                .bool       => return json_value.bool == value,
                else        => return false,
            }
        },
        .comptime_int,
        .int        => {
            switch (json_value) {
                .integer    => return json_value.integer == value,
                .float      => return json_value.float == @as(f64, @floatFromInt(value)),
                else        => return false,
            }
        },
        .comptime_float,
        .float      => {
            switch (json_value) {
                .integer    => return @as(f64, @floatFromInt(json_value.integer)) == value,
                .float      => return json_value.float == value,
                else        => return false,
            }
        },
        .pointer    => {
            const elem_info = @typeInfo(value_info.pointer.child);
            switch (json_value) {
                .string     => return elem_info == .array and elem_info.array.child == u8 and
                                        std.mem.eql(u8, json_value.string, value),
                else        => return false,
            }
        },
        .array      => {
            switch (json_value) {
                .string     => return value_info.array.child == u8 and
                                        std.mem.eql(u8, json_value.string, &value),
                else        => return false,
            }
        },
        else        => {
            // std.debug.print("value type info: {any}\n", .{value_info});
            // return false;
            @compileError("Only simple value can only be compared.");
        },
    }
}


