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

const jsonrpc_errors = @import("jsonrpc_errors.zig");
const ErrorCode = jsonrpc_errors.ErrorCode;
const JrErrors = jsonrpc_errors.JrErrors;



pub fn parseRequest(alloc: Allocator, json_str: []const u8) RpcResult {
    const parsed = std.json.parseFromSlice(RpcMessage, alloc, json_str, .{}) catch |parse_err| {
        // Create an empty request with the error set so callers can have uniform request handling.
        var req = RpcRequest{};
        req.setParseErr(parse_err);
        return .{
            .alloc = alloc,
            .parsed = null,
            .rpcmsg = RpcMessage { .request = req },
        };
    };
    return .{
        .alloc = alloc,
        .parsed = parsed,
        .rpcmsg = parsed.value,
    };
}

pub fn parseRequestReader(alloc: Allocator, json_reader: anytype) RpcResult {
    var rp = ReaderParser(@TypeOf(json_reader)).init(alloc, json_reader);
    defer rp.deinit();
    // NOTE: Stream parsing of JSON's via Reader is impossible.
    // The assert() in std.json.parseFromTokenSourceLeaky() expects the end of input
    // after parsing just one JSON.
    //      assert(.end_of_document == try scanner_or_reader.next())
    // NOTE: Streaming support needs to be done at a higher level, at the framing protocol level.
    // E.g. Add '\n' between each JSON, or use "content-length: N\r\n\r\n" header.
    const parsed = rp.next() catch |parse_err| {
        var req = RpcRequest{};
        req.setParseErr(parse_err);
        return .{
            .alloc = alloc,
            .parsed = null,
            .rpcmsg = RpcMessage { .request = req },
        };
    };
    return .{
        .alloc = alloc,
        .parsed = parsed,
        .rpcmsg = parsed.value,
    };
}

fn ReaderParser(comptime JsonReaderType: type) type {
    return struct {
        const Self = @This();
        const ScannerReader = std.json.Reader(std.json.default_buffer_size, JsonReaderType);

        alloc:      Allocator,
        jreader:    ScannerReader,

        pub fn init(alloc: Allocator, json_reader: JsonReaderType) Self {
            // ScannerReader bridging the json_reader and a Scanner.
            return .{ .alloc = alloc,  .jreader = ScannerReader.init(alloc, json_reader) };
        }

        pub fn deinit(self: *Self) void {
            self.jreader.deinit();
        }

        pub fn next(self: *Self) !Parsed(RpcMessage) {
            return try std.json.parseFromTokenSource(RpcMessage, self.alloc, &self.jreader, .{});
        }
    };
}

pub const RpcResult = struct {
    const Self = @This();
    alloc:      Allocator,
    parsed:     ?std.json.Parsed(RpcMessage) = null,
    rpcmsg:    RpcMessage,

    pub fn deinit(self: *Self) void {
        if (self.parsed) |parsed| parsed.deinit();
    }

    pub fn isRequest(self: *Self) bool {
        return self.rpcmsg == .request;
    }

    pub fn isBatch(self: *Self) bool {
        return self.rpcmsg == .batch;
    }

    /// Shortcut to access the inner tagged union invariant request.
    /// Can also access via switch(rpcmsg) .request => 
    pub fn request(self: *Self) !RpcRequest {
        return if (self.isRequest()) self.rpcmsg.request else JrErrors.NotSingleRpcRequest;
    }

    /// Shortcut to access the inner tagged union invariant batch.
    pub fn batch(self: *Self) ![]const RpcRequest {
        return if (self.isBatch()) self.rpcmsg.batch else JrErrors.NotBatchRpcRequest;
    }
};

pub const RpcMessage = union(enum) {
    request:    RpcRequest,                 // JSON-RPC's single request
    batch:      []RpcRequest,               // JSON-RPC's batch of requests

    // Custom parsing when the JSON parser encounters a field of this type.
    pub fn jsonParse(alloc: Allocator, source: anytype, options: ParseOptions) !RpcMessage {
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
    err:        ReqError = .{},             // attach parsing error and validation error here.

    fn setParseErr(self: *Self, parse_err: ParseError(Scanner)) void {
        self.err = ReqError.fromParseError(parse_err);
    }

    fn validate(self: *Self) void {
        self.err = ReqError.validateRequest(self) orelse .{};
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

    pub fn arrayParams(self: Self) !std.json.Array {
        return if (self.params == .array) self.params.array else JrErrors.NotArray;
    }

    pub fn objectParams(self: Self) !std.json.ObjectMap {
        return if (self.params == .object) self.params.object else JrErrors.NotObject;
    }

    pub fn hasError(self: Self) bool {
        return self.err.code != ErrorCode.None;
    }

    pub fn isError(self: Self, code: ErrorCode) bool {
        return self.err.code == code;
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
};

const ReqError = struct {
    const Self = @This();

    code:       ErrorCode = ErrorCode.None,
    err_msg:    []const u8 = "",                // only constant string, no allocation.
    req_id:     RpcId = .{ .null = {} },        // request id related to the error.

    // The alloc passed in is from std.json.parseFromTokenSource() and it's an ArenaAllocator.
    // The memory is freed all together in Parsed(T).deinit().
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
        return null;    // return null ReqError for validation passed.
    }
    
};


