// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William W. Wong. All rights reserved.
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
const Owned = @import("../rpc/deiniter.zig").Owned;


/// Parse request_json into a RpcRequestResult.
/// Caller manages the lifetime request_json.  Needs to ensure request_json is not
/// freed before RpcRequestResult.deinit(). Parsed result references request_json.
pub fn parseRpcRequest(alloc: Allocator, request_json: []const u8) RpcRequestResult {
    return parseRpcRequestOpts(alloc, request_json, .{
        .ignore_unknown_fields = true,
    });
}

/// Parse request_json into a RpcRequestResult.
/// Caller transfers ownership of request_json to RpcRequestResult.
/// They will be freed in the RpcRequestResult.deinit().
/// This allows managing the lifetime of request_json and result together.
pub fn parseRpcRequestOwned(alloc: Allocator, request_json: []const u8, opts: ParseOptions) RpcRequestResult {
    var rresult = parseRpcRequestOpts(alloc, request_json, opts);
    rresult.jsonOwned(request_json, alloc);
    return rresult;
}

pub fn parseRpcRequestOpts(alloc: Allocator, request_json: []const u8, opts: ParseOptions) RpcRequestResult {
    const parsed = std.json.parseFromSlice(RpcRequestMessage, alloc, request_json, opts) catch |err| {
        // Return an empty request with the error so callers can have a uniform request handling.
        return .{
            .request_msg = .{ .request = RpcRequest.ofParseErr(err) }
        };
    };
    return .{
        .request_msg = parsed.value,
        ._parsed = parsed,
    };
}

pub const RpcRequestResult = struct {
    const Self = @This();
    request_msg:    RpcRequestMessage,
    _parsed:        ?std.json.Parsed(RpcRequestMessage) = null,
    _request_json:  Owned([]const u8) = .{},

    pub fn deinit(self: *Self) void {
        if (self._parsed) |parsed| parsed.deinit();
        self._request_json.deinit();
    }

    fn jsonOwned(self: *Self, request_json: []const u8, alloc: Allocator) void {
         self._request_json = Owned([]const u8).init(request_json, alloc);
    }

    pub fn isRequest(self: Self) bool {
        return self.request_msg == .request;
    }

    pub fn isBatch(self: Self) bool {
        return self.request_msg == .batch;
    }

    pub fn isMissingMethod(self: Self) bool {
        if (self.request_msg == .request) {
            return self.request_msg.request._no_method;
        } else {
            return false;
        }
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
    _err:       RpcRequestError = .{},      // attach parsing error and validation error here.
    _no_method: bool = false,               // treat MissingField error as no method.

    fn ofParseErr(parse_err: ParseError(Scanner)) Self {
        var empty_req = Self{};
        empty_req._err = RpcRequestError.fromParseError(parse_err);
        empty_req._no_method = (parse_err == error.MissingField);
        return empty_req;
    }

    fn validate(self: *Self) void {
        if (RpcRequestError.validateRequest(self)) |e| {
            self._err = e;
        }
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

    pub fn ofNone() RpcId { return .{ .none = {} }; }
    pub fn ofNull() RpcId { return .{ .null = {} }; }
    pub fn of(id: i64) RpcId { return .{ .num = id }; }
    pub fn ofStr(id: []const u8) RpcId { return .{ .str = id }; }

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
            error.LengthMismatch, error.UnexpectedEndOfInput => .{
                .code = ErrorCode.InvalidRequest,
                .err_msg = @errorName(parse_err),
            },
            error.Overflow, error.OutOfMemory => .{
                .code = ErrorCode.InternalError,
                .err_msg = @errorName(parse_err),
            },
            else => .{
                .code = ErrorCode.ParseError,
                .err_msg = @errorName(parse_err),
            },
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


