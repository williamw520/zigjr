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
const StringHashMap = std.hash_map.StringHashMap;
const AutoHashMap = std.hash_map.AutoHashMap;
const allocPrint = std.fmt.allocPrint;
const Parsed = std.json.Parsed;
const Scanner = std.json.Scanner;
const ParseOptions = std.json.ParseOptions;
const innerParse = std.json.innerParse;
const ParseError = std.json.ParseError;
const Value = std.json.Value;
const Array = std.json.Array;
const ObjectMap = std.json.ObjectMap;


// JSON-RPC 2.0 error codes.
pub const ErrorCode = enum(i32) {
    None = 0,
    ParseError = -32700,        // Invalid JSON was received by the server.
    InvalidRequest = -32600,    // The JSON sent is not a valid Request object.
    MethodNotFound = -32601,    // The method does not exist / is not available.
    InvalidParams = -32602,     // Invalid method parameter(s).
    InternalError = -32603,     // Internal JSON-RPC error.
    ServerError = -32000,       // -32000 to -32099 reserved for implementation defined errors.
};

pub const JrErrors = error {
    NotSingleRpcRequest,
    NotBatchRpcRequest,
    NotArray,
    NotObject,
    NotificationHasNoResponse,
};

// Handler registration errors or dispatching errors.
pub const RegistrationErrors = error {
    InvalidMethodName,
    HandlerNotFunction,
    MissingAllocator,
    HandlerInvalidParameter,
    HandlerInvalidParameterType,
    HandlerTooManyParams,
};
pub const DispatchErrors = error {
    NoHandlerForArrayParam,
    NoHandlerForObjectParam,
    MismatchedParameterCounts,
    MethodNotFound,
    InvalidParams,
};


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

pub fn parseJson(alloc: Allocator, json_str: []const u8) RpcResult {
    const parsed = std.json.parseFromSlice(RpcMessage, alloc, json_str, .{}) catch |parse_err| {
        // Create an empty request with the error set so callers can have uniform request handling.
        const req = RpcRequest.initErr(RpcError.initParseError(parse_err));
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
        const req = RpcRequest.initErr(RpcError.initParseError(parse_err));
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
    err:        RpcError = .{},             // parse error and validation error.

    fn initErr(err: RpcError) Self {
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
            .err     = RpcError.validateBody(body) orelse .{},
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

const RpcError = struct {
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
        return null;    // return null RpcError for validation passed.
    }
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


pub const Registry = struct {
    const Self = @This();

    alloc:      Allocator,
    handlers:   StringHashMap(Handler),

    pub fn init(allocator: Allocator) Self {
        return .{
            .alloc = allocator,
            .handlers = StringHashMap(Handler).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.handlers.deinit();
    }

    pub fn register(self: *Self, method: []const u8, handler_fn: anytype) !void {
        if (std.mem.startsWith(u8, method, "rpc.")) {
            return RegistrationErrors.InvalidMethodName;    // By spec, "rpc." is reserved.
        }
        const fn_ptr = try toHandler(handler_fn);
        try self.handlers.put(method, fn_ptr);
    }

    pub fn get(self: *Self, method: []const u8) ?Handler {
        return self.handlers.get(method);
    }

    /// Run a handler on the request and generate a Response JSON string.
    /// Call freeResponse() to free the string.
    pub fn run(self: *Self, req: RpcRequest) ![]const u8 {
        if (req.hasError()) {
            // For parsing or validation error on the request, return an error response.
            return self.responseError(req.id, @intFromEnum(req.err.code), req.err.err_msg);
        }
        if (self.dispatch(req)) |result_json| {
            defer self.alloc.free(result_json);
            return self.response(req, result_json);
        } else |dispatch_err| {
            // Return any dispatching error as an error response.
            const code, const msg = errorToCodeMsg(dispatch_err);
            return self.responseError(req.id, code, msg);
        }
    }

    /// Free the Response JSON string returned by run().
    pub fn freeResponse(self: *Self, response_json: []const u8) void {
        self.alloc.free(response_json);
    }

    fn dispatch(self: *Self, req: RpcRequest) anyerror![]const u8 {
        return switch (req.params) {
            .null   =>      self.dispatchOnNone(req.method),
            .array  => |a|  self.dispatchOnArray(req.method, a),
            .object => |o|  self.dispatchOnObject(req.method, o),
            else    => DispatchErrors.InvalidParams,
        };
    }

    fn dispatchOnNone(self: *Self, method: []const u8) anyerror![]const u8 {
        const handler = self.handlers.get(method);
        if (handler == null) return DispatchErrors.MethodNotFound;
        if (paramLen(handler.?)) |nparams| {
            if (nparams > 0) return DispatchErrors.MismatchedParameterCounts;
        } else {
            return DispatchErrors.MismatchedParameterCounts;
        }
        return switch (handler.?) {
            .fn0 => |f| f(self.alloc),
            else => DispatchErrors.MismatchedParameterCounts,
        };
    }

    fn dispatchOnArray(self: *Self, method: []const u8, arr: Array) anyerror![]const u8 {
        const handler = self.handlers.get(method);
        if (handler == null) return DispatchErrors.MethodNotFound;
        if (paramLen(handler.?) != arr.items.len) return DispatchErrors.MismatchedParameterCounts;

        return switch (handler.?) {
            .fn0 => |f| f(self.alloc),
            .fn1 => |f| f(self.alloc, arr.items[0]),
            .fn2 => |f| f(self.alloc, arr.items[0], arr.items[1]),
            .fn3 => |f| f(self.alloc, arr.items[0], arr.items[1], arr.items[2]),
            .fn4 => |f| f(self.alloc, arr.items[0], arr.items[1], arr.items[2], arr.items[3]),
            .fn5 => |f| f(self.alloc, arr.items[0], arr.items[1], arr.items[2], arr.items[3], arr.items[4]),
            .fn6 => |f| f(self.alloc, arr.items[0], arr.items[1], arr.items[2], arr.items[3], arr.items[4], arr.items[5]),
            .fn7 => |f| f(self.alloc, arr.items[0], arr.items[1], arr.items[2], arr.items[3], arr.items[4], arr.items[5], arr.items[6]),
            .fn8 => |f| f(self.alloc, arr.items[0], arr.items[1], arr.items[2], arr.items[3], arr.items[4], arr.items[5], arr.items[6], arr.items[7]),
            .fn9 => |f| f(self.alloc, arr.items[0], arr.items[1], arr.items[2], arr.items[3], arr.items[4], arr.items[5], arr.items[6], arr.items[7], arr.items[8]),
            .fnArr  => |f| f(self.alloc, arr),
            else    => DispatchErrors.NoHandlerForArrayParam,
        };
    }

    fn dispatchOnObject(self: *Self, method: []const u8, obj: ObjectMap) anyerror![]const u8 {
        const handler = self.handlers.get(method);
        if (handler == null) return DispatchErrors.MethodNotFound;
        return switch (handler.?) {
            .fnObj  => |f| f(self.alloc, obj),
            else    => DispatchErrors.NoHandlerForObjectParam,
        };
    }

    /// Build a Response message, or an Error message if there was a parse error.
    /// Caller needs to call self.alloc.free() on the returned message free the memory.
    fn response(self: Self, req: RpcRequest, result_json: []const u8) ![]const u8 {
        if (req.hasError()) {
            return self.responseError(req.id, @intFromEnum(req.err.code), req.err.err_msg);
        }
        return switch (req.id) {
            .num => allocPrint(self.alloc, \\{{ "jsonrpc": "2.0", "result": {s}, "id": {} }}
                                   , .{result_json, req.id.num}),
            .str => allocPrint(self.alloc, \\{{ "jsonrpc": "2.0", "result": {s}, "id": "{s}" }}
                                   , .{result_json, req.id.str}),
            .null => JrErrors.NotificationHasNoResponse,
        };
    }

    /// Build an Error message.
    /// Caller needs to call self.alloc.free() on the returned message free the memory.
    fn responseError(self: Self, id: RpcId, code: i64, msg: []const u8) ![]const u8 {
        return switch (id) {
            .num => allocPrint(self.alloc,
                               \\{{ "jsonrpc": "2.0",  "id": {},
                               \\   "error": {{ code: {}, "message": "{s}" }}
                               \\}}
                               , .{id.num, code, msg}),
            .str => allocPrint(self.alloc,
                               \\{{ "jsonrpc": "2.0",  "id": "{s}",
                               \\   "error": {{ code: {}, "message": "{s}" }}
                               \\}}
                               , .{id.str, code, msg}),
            .null => allocPrint(self.alloc,
                               \\{{ "jsonrpc": "2.0",  "id": null,
                               \\   "error": {{ code: {}, "message": "{s}" }}
                               \\}}
                               , .{code, msg}),
        };
    }

    fn errorToCodeMsg(err: anyerror) struct {i32, []const u8} {
        return switch (err) {
            DispatchErrors.MethodNotFound => .{
                @intFromEnum(ErrorCode.MethodNotFound),
                "Method not found.",
            },
            DispatchErrors.InvalidParams => .{
                @intFromEnum(ErrorCode.InvalidParams),
                "Invalid parameters.",
            },
            DispatchErrors.NoHandlerForArrayParam => .{
                @intFromEnum(ErrorCode.InvalidParams),
                "Handler expecting array parameters but got non-array parameters.",
            },
            DispatchErrors.NoHandlerForObjectParam => .{
                @intFromEnum(ErrorCode.InvalidParams),
                "Handler expecting an object parameter but got non-object parameters.",
            },
            DispatchErrors.MismatchedParameterCounts => .{
                @intFromEnum(ErrorCode.InvalidParams),
                "The number of parameters of the request does not match the parameter count of the handler.",
            },
            else => .{
                @intFromEnum(ErrorCode.ServerError),
                @errorName(err),    // return the dispatching error as text msg.
            },
        };
    }

};

/// The returned JSON string must be allocated with the passed in allocator.
/// The caller will free it with the allocator after using it in the Response message.
/// Call std.json.stringifyAlloc() to build the returned JSON will take care of it.
const Handler0 = *const fn(Allocator) anyerror![]const u8;
const Handler1 = *const fn(Allocator, Value) anyerror![]const u8;
const Handler2 = *const fn(Allocator, Value, Value) anyerror![]const u8;
const Handler3 = *const fn(Allocator, Value, Value, Value) anyerror![]const u8;
const Handler4 = *const fn(Allocator, Value, Value, Value, Value) anyerror![]const u8;
const Handler5 = *const fn(Allocator, Value, Value, Value, Value, Value) anyerror![]const u8;
const Handler6 = *const fn(Allocator, Value, Value, Value, Value, Value, Value) anyerror![]const u8;
const Handler7 = *const fn(Allocator, Value, Value, Value, Value, Value, Value, Value) anyerror![]const u8;
const Handler8 = *const fn(Allocator, Value, Value, Value, Value, Value, Value, Value, Value) anyerror![]const u8;
const Handler9 = *const fn(Allocator, Value, Value, Value, Value, Value, Value, Value, Value, Value) anyerror![]const u8;
const HandlerArr = *const fn(Allocator, Array) anyerror![]const u8;
const HandlerObj = *const fn(Allocator, ObjectMap) anyerror![]const u8;

// Use tagged union to wrap different types of handler.
pub const Handler = union(enum) {
    fn0: Handler0,
    fn1: Handler1,
    fn2: Handler2,
    fn3: Handler3,
    fn4: Handler4,
    fn5: Handler5,
    fn6: Handler6,
    fn7: Handler7,
    fn8: Handler8,
    fn9: Handler9,
    fnArr: HandlerArr,
    fnObj: HandlerObj,
};

fn toHandler(handler_fn: anytype) !Handler {
    const fn_type_info: Type = @typeInfo(@TypeOf(handler_fn));
    const params = switch (fn_type_info) {
        .@"fn" =>|info_fn| info_fn.params,
        else => return RegistrationErrors.HandlerNotFunction,
    };
    if (params.len == 0) {
        return RegistrationErrors.MissingAllocator;
    }
    const nparams = params.len - 1;  // one less for the Allocator param

    switch (nparams) {
        0 => return Handler { .fn0 = handler_fn },
        1 => {
            // Single-param handler can be a Value, Array, or Object handler.
            if (params[1].type)|typ| {
                switch (typ) {
                    Value =>    return Handler { .fn1 = handler_fn },
                    Array =>    return Handler { .fnArr = handler_fn },
                    ObjectMap=> return Handler { .fnObj = handler_fn },
                    else =>     return RegistrationErrors.HandlerInvalidParameterType,
                }
            }
            return RegistrationErrors.HandlerInvalidParameter;
        },
        2 => return Handler { .fn2 = handler_fn },
        3 => return Handler { .fn3 = handler_fn },
        4 => return Handler { .fn4 = handler_fn },
        5 => return Handler { .fn5 = handler_fn },
        6 => return Handler { .fn6 = handler_fn },
        7 => return Handler { .fn7 = handler_fn },
        8 => return Handler { .fn8 = handler_fn },
        9 => return Handler { .fn9 = handler_fn },
        else => return RegistrationErrors.HandlerTooManyParams,
    }
}

fn paramLen(handler: Handler) ?usize {
    return switch (handler) {
        .fn0 => 0,
        .fn1 => 1,
        .fn2 => 2,
        .fn3 => 3,
        .fn4 => 4,
        .fn5 => 5,
        .fn6 => 6,
        .fn7 => 7,
        .fn8 => 8,
        .fn9 => 9,
        else => null,
    };
}


test {
    _ = @import("tests.zig");
}

