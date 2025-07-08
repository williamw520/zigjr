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
const Owned = @import("../rpc/deiniter.zig").Owned;


/// Parse response_json into a RpcResponseResult.
/// Caller transfers ownership of response_json to RpcResponseResult.
/// They will be freed in the RpcResponseResult.deinit().
pub fn parseRpcResponseOwned(alloc: Allocator, response_json: []const u8) RpcResponseResult {
    var rresult = parseRpcResponse(alloc, response_json);
    rresult.jsonOwned(response_json, alloc);
    return rresult;
}

/// Parse response_json into a RpcResponseResult.
/// Caller manages the lifetime response_json.  Needs to ensure response_json is not
/// freed before RpcResponseResult.deinit(). Parsed result references response_json.
pub fn parseRpcResponse(alloc: Allocator, response_json: []const u8) RpcResponseResult {
    const json = std.mem.trim(u8, response_json, " ");
    if (json.len == 0) {
        return .{ .response_msg = .{ .none = {} } };
    }
    const parsed = std.json.parseFromSlice(RpcResponseMessage, alloc, json, .{}) catch |parse_err| {
        // Create an empty response with the error so callers can have a uniform handling.
        return .{ .response_msg = .{ .response = RpcResponse.ofParseErr(parse_err) } };
    };
    return .{
        .response_msg = parsed.value,
        ._parsed = parsed,
    };
}

pub const RpcResponseResult = struct {
    const Self = @This();
    response_msg:   RpcResponseMessage = .{ .none = {} },
    _parsed:        ?std.json.Parsed(RpcResponseMessage) = null,
    _response_json: Owned([]const u8) = .{},

    pub fn deinit(self: *Self) void {
        if (self._parsed) |parsed| parsed.deinit();
        self._response_json.deinit();
    }

    fn jsonOwned(self: *Self, response_json: []const u8, alloc: Allocator) void {
         self._response_json = Owned([]const u8).init(response_json, alloc);
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
        switch (try source.peekNextTokenType()) {
            .object_begin => {
                var res = try innerParse(RpcResponse, alloc, source, options);
                res.validate();
                return .{ .response = res };
            },
            .array_begin => {
                const batch = try innerParse([]RpcResponse, alloc, source, options);
                for (batch)|*res| res.validate();
                return .{ .batch = batch };
            },
            else => return error.UnexpectedToken,
        }
    }
};

pub const RpcResponse = struct {
    const Self = @This();
    jsonrpc:    [3]u8 = "0.0".*,            // default to fail validation.
    id:         RpcId = .{ .null = {} },    // default for optional field.
    result:     Value = .{ .null = {} },    // default for optional field.
    @"error":   RpcResponseError = .{},     // parse error and validation error.

    fn ofParseErr(parse_err: ParseError(Scanner)) Self {
        var empty_res = RpcResponse{};
        empty_res.@"error" = RpcResponseError.fromParseError(parse_err);
        return empty_res;
    }

    fn validate(self: *Self) void {
        if (RpcResponseError.validateResponse(self)) |e| {
            self.@"error" = e;
        }
    }

    pub fn err(self: Self) RpcResponseError {
        return self.@"error";
    }

    pub fn hasResult(self: Self) bool {
        return self.result != .null;
    }

    pub fn hasErr(self: Self) bool {
        return self.err().code != 0;
    }

    pub fn resultEql(self: Self, value: anytype) bool {
        return jsonValueEql(self.result, value);
    }

};

pub const RpcResponseError = struct {
    const Self = @This();

    code:       i32 = 0,
    message:    []const u8 = "",
    data:       ?Value = null,

    fn fromParseError(parse_err: ParseError(Scanner)) Self {
        return switch (parse_err) {
            error.MissingField, error.UnknownField, error.DuplicateField,
            error.LengthMismatch, error.UnexpectedEndOfInput => .{
                .code = @intFromEnum(ErrorCode.InvalidRequest),
                .message = @errorName(parse_err),
            },
            error.Overflow, error.OutOfMemory => .{
                .code = @intFromEnum(ErrorCode.InternalError),
                .message = @errorName(parse_err),
            },
            else => .{
                .code = @intFromEnum(ErrorCode.ParseError),
                .message = @errorName(parse_err),
            },
        };
    }

    fn validateResponse(body: *RpcResponse) ?Self {
        if (!std.mem.eql(u8, &body.jsonrpc, "2.0")) {
            return .{
                .code = @intFromEnum(ErrorCode.InvalidRequest),
                .message = "Invalid JSON-RPC version. Must be 2.0.",
            };
        }
        return null;    // return null RpcRequestError for validation passed.
    }
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

        
