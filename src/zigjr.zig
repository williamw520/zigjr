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
const ArrayList = std.ArrayList;
const indexOfScalar = std.mem.indexOfScalar;
const StringHashMap = std.hash_map.StringHashMap;
const AutoHashMap = std.hash_map.AutoHashMap;
const allocPrint = std.fmt.allocPrint;
const parseInt = std.fmt.parseInt;
const tokenizeScalar = std.mem.tokenizeScalar;
const Scanner = std.json.Scanner;
const ParseOptions = std.json.ParseOptions;
const innerParse = std.json.innerParse;
const ParseFromValueError = std.json.ParseFromValueError;
const ParseError = std.json.ParseError;


const ErrorCode = enum(i32) {
    None = 0,
    ParseError = -32700,        // Invalid JSON was received by the server.
    InvalidRequest = -32600,    // The JSON sent is not a valid Request object.
    MethodNotFound = -32601,    // The method does not exist / is not available.
    InvalidParams = -32602,     // Invalid method parameter(s).
    InternalError = -32603,     // Internal JSON-RPC error.
    ServerError = -32000,       // -32000 to -32099 reserved for implementation defined errors.
};

const MyErrors = error{ NotificationHasNoResponse, MissingRequestBody };
pub const ServerErrors = error{
    InvalidRequest, InvalidParams, MethodNotFound,
    NoHandlerForArrayParam,
    NoHandlerForObjectParam,
    HandlerNotFunction,
    HandlerInvalidParameter,
    HandlerTooManyParams,
    MismatchedParameterCounts,
};

const RequestError = struct {
    code:   ErrorCode = .None,
    msg:    []const u8 = "",
};

const IdType = union(enum) {
    num:    i64,
    str:    []const u8,
    nul:    i64,

    // Custom parsing when the JSON parser encounters a field of the IdType type.
    pub fn jsonParse(allocator: Allocator, source: *Scanner, options: ParseOptions) !IdType {
        // std.debug.print("jsonParse: {any}\n", .{source.peekNextTokenType()});
        return switch (try source.peekNextTokenType()) {
            .number => .{ .num = try innerParse(i64, allocator, source, options) },
            .string => .{ .str = try innerParse([]const u8, allocator, source, options) },
            else => error.InvalidCharacter,
        };
    }
};

const RequestBody = struct {
    jsonrpc:        [3]u8,
    method:         []u8,
    id:             IdType = IdType { .nul = 0 },   // default if JSON doesn't have it.
    params:         std.json.Value,
};

/// Handle an incoming JSON-RPC 2.0 request message.
pub const Request = struct {
    const Self = @This();

    err_code:       ErrorCode = .None,
    err_msg:        []const u8 = "",
    body:           ?RequestBody = null,
    parsed:         ?std.json.Parsed(RequestBody) = null,

    pub fn init(allocator: Allocator, message: []const u8) !Self {
        // std.debug.print("msg: {s}\n", .{msg});
        const parsed = std.json.parseFromSlice(RequestBody, allocator, message, .{}) catch |err|
            switch (err) {
                ParseError(Scanner).MissingField,
                ParseError(Scanner).UnknownField,
                ParseError(Scanner).DuplicateField => {
                    return .{ .err_code = ErrorCode.InvalidRequest, .err_msg = @errorName(err) };
                },
                error.OutOfMemory,
                error.BufferUnderrun => {
                    return .{ .err_code = ErrorCode.InternalError, .err_msg = @errorName(err) };
                },
                else => {
                    return .{ .err_code = ErrorCode.ParseError, .err_msg = @errorName(err) };
                },
        };
        return .{ .body = parsed.value, .parsed = parsed };
    }

    pub fn deinit(self: *const Self) void {
        if (self.parsed) |parsed| parsed.deinit();
    }

    pub fn getId(self: *const Self) IdType {
        return if (self.body) |body| body.id else IdType { .nul = 0 };
    }

    pub fn hasError(self: Self) bool {
        return self.err_code != .None;
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
        // _=self;
        self.handlers.deinit();
    }

    pub fn register(self: *Self, method: []const u8, handler_fn: anytype) !void {
        const fn_ptr = try toHandler(handler_fn);
        try self.handlers.put(method, fn_ptr);
    }

    /// Run a handler on the request and generate a Response JSON string.
    /// Call freeResponse() to free the string.
    pub fn run(self: *Self, req: Request) ![]const u8 {
        if (req.hasError()) {
            // Have a parsing error on the Request message; return an Error message.
            const code  = @intFromEnum(req.err_code);
            const msg   = req.err_msg;
            return self.responseError(req.getId(), code, msg);
        }
        if (self.dispatch(req)) |result_json| {
            defer self.alloc.free(result_json);
            return self.response(req, result_json);
        } else |err| {
            // Return any dispatching error as an Error message.
            const code  = errorToCode(err);
            const msg   = @errorName(err);
            return self.responseError(req.getId(), code, msg);
        }
    }

    /// Free the Response JSON string returned by run().
    pub fn freeResponse(self: *Self, response_json: []const u8) void {
        self.alloc.free(response_json);
    }

    fn dispatch(self: *Self, req: Request) anyerror![]const u8 {
        if (req.body) |body| {
            return switch (body.params) {
                .array  => |array|  self.dispatchOnArray(body.method, array),
                .object => |obj|    self.dispatchOnObject(body.method, obj),
                else => ServerErrors.InvalidParams,
            };
        }
        return ServerErrors.InvalidRequest;
    }

    fn dispatchOnArray(self: *Self, method: []const u8, arr: Array) anyerror![]const u8 {
        const handler = self.handlers.get(method);
        if (handler == null) return ServerErrors.MethodNotFound;
        if (paramLen(handler.?) != arr.items.len) return ServerErrors.MismatchedParameterCounts;

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
            else    => ServerErrors.NoHandlerForArrayParam,
        };
    }

    fn dispatchOnObject(self: *Self, method: []const u8, obj: ObjectMap) anyerror![]const u8 {
        const handler = self.handlers.get(method);
        if (handler == null) return ServerErrors.MethodNotFound;
        return switch (handler.?) {
            .fnObj  => |f| f(self.alloc, obj),
            else    => ServerErrors.NoHandlerForObjectParam,
        };
    }

    /// Build a Response message, or an Error message if there was a parse error.
    /// Caller needs to call self.alloc.free() on the returned message free the memory.
    fn response(self: Self, req: Request, result_json: []const u8) ![]const u8 {
        if (req.hasError()) {
            const code  = @intFromEnum(req.err_code);
            const msg   = req.err_msg;
            return self.responseError(req.getId(), code, msg);
        }
        if (req.body) |body| {
            return switch (body.id) {
                .num => allocPrint(self.alloc, \\{{ "jsonrpc": "2.0", "result": {s}, "id": {} }}
                                       , .{result_json, body.id.num}),
                .str => allocPrint(self.alloc, \\{{ "jsonrpc": "2.0", "result": {s}, "id": "{s}" }}
                                       , .{result_json, body.id.str}),
                .nul => MyErrors.NotificationHasNoResponse,
            };
        }
        const id    = IdType { .nul = 0 };
        const code  = @intFromEnum(ErrorCode.InvalidRequest);
        const msg   = "Missing request body.";
        return self.responseError(id, code, msg);
    }

    /// Build an Error message.
    /// Caller needs to call self.alloc.free() on the returned message free the memory.
    fn responseError(self: Self, id: IdType, code: i64, msg: []const u8) ![]const u8 {
        return switch (id) {
            .num => allocPrint(self.alloc,
                               \\{{ "jsonrpc": "2.0",  "id": {},
                               \\   "error": {{ code: {}, "message": {s} }}
                               \\}}
                               , .{id.num, code, msg}),
            .str => allocPrint(self.alloc,
                               \\{{ "jsonrpc": "2.0",  "id": "{s}",
                               \\   "error": {{ code: {}, "message": {s} }}
                               \\}}
                               , .{id.str, code, msg}),
            .nul => allocPrint(self.alloc,
                               \\{{ "jsonrpc": "2.0",  "id": null,
                               \\   "error": {{ code: {}, "message": {s} }}
                               \\}}
                               , .{code, msg}),
        };
    }

    fn errorToCode(err: anyerror) i32 {
        return switch (err) {
            ServerErrors.InvalidParams => @intFromEnum(ErrorCode.InvalidParams),
            ServerErrors.InvalidRequest => @intFromEnum(ErrorCode.InvalidRequest),
            ServerErrors.MethodNotFound => @intFromEnum(ErrorCode.MethodNotFound),
            else => @intFromEnum(ErrorCode.ServerError),
        };
    }

};

/// The returned JSON string must be allocated with the passed in allocator.
/// The caller will free it with the allocator after using it in the Response message.
/// Call std.json.stringifyAlloc() to build the returned JSON will take care of it.
const Value = std.json.Value;
const Array = std.json.Array;
const ObjectMap = std.json.ObjectMap;
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
const HandlerN = *const fn(Allocator, Array) anyerror![]const u8;
const HandlerObj = *const fn(Allocator, ObjectMap) anyerror![]const u8;

const Handler = union(enum) {
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
    fnArr: HandlerN,
    fnObj: HandlerObj,
};

fn toHandler(handler_fn: anytype) !Handler {
    const fn_type_info: Type = @typeInfo(@TypeOf(handler_fn));
    const nparams = switch (fn_type_info) {
        .@"fn" =>|info_fn| info_fn.params.len - 1,  // one less for the Allocator param
        else => return ServerErrors.HandlerNotFunction,
    };

    switch (nparams) {
        0 => return Handler { .fn0 = handler_fn },
        1 => {
            // Single-param handler can be a Value, Array, or Object handler.
            const param1 = fn_type_info.@"fn".params[1];
            if (param1.type)|typ| {
                switch (typ) {
                    Value =>    return Handler { .fn1 = handler_fn },
                    Array =>    return Handler { .fnArr = handler_fn },
                    ObjectMap=> return Handler { .fnObj = handler_fn },
                    else =>     return ServerErrors.HandlerInvalidParameter,
                }
            }
            return ServerErrors.HandlerInvalidParameter;
        },
        2 => return Handler { .fn2 = handler_fn },
        3 => return Handler { .fn3 = handler_fn },
        4 => return Handler { .fn4 = handler_fn },
        5 => return Handler { .fn5 = handler_fn },
        6 => return Handler { .fn6 = handler_fn },
        7 => return Handler { .fn7 = handler_fn },
        8 => return Handler { .fn8 = handler_fn },
        9 => return Handler { .fn9 = handler_fn },
        else => return ServerErrors.HandlerTooManyParams,
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


fn foo(p1: u32) !usize { return p1 + 2; }

fn foo2(p1: ?std.json.Value, p2: ?std.json.Value) struct { id: usize, name: []const u8 } {
    _=p1;
    _=p2;
    return .{ .id = 123, .name = "foo2" };
}

test {
    std.debug.print("test...\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    std.debug.print("foo(3): {}\n", .{try foo(3)});

    // const type_foo = @TypeOf(foo);
    const info_foo = @typeInfo(@TypeOf(foo));
    const info_fn = info_foo.@"fn";
    const return_type = info_fn.return_type;
    const params = info_foo.@"fn".params;
    const param_count = params.len;
    
    // std.debug.print("TypeOf: {any}\n", .{type_foo});
    // std.debug.print("typeInfo: {any}\n", .{tinfo_foo});
    // std.debug.print("typeInfo: {any}\n", .{tinfo_fn});
    std.debug.print("return_type: {any}\n", .{return_type});
    std.debug.print("param_count: {any}\n", .{param_count});
    std.debug.print("params[0]: {any}\n", .{params[0]});

    comptime for (params)|p| {
        const t = p.type;
        _=t;
        // std.debug.print("typeInfo param: {} - {any}\n", .{i, params[i].type});
    };

    const msg1 =\\{"jsonrpc": "2.0", "method": "subtract", "params": [42, 23], "id": 1}
                ;
    const req = try Request.init(allocator, msg1);
    std.debug.print("msg: {s}\n", .{msg1});
    std.debug.print("req: {any}\n", .{req.err_code});
    std.debug.print("req: {s}\n", .{req.err_msg});
    std.debug.print("req: {any}\n", .{req.body});
    std.debug.print("req: {any}\n", .{req.parsed});

    // const res1 = try req.response(allocator, [_]usize{ 1, 2, 3});
    // std.debug.print("res1: {s}\n", .{res1});
    
    const f2 =  foo2(null, null);
    std.debug.print("foo2(): {any}\n", .{f2});

    const type_foo2 = @TypeOf(foo2);
    std.debug.print("type_foo2: {any}\n", .{type_foo2});

}

fn fun0(alloc: Allocator) anyerror![]const u8 {
    return std.json.stringifyAlloc(alloc, "Hello", .{});
}

fn fun1(alloc: Allocator, p1: Value) anyerror![]const u8 {
    const n1 = p1.string;
    const str = allocPrint(alloc, "Hello p1={s}", .{n1}) catch |e| @errorName(e);
    defer alloc.free(str);
    return std.json.stringifyAlloc(alloc, str, .{});
}

fn fun2(alloc: Allocator, p1: Value, p2: Value) anyerror![]const u8 {
    const n1 = p1.integer;
    const n2 = p2.integer;
    return std.json.stringifyAlloc(alloc, n1 - n2, .{});
}


test {
    std.debug.print("\n\n\n", .{});
    std.debug.print("test handler calls...\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var registry = Registry.init(allocator);
    defer registry.deinit();

    const ptr = toHandler(fun0);
    std.debug.print("ptr: {any}\n", .{ptr});

    const ptr2 = toHandler(fun0);
    std.debug.print("ptr2: {any}\n", .{ptr2});

    const ptr3 = toHandler(123);
    std.debug.print("ptr3: {any}\n", .{ptr3});

    try registry.register("fun0", fun0);
    try registry.register("fun1", fun1);
    try registry.register("subtract", fun2);

    const msg0 =\\{"jsonrpc": "2.0", "method": "fun0", "params": [], "id": 1}
                ;
    const req0 = try Request.init(allocator, msg0);
    std.debug.print("req0.body: {any}\n", .{req0.body});
    const res0 = try registry.run(req0);
    std.debug.print("res0 {s}\n", .{res0});
    
    const msg1 =\\{"jsonrpc": "2.0", "method": "fun1", "params": ["FUN1"], "id": 1}
                ;
    const req1 = try Request.init(allocator, msg1);
    std.debug.print("req1.body: {any}\n", .{req1.body});
    const res1 = try registry.run(req1);
    std.debug.print("res1 {s}\n", .{res1});
    
    const msg2 =\\{"jsonrpc": "2.0", "method": "subtract", "params": [42, 22], "id": 1}
                ;
    const req2 = try Request.init(allocator, msg2);
    std.debug.print("req2.body: {any}\n", .{req2.body});
    if (req2.body) |body| {
        std.debug.print("req2.body.params: {any}\n", .{body.params});
        const p1: Value = body.params.array.items[0];
        std.debug.print("req2.body.params[0]: {any}\n", .{p1});
    }
    const res2 = try registry.run(req2);
    std.debug.print("res2 {s}\n", .{res2});
    
}


