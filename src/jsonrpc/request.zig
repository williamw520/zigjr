// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const Type = std.builtin.Type;
const Allocator = std.mem.Allocator;
const Parsed = std.json.Parsed;
const Scanner = std.json.Scanner;
const ParseOptions = std.json.ParseOptions;
const innerParse = std.json.innerParse;
const ParseError = std.json.ParseError;
const Value = std.json.Value;
const Array = std.json.Array;
const ObjectMap = std.json.ObjectMap;

const errors = @import("errors.zig");
const ErrorCode = errors.ErrorCode;
const JrErrors = errors.JrErrors;



pub fn parseRpcRequest(alloc: Allocator, json_str: []const u8) RpcRequestResult {
    const parsed = std.json.parseFromSlice(RpcRequestMessage, alloc, json_str, .{}) catch |parse_err| {
        // Create an empty request with the error so callers can have a uniform request handling.
        var empty_req = RpcRequest{};
        empty_req.setParseErr(parse_err);
        return .{
            .request_msg = RpcRequestMessage { .request = empty_req },
            .parsed = null,
        };
    };
    return .{
        .request_msg = parsed.value,
        .parsed = parsed,
    };
}

pub const RpcRequestResult = struct {
    const Self = @This();
    request_msg:    RpcRequestMessage,
    parsed:         ?std.json.Parsed(RpcRequestMessage) = null,

    pub fn deinit(self: *Self) void {
        if (self.parsed) |parsed| parsed.deinit();
    }

    pub fn isRequest(self: Self) bool {
        return self.request_msg == .request;
    }

    pub fn isBatch(self: Self) bool {
        return self.request_msg == .batch;
    }

    /// Shortcut to access the inner tagged union invariant request.
    /// Can also access via switch(request_msg) .request => , .batch =>
    pub fn request(self: *Self) !RpcRequest {
        return if (self.isRequest()) self.request_msg.request else JrErrors.NotSingleRpcRequest;
    }

    /// Shortcut to access the inner tagged union invariant batch.
    pub fn batch(self: *Self) ![]const RpcRequest {
        return if (self.isBatch()) self.request_msg.batch else JrErrors.NotBatchRpcRequest;
    }
};

pub const RpcRequestMessage = union(enum) {
    request:    RpcRequest,                 // JSON-RPC's single request
    batch:      []RpcRequest,               // JSON-RPC's batch of requests

    // Custom parsing when the JSON parser encounters a field of this type.
    pub fn jsonParse(alloc: Allocator, source: anytype, options: ParseOptions) !RpcRequestMessage {
        return switch (try source.peekNextTokenType()) {
            .object_begin => {
                var req = try innerParse(RpcRequest, alloc, source, options);
                req.validate();
                return .{ .request = req };
            },
            .array_begin => {
                const batch = try innerParse([]RpcRequest, alloc, source, options);
                for (batch)|*req| req.validate();
                return .{ .batch = batch };
            },
            else => error.UnexpectedToken,  // there're only two cases; any others are error.
        };
    }
};

pub const RpcRequest = struct {
    const Self = @This();

    jsonrpc:    [3]u8 = .{ '0', '.', '0' }, // default to fail validation.
    method:     []u8 = "",
    params:     Value = .{ .null = {} },    // default for optional field.
    id:         RpcId = .{ .none = {} },    // default for optional field.
    _err:       RpcRequestError = .{},         // attach parsing error and validation error here.

    fn setParseErr(self: *Self, parse_err: ParseError(Scanner)) void {
        self._err = RpcRequestError.fromParseError(parse_err);
    }

    fn validate(self: *Self) void {
        self._err = RpcRequestError.validateRequest(self) orelse .{};
    }

    pub fn err(self: Self) RpcRequestError {
        return self._err;
    }

    pub fn hasError(self: Self) bool {
        return self.err().code != ErrorCode.None;
    }

    pub fn isError(self: Self, code: ErrorCode) bool {
        return self.err().code == code;
    }

    pub fn hasParams(self: Self) bool {
        return self.params != .null;
    }

    pub fn hasArrayParams(self: Self) bool {
        return self.params == .array;
    }

    pub fn hasObjectParams(self: Self) bool {
        return self.params == .object;
    }

    pub fn arrayParams(self: Self) ?std.json.Array {
        return if (self.params == .array) self.params.array else null;
    }

    pub fn objectParams(self: Self) ?std.json.ObjectMap {
        return if (self.params == .object) self.params.object else null;
    }
};

pub const RpcId = union(enum) {
    none:       void,                   // id is missing (not set at all).
    null:       void,                   // id is set to null.
    num:        i64,
    str:        []const u8,

    pub fn jsonParse(alloc: Allocator, source: anytype, options: ParseOptions) !RpcId {
        const value = try innerParse(Value, alloc, source, options);
        return switch (value) {
            .null       => .{ .null = value.null    },
            .integer    => .{ .num = value.integer  },
            .string     => .{ .str = value.string   },
            else        => error.UnexpectedToken,
        };
    }

    pub fn isValid(self: @This()) bool {
        return self == .num or self == .str;
    }

    pub fn isNotification(self: @This()) bool {
        return !self.isValid();
    }

    pub fn isNone(self: @This()) bool {
        return self == .none;
    }

    pub fn isNull(self: @This()) bool {
        return self == .null;
    }

    pub fn eql(self: @This(), value: anytype) bool {
        const value_info = @typeInfo(@TypeOf(value));
        switch (value_info) {
            .comptime_int,
            .int        => return self == .num and self.num == value,
            .pointer    => {
                const element_info = @typeInfo(value_info.pointer.child);
                return element_info == .array and element_info.array.child == u8 and
                        self == .str and std.mem.eql(u8, self.str, value);
            },
            .array      => {
                return value_info.array.child == u8 and
                        self == .str and std.mem.eql(u8, self.str, &value);
            },
            else        => @compileError("RpcId value can only be integer or string."),
        }
    }

};

pub const RpcRequestError = struct {
    const Self = @This();

    code:       ErrorCode = ErrorCode.None,
    err_msg:    []const u8 = "",                // only constant string, no allocation.
    req_id:     RpcId = .{ .null = {} },        // request id related to the error.

    fn fromParseError(parse_err: ParseError(Scanner)) Self {
        return switch (parse_err) {
            error.MissingField, error.UnknownField, error.DuplicateField,
            error.LengthMismatch, error.UnexpectedEndOfInput =>
                .{ .code = ErrorCode.InvalidRequest, .err_msg = @errorName(parse_err) },
            error.Overflow, error.OutOfMemory => 
                .{ .code = ErrorCode.InternalError, .err_msg = @errorName(parse_err) },
            else =>
                .{ .code = ErrorCode.ParseError, .err_msg = @errorName(parse_err) },
        };
    }

    fn validateRequest(body: *RpcRequest) ?Self {
        if (!std.mem.eql(u8, &body.jsonrpc, "2.0")) {
            return .{
                .code = ErrorCode.InvalidRequest,
                .err_msg = "Invalid JSON-RPC version. Must be 2.0.",
                .req_id = body.id,
            };
        }
        if (body.params != .array and body.params != .object and body.params != .null) {
            return .{
                .code = ErrorCode.InvalidParams,
                .err_msg = "'Params' must be an array, an object, or not defined.",
                .req_id = body.id,
            };
        }
        if (body.method.len == 0) {
            return .{
                .code = ErrorCode.InvalidRequest,
                .err_msg = "'Method' is empty.",
                .req_id = body.id,
            };
        }
        return null;    // return null RpcRequestError for validation passed.
    }
    
};


