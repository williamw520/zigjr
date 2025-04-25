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



pub fn parseJson(alloc: Allocator, json_str: []const u8) RpcResult {
    const parsed = std.json.parseFromSlice(RpcMessage, alloc, json_str, .{}) catch |parse_err| {
        // Create an empty request with the error set so callers can have uniform request handling.
        const req = RpcRequest.initErr(ReqError.initParseError(parse_err));
        return .{
            .alloc = alloc,
            .parsed = null,
            .rpc_msg = RpcMessage { .request = req },
        };
    };
    return .{
        .alloc = alloc,
        .parsed = parsed,
        .rpc_msg = parsed.value,
    };
}

pub fn parseReader(alloc: Allocator, json_reader: anytype) RpcResult {
    var rp = ReaderParser(@TypeOf(json_reader)).init(alloc, json_reader);
    defer rp.deinit();
    // NOTE: Stream parsing of JSON's via Reader is impossible.
    // The assert() in std.json.parseFromTokenSourceLeaky() expects the end of input
    // after parsing just one JSON.
    //      assert(.end_of_document == try scanner_or_reader.next())
    // NOTE: Streaming support needs to be done at a higher level, at the framing protocol level.
    // E.g. Add '\n' between each JSON, or use "content-length: N\r\n\r\n" header.
    const parsed = rp.next() catch |parse_err| {
        const req = RpcRequest.initErr(ReqError.initParseError(parse_err));
        return .{
            .alloc = alloc,
            .parsed = null,
            .rpc_msg = RpcMessage { .request = req },
        };
    };
    return .{
        .alloc = alloc,
        .parsed = parsed,
        .rpc_msg = parsed.value,
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
    rpc_msg:    RpcMessage,

    pub fn deinit(self: *Self) void {
        if (self.parsed) |parsed| parsed.deinit();
    }

    pub fn isRequest(self: *Self) bool {
        return self.rpc_msg == .request;
    }

    pub fn isBatch(self: *Self) bool {
        return self.rpc_msg == .batch;
    }

    /// Shortcut to access the inner tagged union invariant request.
    /// Can also access via switch(rpc_msg) .request => 
    pub fn request(self: *Self) !RpcRequest {
        return if (self.isRequest()) self.rpc_msg.request else JrErrors.NotSingleRpcRequest;
    }

    /// Shortcut to access the inner tagged union invariant batch.
    pub fn batch(self: *Self) ![]const RpcRequest {
        return if (self.isBatch()) self.rpc_msg.batch else JrErrors.NotBatchRpcRequest;
    }
};

pub const RpcMessage = union(enum) {
    request:    RpcRequest,                 // JSON-RPC's single request
    batch:      []RpcRequest,               // JSON-RPC's batch of requests

    // Custom parsing when the JSON parser encounters a field of this type.
    pub fn jsonParse(alloc: Allocator, source: anytype, options: ParseOptions) !RpcMessage {
        return switch (try source.peekNextTokenType()) {
            .object_begin => .{
                .request = try innerParse(RpcRequest, alloc, source, options)
            },
            .array_begin => .{
                .batch   = try innerParse([]RpcRequest, alloc, source, options)
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
    id:         RpcId = .{ .null = {} },    // default for optional field.
    err:        ReqError = .{},             // parse error and validation error.

    fn initErr(err: ReqError) Self {
        return .{ .err = err };
    }

    pub fn jsonParse(alloc: Allocator, source: anytype, options: ParseOptions) !Self {
        // Parse errors are bubbled up to the caller of parser to be handled.
        const body = try innerParse(RpcRequestBody, alloc, source, options);
        // At this point, the body has passed parsing.  Copy and validate its content.
        return .{
            .jsonrpc = body.jsonrpc,
            .method  = body.method,
            .params  = if (body.params == .value) body.params.value else Value { .null = {} },
            .id      = body.id,
            .err     = ReqError.validateBody(body) orelse .{},
        };
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

    pub fn hasId(self: Self) bool {
        return self.id != .null;
    }

    pub fn hasError(self: Self) bool {
        return self.err.code != ErrorCode.None;
    }

    pub fn isError(self: Self, code: ErrorCode) bool {
        return self.err.code == code;
    }
    
};

const RpcRequestBody = struct {
    jsonrpc:    [3]u8 = .{ '0', '.', '0' },     // default to fail validation.
    method:     []u8 = "",
    params:     RpcParamsBody = .{ .nul = {} }, // default for optional field.
    id:         RpcId = .{ .null = {} },        // default for optional field.
};

const RpcParamsBody = union(enum) {
    nul:        void,
    value:      Value,
    invalid:    void,

    pub fn jsonParse(alloc: Allocator, source: anytype, options: ParseOptions) !RpcParamsBody {
        return switch (try source.peekNextTokenType()) {
            .object_begin   => .{ .value    = try innerParse(Value, alloc, source, options) },
            .array_begin    => .{ .value    = try innerParse(Value, alloc, source, options) },
            else            => .{ .invalid  = {} },
        };
    }
};

pub const RpcId = union(enum) {
    null:       void,
    num:        i64,
    str:        []const u8,

    pub fn jsonParse(alloc: Allocator, source: anytype, options: ParseOptions) !RpcId {
        return switch (try source.peekNextTokenType()) {
            .number => .{ .num = try innerParse(i64, alloc, source, options) },
            .string => .{ .str = try innerParse([]const u8, alloc, source, options) },
            else => error.UnexpectedToken,
        };
    }
};

const ReqError = struct {
    const Self = @This();

    code:       ErrorCode = ErrorCode.None,
    err_msg:    []const u8 = "",                // only constant string, no allocation.
    req_id:     RpcId = .{ .null = {} },        // request id related to the error.

    // The alloc passed in is from std.json.parseFromTokenSource() and it's an ArenaAllocator.
    // The memory is freed all together in Parsed(T).deinit().
    fn initParseError(parse_err: ParseError(Scanner)) Self {
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

    // The alloc passed in is from std.json.parseFromTokenSource() and it's an ArenaAllocator.
    // The memory is freed all together in Parsed(T).deinit().
    fn validateBody(body: RpcRequestBody) ?Self {
        if (!std.mem.eql(u8, &body.jsonrpc, "2.0")) {
            return .{
                .code = ErrorCode.InvalidRequest,
                .err_msg = "Invalid JSON-RPC version. Must be 2.0.",
                .req_id = body.id,
            };
        }
        if (body.params == .invalid) {
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


