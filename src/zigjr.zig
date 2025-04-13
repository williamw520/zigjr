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

const MyErrors = error{ NotificationHasNoResponse, InvalidFunctionParameter };
const ServerErrors = error{ InvalidRequest, InvalidParams, MethodNotFound };

const RequestError = struct {
    code:   ErrorCode = .None,
    msg:    []const u8 = "",
};

const IdType = union(enum) {
    num:    i64,
    str:    []const u8,

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
    id:             ?IdType = null,
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
        // TODO: validate method and params in parsed.
        return .{ .body = parsed.value, .parsed = parsed };
    }

    pub fn deinit(self: *const Self) void {
        if (self.parsed) |parsed| parsed.deinit();
    }

    pub fn has_error(self: Self) bool {
        return self.err_code != .None;
    }

    /// Build a Response message, or an Error message if there was a parse error.
    /// Caller needs to call allocator.free() on the returned message free the memory.
    pub fn response(self: Self, alloc: Allocator, result: anytype) ![]const u8 {
        if (self.body) |body| {
            const id = body.id orelse return MyErrors.NotificationHasNoResponse;
            const result_json = try std.json.stringifyAlloc(alloc, result, .{});
            defer alloc.free(result_json);
            return switch (id) {
                .num => allocPrint(alloc, \\{{ "jsonrpc": "2.0", "result": {s}, "id": {} }}
                                       , .{result_json, id.num}),
                .str => allocPrint(alloc, \\{{ "jsonrpc": "2.0", "result": {s}, "id": "{s}" }}
                                       , .{result_json, id.str}),
            };
        }
        return self.response_error(alloc);
    }

    /// Build an Error message.
    /// Caller needs to call allocator.free() on the returned message free the memory.
    pub fn response_error(self: Self, alloc: Allocator) ![]const u8 {
        const code  = @intFromEnum(self.err_code);
        const msg   = self.err_msg;
        if (self.body) |body| {
            if (body.id) |id| {
                return switch (id) {
                    .num => allocPrint(alloc,
                                        \\{{ "jsonrpc": "2.0", "id": {},
                                        \\   "error": {{ code: {}, "message": {s} }}
                                        \\}}
                                        , .{id.num, code, msg}),
                    .str => allocPrint(alloc,
                                        \\{{ "jsonrpc": "2.0", "id": "{s}",
                                        \\   "error": {{ code: {}, "message": {s} }}
                                        \\}}
                                        , .{id.str, code, msg}),
                };
            }
        }
        return allocPrint(alloc,
                              \\{{ "jsonrpc": "2.0", "id": null,
                              \\   "error": {{ code: {}, "message": {s} }}
                              \\}}
                              , .{code, msg});
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
        const fn_ptr = toHandler(handler_fn);
        try self.handlers.put(method, fn_ptr);
    }

    pub fn run(self: *Self, req: Request) []const u8 {
        _=self;
        _=req;
        // TODO: return a Response JSON.
        // Move response building code from Request to here.
        // Handle existing error in req.
        // Handle any error during dispatching.
    }

    fn dispatch(self: *Self, req: Request) ServerErrors![]const u8 {
        if (req.body) |body| {
            return switch (body.params) {
                .array => |array| self.dispatchOnArray(req, body, array),
                .object => |obj| self.dispatchOnObject(req, obj),
                else => ServerErrors.InvalidParams,
            };
        }
        return ServerErrors.InvalidRequest;
    }

    fn dispatchOnArray(self: *Self, req: Request, body: RequestBody, arr: std.json.Array) ServerErrors![]const u8 {
        _=req;
        if (self.handlers.get(body.method)) |handler| {
            // TODO: check handler's nparams vs arr.len
            return switch (handler) {
                .fn0 => |f| try f(self.alloc),
                .fn1 => |f| try f(self.alloc, arr.items[0]),
                .fn2 => |f| try f(self.alloc, arr.items[0], arr.items[1]),
                .fn3 => |f| try f(self.alloc, arr.items[0], arr.items[1], arr.items[2]),
                .fn4 => |f| try f(self.alloc, arr.items[0], arr.items[1], arr.items[2], arr.items[3]),
                .fn5 => |f| try f(self.alloc, arr.items[0], arr.items[1], arr.items[2], arr.items[3], arr.items[4]),
                .fn6 => |f| try f(self.alloc, arr.items[0], arr.items[1], arr.items[2], arr.items[3], arr.items[4], arr.items[5]),
                .fn7 => |f| try f(self.alloc, arr.items[0], arr.items[1], arr.items[2], arr.items[3], arr.items[4], arr.items[5], arr.items[6]),
                .fn8 => |f| try f(self.alloc, arr.items[0], arr.items[1], arr.items[2], arr.items[3], arr.items[4], arr.items[5], arr.items[6], arr.items[7]),
                .fn9 => |f| try f(self.alloc, arr.items[0], arr.items[1], arr.items[2], arr.items[3], arr.items[4], arr.items[5], arr.items[6], arr.items[7], arr.items[8]),
                .fnN => |f| try f(self.alloc, arr),
            };
        }
        return ServerErrors.MethodNotFound;
    }

    fn dispatchOnObject(self: *Self, req: Request, obj: std.json.ObjectMap) ServerErrors![]const u8 {
        _=self;
        _=req;
        _=obj;
        // TODO: dispatch to .fn1
        return "";
    }

};

const Value = std.json.Value;
const Handler0 = *const fn(Allocator) ServerErrors![]const u8;
const Handler1 = *const fn(Allocator, Value) ServerErrors![]const u8;
const Handler2 = *const fn(Allocator, Value, Value) ServerErrors![]const u8;
const Handler3 = *const fn(Allocator, Value, Value, Value) ServerErrors![]const u8;
const Handler4 = *const fn(Allocator, Value, Value, Value, Value) ServerErrors![]const u8;
const Handler5 = *const fn(Allocator, Value, Value, Value, Value, Value) ServerErrors![]const u8;
const Handler6 = *const fn(Allocator, Value, Value, Value, Value, Value, Value) ServerErrors![]const u8;
const Handler7 = *const fn(Allocator, Value, Value, Value, Value, Value, Value, Value) ServerErrors![]const u8;
const Handler8 = *const fn(Allocator, Value, Value, Value, Value, Value, Value, Value, Value) ServerErrors![]const u8;
const Handler9 = *const fn(Allocator, Value, Value, Value, Value, Value, Value, Value, Value, Value) ServerErrors![]const u8;
const HandlerN = *const fn(Allocator, std.json.Array) ServerErrors![]const u8;

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
    fnN: HandlerN,
};

fn toHandler(handler_fn: anytype) Handler {
    const fn_type_info = @typeInfo(@TypeOf(handler_fn));
    const nparams = switch (fn_type_info) {
        .@"fn" =>|info_fn| info_fn.params.len - 1,  // one less for the Allocator param
        else => 99,
    };

    return switch (nparams) {
        0 => Handler { .fn0 = handler_fn },
        1 => Handler { .fn1 = handler_fn },
        2 => Handler { .fn2 = handler_fn },
        3 => Handler { .fn3 = handler_fn },
        4 => Handler { .fn4 = handler_fn },
        5 => Handler { .fn5 = handler_fn },
        6 => Handler { .fn6 = handler_fn },
        7 => Handler { .fn7 = handler_fn },
        8 => Handler { .fn8 = handler_fn },
        9 => Handler { .fn9 = handler_fn },
        else => Handler { .fnN = handler_fn },
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
    
    const res2 = try req.response(allocator, [_]usize{ 1, 2, 3});
    std.debug.print("res2: {s}\n", .{res2});

    const f2 =  foo2(null, null);
    std.debug.print("foo2(): {any}\n", .{f2});

    const type_foo2 = @TypeOf(foo2);
    std.debug.print("type_foo2: {any}\n", .{type_foo2});

    

    // const fp: fn(?std.json.Value, ?std.json.Value) type = foo2;
    // std.debug.print("fp:        {any}\n", .{fp});
    
}

fn fun0(_: Allocator) ServerErrors![]const u8 {
    return "Hello";
}

fn fun1(alloc: Allocator, p1: Value) ServerErrors![]const u8 {
    const n1 = p1.integer;
    return allocPrint(alloc, "Hello p1={}", .{n1}) catch |e| @errorName(e);
}

fn fun2(alloc: Allocator, p1: Value, p2: Value) ServerErrors![]const u8 {
    const n1 = p1.integer;
    const n2 = p2.integer;
    return allocPrint(alloc, "Subtract p1={}, p2={}", .{n1, n2}) catch |e| @errorName(e);
}


test {
    std.debug.print("\n\n\n", .{});
    std.debug.print("test handler calls...\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var registry = Registry.init(allocator);
    defer registry.deinit();

    const ptr = toHandler(fun0);
    std.debug.print("ptr: {}\n", .{ptr});

    const ptr2 = toHandler(fun0);
    std.debug.print("ptr2: {}\n", .{ptr2});

    try registry.register("fun0", fun0);
    try registry.register("fun1", fun1);
    try registry.register("subtract", fun2);

    const msg1 =\\{"jsonrpc": "2.0", "method": "subtract", "params": [42, 23], "id": 1}
                ;
    const req = try Request.init(allocator, msg1);
    std.debug.print("req.body: {any}\n", .{req.body});
    var p1: Value = undefined;
    if (req.body) |body| {
        std.debug.print("req.body.params: {any}\n", .{body.params});
        p1 = body.params.array.items[0];
        std.debug.print("req.body.params[0]: {any}\n", .{p1});
    }

    if (registry.handlers.get("fun1")) |hptr| {
        switch (hptr) {
            .fn0 => |f| {
                const result = try f(allocator);
                std.debug.print("call fn0: {s}\n", .{result});
            },
            .fn1 => |f| {
                const result = try f(allocator, p1);
                std.debug.print("call fn1: {s}\n", .{result});
            },
            // fn2: Handler2,
            // fn3: Handler3,
            // fnN: HandlerN,
            else => |_| {
                std.debug.print("Not done yet\n", .{});
            },
        }            
    }

    const res3 = try registry.dispatch(req);
    std.debug.print("res3 {s}\n", .{res3});
    
}


const FnType = *const fn(i32) i32;

fn add1(x: i32) i32 { return x + 1; }
fn add2(x: i32) i32 { return x + 2; }

test {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var map = std.StringHashMap(FnType).init(allocator);
    defer map.deinit();    

    try map.put("inc1", add1);
    try map.put("inc2", add2);

    if (map.get("inc1")) |f| {
        const result = f(5);
        std.debug.print("inc1(5): {}\n", .{result});
    }    
    if (map.get("inc2")) |f| {
        const result = f(5);
        std.debug.print("inc2(5): {}\n", .{result});
    }    

}

