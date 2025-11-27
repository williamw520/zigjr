const std = @import("std");
const testing = std.testing;
const allocPrint = std.fmt.allocPrint;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const nanoTimestamp = std.time.nanoTimestamp;
const Value = std.json.Value;

const zigjr = @import("../zigjr.zig");
const RpcRequestMessage = zigjr.RpcRequestMessage;
const RpcRequest = zigjr.RpcRequest;
const ErrorCode = zigjr.ErrorCode;
const JrErrors = zigjr.JrErrors;
const RequestDispatcher = zigjr.RequestDispatcher;
const DispatchResult = zigjr.DispatchResult;
const DispatchErrors = zigjr.DispatchErrors;


// Test handler registration.

var fn0_called = false;
var fn0_with_err_called = false;
var fn0_alloc_called = false;

fn fn0() void {
    // std.debug.print("fn0() called\n", .{});
    fn0_called = true;
}

fn fn0_with_err() !void {
    // std.debug.print("fn0_with_err() called\n", .{});
    fn0_with_err_called = true;
}

fn fn0_return_value() []const u8 {
    // std.debug.print("fn0_return_value() called\n", .{});
    return "Hello";
}

fn fn0_return_value_with_err() ![]const u8 {
    // std.debug.print("fn0_return_value_with_err() called\n", .{});
    return "Hello";
}

fn fn0_alloc(alloc: Allocator) !void {
    // std.debug.print("fn0_alloc() called\n", .{});
    // The arena allocator will take care of freeing it.
    _ = try alloc.dupe(u8, "Hello. Allocate some memory without freeing.");
    fn0_alloc_called = true;
}


var fn1_called = false;
var fn1_with_err_called = false;

fn fn1(a: i64) void {
    _=a;
    // std.debug.print("fn1() called, a:{}\n", .{a});
    fn1_called = true;
}

fn fn1_with_err(a: i64) !void {
    _=a;
    // std.debug.print("fn1_with_err() called, a:{}\n", .{a});
    fn1_with_err_called = true;
}

fn fn1_return_value(a: i64) []const u8 {
    _=a;
    // std.debug.print("fn1_return_value() called, a:{}\n", .{a});
    return "Hello";
}

fn fn1_return_value_with_err(a: i64) ![]const u8 {
    _=a;
    // std.debug.print("fn1_return_value_with_err() called, a:{}\n", .{a});
    return "Hello";
}

fn fn1_alloc_with_err(alloc: Allocator, a: i64) !void {
    _=a;
    // std.debug.print("fn1_alloc_with_err() called, a:{}\n", .{a});
    // The arena allocator will take care of freeing it.
    _ = try alloc.dupe(u8, "Hello. Allocate some memory without freeing.");
}


var fn2_called = false;
var fn2_with_err_called = false;
var fn2_alloc_with_err_called = false;

fn fn2(a: i64, b: bool) void {
    _=a;
    _=b;
    // std.debug.print("fn2() called, a:{}, b:{}\n", .{a, b});
    fn2_called = true;
}

fn fn2_with_err(a: i64, b: bool) !void {
    _=a;
    // std.debug.print("fn2_with_err() called, a:{}, b:{}\n", .{a, b});
    fn2_with_err_called = true;
    if (b)
        return error { Fn2WithErr }.Fn2WithErr;
}

fn fn2_return_value(a: i64, b: bool) i64 {
    // std.debug.print("fn2_return_value() called, a:{}, b:{}\n", .{a, b});
    return if (b) a * 1 else a * 2;
}

fn fn2_return_value_with_err(a: i64, b: bool) i64 {
    // std.debug.print("fn2_return_value_with_err() called, a:{}, b:{}\n", .{a, b});
    return if (b) a * 1 else a * 2;
}

fn fn2_alloc_with_err(alloc: Allocator, a: i64, b: bool) !void {
    _=a;
    _=b;
    // std.debug.print("fn2_alloc_with_err() called, a:{}, b:{}\n", .{a, b});
    // The arena allocator will take care of freeing it.
    _ = try alloc.dupe(u8, "Hello. Allocate some memory without freeing.");
    fn2_alloc_with_err_called = true;
}

const Group = struct {
    var group_fn0_called = false;
    var group_fn1_called = false;
    
    fn fn0() void {
        group_fn0_called = true;
    }

    fn fn1(_: i64) void {
        group_fn1_called = true;
    }
};


const Ctx = struct {
    var ctx_fn0_called = false;
    
    count: i64 = 0,

    // All methods must have self as pointer as the context is passed in as a pointer.
    fn get(self: *@This()) i64 {
        // std.debug.print("ctx.get() called, count:{}\n", .{self.count});
        return self.count;
    }

    fn fn0(_: *@This()) void {
        // std.debug.print("ctx.fn0() called, count:{}\n", .{self.count});
        ctx_fn0_called = true;
    }

    fn fn1(self: *@This(), a: i64) void {
        self.count += a;
        // std.debug.print("ctx.fn1() called, count:{}\n", .{self.count});
    }

    fn fn1_alloc(self: *@This(), alloc: Allocator, a: i64) !void {
        self.count += a;
        // std.debug.print("ctx.fn1_alloc() called, count:{}\n", .{self.count});
        _ = try alloc.dupe(u8, "Hello. Allocate some memory without freeing.");
    }

    fn fn_cat_value_ctx(self: *@This(), alloc: Allocator, obj: std.json.Value) !CatInfo {
        // std.debug.print("fn_cat_value_ctx() called\n", .{});
        self.count += 1;
        const parsed = try std.json.parseFromValue(CatInfo, alloc, obj, .{});
        // defer parsed.deinit();
        return .{
            .cat_name = try alloc.dupe(u8, parsed.value.cat_name),
            .weight = parsed.value.weight,
            .eye_color = try alloc.dupe(u8, parsed.value.eye_color),
        };
    }

    fn fn_cat_struct_ctx(self: *@This(), cat: CatInfo) CatInfo {
        self.count += 1;
        return .{
            .cat_name = cat.cat_name,
            .weight = cat.weight + 1,
            .eye_color = cat.eye_color,
        };
    }

    fn fn_cat_struct_ctx_alloc(self: *@This(), alloc: Allocator, cat: CatInfo) !CatInfo {
        self.count += 1;
        return .{
            .cat_name = try allocPrint(alloc, "{s}'s cousin", .{cat.cat_name}),
            .weight = cat.weight + 1,
            .eye_color = try allocPrint(alloc, "double {s}", .{cat.eye_color}),
        };
    }

};


const CatInfo = struct {
    cat_name: []const u8,
    weight: f64,
    eye_color: []const u8,
};

fn fn_cat(name: []const u8, weight: f64, color: []const u8) CatInfo {
    return .{
        .cat_name = name,
        .weight = weight,
        .eye_color = color,
    };
}

fn fn_cat_value(json_value: std.json.Value) CatInfo {
    // std.debug.print("fn_cat_value() called\n", .{});
    return .{
        .cat_name = json_value.object.get("cat_name").?.string,
        .weight = @floatFromInt(json_value.object.get("weight").?.integer),
        .eye_color = json_value.object.get("eye_color").?.string,
    };
}

fn fn_cat_value_alloc(alloc: Allocator, json_value: std.json.Value) !CatInfo {
    // std.debug.print("fn_cat_value_alloc() called\n", .{});
    _ = try alloc.dupe(u8, "Hello");
    return .{
        .cat_name = json_value.object.get("cat_name").?.string,
        .weight = @floatFromInt(json_value.object.get("weight").?.integer),
        .eye_color = json_value.object.get("eye_color").?.string,
    };
}

fn fn_cat_struct(cat: CatInfo) CatInfo {
    return .{
        .cat_name = cat.cat_name,
        .weight = cat.weight + 1,
        .eye_color = cat.eye_color,
    };
}

fn fn_cat_struct_alloc(alloc: Allocator, cat: CatInfo) !CatInfo {
    return .{
        .cat_name = try allocPrint(alloc, "{s}'s cousin", .{cat.cat_name}),
        .weight = cat.weight + 1,
        .eye_color = try allocPrint(alloc, "double {s}", .{cat.eye_color}),
    };
}

fn fn_json_value1(value1: std.json.Value) i64 {
    // std.debug.print("fn_json_value1() called {any}\n", .{value1});
    switch (value1) {
        .integer    => |num| return if (num == 1) 1 else -1,
        .array      => |array| return @intCast(array.items.len),
        else        => return -1,
    }
}

fn fn_json_value2(value1: std.json.Value, value2: std.json.Value) i64 {
    // std.debug.print("fn_json_value2() called {any}, {any}\n", .{value1, value2});
    return value1.integer + value2.integer;
}

fn fn_json_value_int(value1: std.json.Value, b: i64) i64 {
    // std.debug.print("fn_json_value_int() called {any}, {}\n", .{value1, b});
    return value1.integer + b;
}

fn fn_json_value_int_value(value1: std.json.Value, b: i64, value3: std.json.Value) i64 {
    // std.debug.print("fn_json_value_int_value() called {any}, {}, {any}\n", .{value1, b, value3});
    return value1.integer + b + value3.integer;
}


var fn_opt1_int_a: ?isize = null;

fn fn_opt1_int(a: ?isize) void {
    // std.debug.print("fn_opt1_int called, a:{any}\n", .{a});
    fn_opt1_int_a = a;
}

var fn_opt1_str_a: ?[]const u8 = null;

fn fn_opt1_str(alloc: Allocator, a: ?[]const u8) ![]const u8 {
    // std.debug.print("fn_opt1_str called, a:{any}\n", .{a});
    fn_opt1_str_a = a;
    if (a)|str| {
        return str;
    } else {
        return try allocPrint(alloc, "a is null", .{});
    }
}

var fn_opt1_cat_a: ?CatInfo = null;

fn fn_opt1_cat(a: ?CatInfo) void {
    // std.debug.print("fn_opt1_cat called, a:{any}\n", .{a});
    fn_opt1_cat_a = a;
}



const Standalone = struct {
    flag:   bool = false,
};

fn fn_standalone_on (ctx: *Standalone) void { ctx.flag = true;  }
fn fn_standalone_off(ctx: *Standalone) void { ctx.flag = false; }
fn fn_standalone_get(ctx: *Standalone) bool { return ctx.flag;  }
fn fn_standalone_msg(ctx: *Standalone, alloc: Allocator) ![]const u8 {
    return try allocPrint(alloc, "flag value is: {}", .{ ctx.flag });
}


const MyErrors = error {
    MissingName,
};


fn fun_too_many_params(_: Allocator, p1: Value, p2: Value, p3: Value, p4: Value, p5: Value,
                       p6: Value, p7: Value, p8: Value, p9: Value, p10: Value) anyerror![]const u8 {
    _=p1; _=p2; _=p3; _=p4; _=p5; _=p6; _=p7; _=p8; _=p9; _=p10;
}

fn fun_missing_allocator() void {}

fn fun_wrong_return_type(_: Allocator) void {}

fn fun_wrong_param_type(alloc: Allocator, _: u8) anyerror![]const u8 {
    return std.json.stringifyAlloc(alloc, "Hello", .{});
}

fn fun_wrong_param_type2(alloc: Allocator, _: Value, _: u8) anyerror![]const u8 {
    return std.json.stringifyAlloc(alloc, "Hello", .{});
}


test "rpc_dispatcher fn0 and variants with DispatchCtx" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    var arena = ArenaAllocator.init(alloc);
    defer arena.deinit();
    var nop_logger = zigjr.NopLogger{};

    var dc: zigjr.DispatchCtx = .{
        .arena = arena.allocator(),
        .logger = nop_logger.asLogger(),
    };

    var dispatcher = try zigjr.RpcDispatcher.init(alloc);
    defer dispatcher.deinit();
    const req_dispatcher = RequestDispatcher.implBy(&dispatcher);
    try dispatcher.add("fn0", fn0);
    try dispatcher.add("fn0_with_err", fn0_with_err);
    try dispatcher.add("fn0_return_value", fn0_return_value);
    try dispatcher.add("fn0_return_value_with_err", fn0_return_value_with_err);
    try dispatcher.add("fn0_alloc", fn0_alloc);

    {
        var parsed_req = zigjr.parseRpcRequest(alloc,
            \\{"jsonrpc": "2.0", "method": "fn0", "id": 1}
        );
        defer parsed_req.deinit();
        const req = try parsed_req.request();
        const d_result = try req_dispatcher.dispatch(&dc, &req);
        _=d_result;
        // std.debug.print("result: {any}\n", .{d_result});
        try testing.expect(fn0_called);
    }

    {
        var parsed_req = zigjr.parseRpcRequest(alloc,
            \\{"jsonrpc": "2.0", "method": "fn0_with_err", "id": 1}
        );
        defer parsed_req.deinit();
        const req = try parsed_req.request();
        const d_result = try req_dispatcher.dispatch(&dc, &req);
        std.debug.print("result: {any}\n", .{d_result});
        try testing.expect(fn0_with_err_called);
    }

}

test "rpc_dispatcher fn1 and variants with DispatchCtx" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    var arena = ArenaAllocator.init(alloc);
    defer arena.deinit();
    var nop_logger = zigjr.NopLogger{};

    var dc: zigjr.DispatchCtx = .{
        .arena = arena.allocator(),
        .logger = nop_logger.asLogger(),
    };

    var dispatcher = try zigjr.RpcDispatcher.init(alloc);
    defer dispatcher.deinit();
    const req_dispatcher = RequestDispatcher.implBy(&dispatcher);
    try dispatcher.add("fn1", fn1);
    try dispatcher.add("fn1_with_err", fn1_with_err);
    try dispatcher.add("fn1_return_value", fn1_return_value);
    try dispatcher.add("fn1_return_value_with_err", fn1_return_value_with_err);
    try dispatcher.add("fn1_alloc_with_err", fn1_alloc_with_err);

    {
        var parsed_req = zigjr.parseRpcRequest(alloc,
            \\{"jsonrpc": "2.0", "method": "fn1", "params": [1], "id": 1}
        );
        defer parsed_req.deinit();
        const req = try parsed_req.request();
        _ = try req_dispatcher.dispatch(&dc, &req);
        try testing.expect(fn1_called);
    }

    {
        var parsed_req = zigjr.parseRpcRequest(alloc,
            \\{"jsonrpc": "2.0", "method": "fn1_with_err", "params": [2], "id": 1}
        );
        defer parsed_req.deinit();
        const req = try parsed_req.request();
        _ = try req_dispatcher.dispatch(&dc, &req);
        try testing.expect(fn1_with_err_called);
    }
}

// test "rpc_dispatcher fn0" {
//     var gpa = std.heap.DebugAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const alloc = gpa.allocator();

//     {
//         var dispatcher = try zigjr.RpcDispatcher.init(alloc);
//         defer dispatcher.deinit();
//         var pipeline = zigjr.RequestPipeline.init(alloc, RequestDispatcher.implBy(&dispatcher), null);
//         defer pipeline.deinit();

//         try dispatcher.add("fn0", fn0);

//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn0", "id": 1}
//             ) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});
//             try testing.expect(fn0_called);
//         }
//     }

// }

// test "rpc_dispatcher fn0 variants" {
//     var gpa = std.heap.DebugAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const alloc = gpa.allocator();

//     {
//         var dispatcher = try zigjr.RpcDispatcher.init(alloc);
//         defer dispatcher.deinit();
//         var pipeline = zigjr.RequestPipeline.init(alloc, RequestDispatcher.implBy(&dispatcher), null);
//         defer pipeline.deinit();

//         try dispatcher.add("fn0", fn0);
//         try dispatcher.add("fn0_with_err", fn0_with_err);
//         try dispatcher.add("fn0_return_value", fn0_return_value);
//         try dispatcher.add("fn0_return_value_with_err", fn0_return_value_with_err);
//         try dispatcher.add("fn0_alloc", fn0_alloc);

//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn0", "id": 1}
//             ) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});
//             try testing.expect(fn0_called);
//         }

//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn0_with_err", "id": 1}
//             ) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});
//             try testing.expect(fn0_with_err_called);
//         }
        
//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn0_return_value", "id": 1}
//             ) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             try testing.expect((try res_result.response()).resultEql("Hello"));
//         }
        
//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn0_return_value_with_err", "id": 1}
//             ) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             try testing.expect((try res_result.response()).resultEql("Hello"));
//         }

//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn0_alloc", "id": 1}
//             ) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});
//             try testing.expect(fn0_alloc_called);
//         }

//     }

// }


// test "rpc_dispatcher fn1" {
//     var gpa = std.heap.DebugAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const alloc = gpa.allocator();

//     {
//         var dispatcher = try zigjr.RpcDispatcher.init(alloc);
//         defer dispatcher.deinit();
//         var pipeline = zigjr.RequestPipeline.init(alloc, RequestDispatcher.implBy(&dispatcher), null);
//         defer pipeline.deinit();

//         try dispatcher.add("fn1", fn1);
//         try dispatcher.add("fn1_with_err", fn1_with_err);
//         try dispatcher.add("fn1_return_value", fn1_return_value);
//         try dispatcher.add("fn1_return_value_with_err", fn1_return_value_with_err);
//         try dispatcher.add("fn1_alloc_with_err", fn1_alloc_with_err);

//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn1", "params": [1], "id": 1}
//             ) orelse "";
//             defer alloc.free(res_json);
//             try testing.expect(fn1_called);
//         }

//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn1_with_err", "params": [2], "id": 1}
//             ) orelse "";
//             defer alloc.free(res_json);
//             try testing.expect(fn1_with_err_called);
//         }
        
//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn1_return_value", "params": [3], "id": 1}
//             ) orelse "";
//             defer alloc.free(res_json);

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             try testing.expect((try res_result.response()).resultEql("Hello"));
//         }
        
//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn1_return_value_with_err", "params": [4], "id": 1}
//             ) orelse "";
//             defer alloc.free(res_json);

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             try testing.expect((try res_result.response()).resultEql("Hello"));
//         }

//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn1_alloc_with_err", "params": [1], "id": 1}
//             ) orelse "";
//             defer alloc.free(res_json);

//             try testing.expect(res_json.len == 0);
//         }

//     }

// }


// test "rpc_dispatcher fn2" {
//     var gpa = std.heap.DebugAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const alloc = gpa.allocator();

//     {
//         var dispatcher = try zigjr.RpcDispatcher.init(alloc);
//         defer dispatcher.deinit();
//         var pipeline = zigjr.RequestPipeline.init(alloc, RequestDispatcher.implBy(&dispatcher), null);
//         defer pipeline.deinit();

//         try dispatcher.add("fn2", fn2);
//         try dispatcher.add("fn2_with_err", fn2_with_err);
//         try dispatcher.add("fn2_return_value", fn2_return_value);
//         try dispatcher.add("fn2_return_value_with_err", fn2_return_value_with_err);
//         try dispatcher.add("fn2_alloc_with_err", fn2_alloc_with_err);

//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn2", "params": [1, true], "id": 1}
//             ) orelse "";
//             defer alloc.free(res_json);
//             try testing.expect(fn2_called);
//         }

//         fn2_with_err_called = false;
//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn2_with_err", "params": [2, false], "id": 1}
//             ) orelse "";
//             defer alloc.free(res_json);
//             try testing.expect(fn2_with_err_called);
//         }

//         fn2_with_err_called = false;
//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn2_with_err", "params": [2, true], "id": 1}
//             ) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});
//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             try testing.expect(fn2_with_err_called);
//             try testing.expect((try res_result.response()).hasErr());
//             try testing.expect((try res_result.response()).err().code == @intFromEnum(ErrorCode.ServerError));
//             try testing.expectEqualStrings((try res_result.response()).err().message, "Fn2WithErr");
//         }

//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn2_return_value", "params": [3, true], "id": 1}
//             ) orelse "";
//             defer alloc.free(res_json);

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             try testing.expect((try res_result.response()).resultEql(3));
//         }

//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn2_return_value_with_err", "params": [4, false], "id": 1}
//             ) orelse "";
//             defer alloc.free(res_json);

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             try testing.expect((try res_result.response()).resultEql(8));
//         }
        
//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn2_alloc_with_err", "params": [1, true], "id": 1}
//             ) orelse "";
//             defer alloc.free(res_json);
//             try testing.expect(fn2_alloc_with_err_called);
//         }

//     }

// }


// test "rpc_dispatcher with struct scope functions" {
//     var gpa = std.heap.DebugAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const alloc = gpa.allocator();

//     {
//         var dispatcher = try zigjr.RpcDispatcher.init(alloc);
//         defer dispatcher.deinit();
//         var pipeline = zigjr.RequestPipeline.init(alloc, RequestDispatcher.implBy(&dispatcher), null);
//         defer pipeline.deinit();

//         try dispatcher.add("fn0", Group.fn0);
//         try dispatcher.add("fn1", Group.fn1);

//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn0", "id": 1}
//             ) orelse "";
//             defer alloc.free(res_json);
//             try testing.expect(Group.group_fn0_called);
//         }
//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn1", "params": [1], "id": 1}
//             ) orelse "";
//             defer alloc.free(res_json);
//             try testing.expect(Group.group_fn1_called);
//         }
//     }

// }


// test "rpc_dispatcher with context" {
//     var gpa = std.heap.DebugAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const alloc = gpa.allocator();

//     {
//         var dispatcher = try zigjr.RpcDispatcher.init(alloc);
//         defer dispatcher.deinit();
//         var pipeline = zigjr.RequestPipeline.init(alloc, RequestDispatcher.implBy(&dispatcher), null);
//         defer pipeline.deinit();

//         var ctx = Ctx { .count = 0 };

//         try dispatcher.addWithCtx("ctx.get", &ctx, Ctx.get);
//         try dispatcher.addWithCtx("ctx.fn0", &ctx, Ctx.fn0);
//         try dispatcher.addWithCtx("ctx.fn1", &ctx, Ctx.fn1);
//         try dispatcher.addWithCtx("ctx.fn1_alloc", &ctx, Ctx.fn1_alloc);

//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "ctx.get", "id": 1}
//             ) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             try testing.expect((try res_result.response()).resultEql(0));
//         }

//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "ctx.fn0", "id": 1}
//             ) orelse "";
//             defer alloc.free(res_json);
//             try testing.expect(Ctx.ctx_fn0_called);
//         }

//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "ctx.fn1", "params": [2], "id": 1}
//             ) orelse "";
//             defer alloc.free(res_json);

//             try testing.expect(res_json.len == 0);
//         }

//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "ctx.fn1_alloc", "params": [2], "id": 1}
//             ) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});

//             try testing.expect(res_json.len == 0);
//         }

//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "ctx.get", "id": 1}
//             ) orelse "";

//             defer alloc.free(res_json);

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             try testing.expect((try res_result.response()).resultEql(4));
//         }

//     }

// }


// test "rpc_dispatcher fn with array params returning struct value" {
//     var gpa = std.heap.DebugAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const alloc = gpa.allocator();

//     {
//         var dispatcher = try zigjr.RpcDispatcher.init(alloc);
//         defer dispatcher.deinit();
//         var pipeline = zigjr.RequestPipeline.init(alloc, RequestDispatcher.implBy(&dispatcher), null);
//         defer pipeline.deinit();

//         try dispatcher.addWithCtx("fn_cat", null, fn_cat);

//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn_cat", "params": ["cat1", 9, "blue"], "id": 1}
//             ) orelse "";

//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             // std.debug.print("result: {any}\n", .{(try res_result.response()).result});
//             const parsed_cat = try std.json.parseFromValue(CatInfo, alloc, (try res_result.response()).result, .{});
//             defer parsed_cat.deinit();
//             // std.debug.print("cat: {any}\n", .{parsed_cat.value});
//             try testing.expectEqualSlices(u8, parsed_cat.value.cat_name, "cat1");
//             try testing.expectEqualSlices(u8, parsed_cat.value.eye_color, "blue");
//             try testing.expectEqual(parsed_cat.value.weight, 9);
//         }

//     }

// }


// test "rpc_dispatcher fn with built array params returning struct value" {
//     var gpa = std.heap.DebugAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const alloc = gpa.allocator();

//     {
//         var dispatcher = try zigjr.RpcDispatcher.init(alloc);
//         defer dispatcher.deinit();
//         var pipeline = zigjr.RequestPipeline.init(alloc, RequestDispatcher.implBy(&dispatcher), null);
//         defer pipeline.deinit();

//         try dispatcher.addWithCtx("fn_cat", null, fn_cat);

//         {
//             const params = .{"cat1", 9, "blue"};
//             const req_json = try zigjr.composer.makeRequestJson(alloc, "fn_cat", params, .{ .num = 1 });
//             defer alloc.free(req_json);
//             // std.debug.print("request: {s}\n", .{req_json});

//             const res_json = try pipeline.runRequestToJson(alloc,  req_json) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             // std.debug.print("result: {any}\n", .{(try res_result.response()).result});
//             const parsed_cat = try std.json.parseFromValue(CatInfo, alloc, (try res_result.response()).result, .{});
//             defer parsed_cat.deinit();
//             // std.debug.print("cat: {any}\n", .{parsed_cat.value});
//             try testing.expectEqualSlices(u8, parsed_cat.value.cat_name, "cat1");
//             try testing.expectEqualSlices(u8, parsed_cat.value.eye_color, "blue");
//             try testing.expectEqual(parsed_cat.value.weight, 9);
//         }

//     }

// }


// test "rpc_dispatcher passing in an Value as a parameter" {
//     var gpa = std.heap.DebugAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const alloc = gpa.allocator();

//     {
//         var dispatcher = try zigjr.RpcDispatcher.init(alloc);
//         defer dispatcher.deinit();
//         var pipeline = zigjr.RequestPipeline.init(alloc, RequestDispatcher.implBy(&dispatcher), null);
//         defer pipeline.deinit();

//         try dispatcher.addWithCtx("fn_cat_value", null, fn_cat_value);

//         {
//             const cat3 = CatInfo { .cat_name = "cat3", .weight = 5.0, .eye_color = "black" };
//             const req_json = try zigjr.composer.makeRequestJson(alloc, "fn_cat_value", cat3, .{ .num = 1 });
//             defer alloc.free(req_json);
//             // std.debug.print("request: {s}\n", .{req_json});

//             const res_json = try pipeline.runRequestToJson(alloc,  req_json) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             // std.debug.print("result: {any}\n", .{(try res_result.response()).result});
//             const parsed_cat = try std.json.parseFromValue(CatInfo, alloc, (try res_result.response()).result, .{});
//             defer parsed_cat.deinit();
//             // std.debug.print("cat: {any}\n", .{parsed_cat.value});
//             try testing.expectEqualSlices(u8, parsed_cat.value.cat_name, "cat3");
//             try testing.expectEqualSlices(u8, parsed_cat.value.eye_color, "black");
//             try testing.expectEqual(parsed_cat.value.weight, 5.0);
//         }

//     }

// }


// test "rpc_dispatcher passing in an Value as a parameter, with an Allocator as the first parameter" {
//     var gpa = std.heap.DebugAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const alloc = gpa.allocator();

//     {
//         var dispatcher = try zigjr.RpcDispatcher.init(alloc);
//         defer dispatcher.deinit();
//         var pipeline = zigjr.RequestPipeline.init(alloc, RequestDispatcher.implBy(&dispatcher), null);
//         defer pipeline.deinit();

//         try dispatcher.addWithCtx("fn_cat_value_alloc", null, fn_cat_value_alloc);
//         {
//             const cat3 = CatInfo { .cat_name = "cat3", .weight = 5.0, .eye_color = "black" };
//             const req_json = try zigjr.composer.makeRequestJson(alloc, "fn_cat_value_alloc", cat3, .{ .num = 1 });
//             defer alloc.free(req_json);
//             // std.debug.print("request: {s}\n", .{req_json});

//             const res_json = try pipeline.runRequestToJson(alloc,  req_json) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             // std.debug.print("result: {any}\n", .{(try res_result.response()).result});
//             const parsed_cat = try std.json.parseFromValue(CatInfo, alloc, (try res_result.response()).result, .{});
//             defer parsed_cat.deinit();
//             // std.debug.print("cat: {any}\n", .{parsed_cat.value});
//             try testing.expectEqualSlices(u8, parsed_cat.value.cat_name, "cat3");
//             try testing.expectEqualSlices(u8, parsed_cat.value.eye_color, "black");
//             try testing.expectEqual(parsed_cat.value.weight, 5.0);
//         }

//     }

// }


// test "rpc_dispatcher passing in a Value(.object) as a parameter, with a context, parsing the Value to a struct" {
//     var gpa = std.heap.DebugAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const alloc = gpa.allocator();

//     {
//         var dispatcher = try zigjr.RpcDispatcher.init(alloc);
//         defer dispatcher.deinit();
//         var pipeline = zigjr.RequestPipeline.init(alloc, RequestDispatcher.implBy(&dispatcher), null);
//         defer pipeline.deinit();

//         var ctx = Ctx { .count = 0 };

//         try dispatcher.addWithCtx("ctx.fn_cat_value_ctx", &ctx, Ctx.fn_cat_value_ctx);

//         {
//             const cat3 = CatInfo { .cat_name = "cat3", .weight = 5.0, .eye_color = "brown" };
//             const req_json = try zigjr.composer.makeRequestJson(alloc, "ctx.fn_cat_value_ctx", cat3, .{ .num = 1 });
//             defer alloc.free(req_json);
//             // std.debug.print("request: {s}\n", .{req_json});

//             const res_json = try pipeline.runRequestToJson(alloc,  req_json) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             // std.debug.print("result: {any}\n", .{(try res_result.response()).result});
//             const parsed_cat = try std.json.parseFromValue(CatInfo, alloc, (try res_result.response()).result, .{});
//             defer parsed_cat.deinit();
//             // std.debug.print("cat1: {any}\n", .{parsed_cat.value});
//             try testing.expectEqualSlices(u8, parsed_cat.value.cat_name, "cat3");
//             try testing.expectEqualSlices(u8, parsed_cat.value.eye_color, "brown");
//             try testing.expectEqual(parsed_cat.value.weight, 5);
//         }

//     }

// }


// test "rpc_dispatcher passing in a single JSON Value as parameter" {
//     var gpa = std.heap.DebugAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const alloc = gpa.allocator();

//     {
//         var dispatcher = try zigjr.RpcDispatcher.init(alloc);
//         defer dispatcher.deinit();
//         var pipeline = zigjr.RequestPipeline.init(alloc, RequestDispatcher.implBy(&dispatcher), null);
//         defer pipeline.deinit();

//         try dispatcher.addWithCtx("fn_json_value1", null, fn_json_value1);
//         {
//             const req_json = try zigjr.composer.makeRequestJson(alloc, "fn_json_value1", .{1}, .{ .num = 1 });
//             defer alloc.free(req_json);
//             // std.debug.print("request: {s}\n", .{req_json});

//             const res_json = try pipeline.runRequestToJson(alloc,  req_json) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             try testing.expect((try res_result.response()).resultEql(1));
//         }

//         try dispatcher.addWithCtx("fn_json_value1", null, fn_json_value1);
//         {
//             const req_json = try zigjr.composer.makeRequestJson(alloc, "fn_json_value1", .{1, 2, 3}, .{ .num = 1 });
//             defer alloc.free(req_json);
//             // std.debug.print("request: {s}\n", .{req_json});

//             const res_json = try pipeline.runRequestToJson(alloc,  req_json) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             try testing.expect((try res_result.response()).resultEql(3));
//         }

//     }

// }


// test "rpc_dispatcher passing in two JSON Values as parameters" {
//     var gpa = std.heap.DebugAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const alloc = gpa.allocator();

//     {
//         var dispatcher = try zigjr.RpcDispatcher.init(alloc);
//         defer dispatcher.deinit();
//         var pipeline = zigjr.RequestPipeline.init(alloc, RequestDispatcher.implBy(&dispatcher), null);
//         defer pipeline.deinit();

//         try dispatcher.addWithCtx("fn_json_value2", null, fn_json_value2);
//         {
//             const req_json = try zigjr.composer.makeRequestJson(alloc, "fn_json_value2", .{1, 2}, .{ .num = 1 });
//             defer alloc.free(req_json);
//             // std.debug.print("request: {s}\n", .{req_json});

//             const res_json = try pipeline.runRequestToJson(alloc,  req_json) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             try testing.expect((try res_result.response()).resultEql(3));
//         }

//     }

// }


// test "rpc_dispatcher passing in one JSON Value and one primitive as parameters" {
//     var gpa = std.heap.DebugAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const alloc = gpa.allocator();

//     {
//         var dispatcher = try zigjr.RpcDispatcher.init(alloc);
//         defer dispatcher.deinit();
//         var pipeline = zigjr.RequestPipeline.init(alloc, RequestDispatcher.implBy(&dispatcher), null);
//         defer pipeline.deinit();

//         try dispatcher.addWithCtx("fn_json_value_int", null, fn_json_value_int);
//         {
//             const req_json = try zigjr.composer.makeRequestJson(alloc, "fn_json_value_int", .{1, 2}, .{ .num = 1 });
//             defer alloc.free(req_json);
//             // std.debug.print("request: {s}\n", .{req_json});

//             const res_json = try pipeline.runRequestToJson(alloc,  req_json) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             try testing.expect((try res_result.response()).resultEql(3));
//         }

//     }

// }


// test "rpc_dispatcher passing in one JSON Value, one primitive, and one Value as parameters" {
//     var gpa = std.heap.DebugAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const alloc = gpa.allocator();

//     {
//         var dispatcher = try zigjr.RpcDispatcher.init(alloc);
//         defer dispatcher.deinit();
//         var pipeline = zigjr.RequestPipeline.init(alloc, RequestDispatcher.implBy(&dispatcher), null);
//         defer pipeline.deinit();

//         try dispatcher.addWithCtx("fn_json_value_int_value", null, fn_json_value_int_value);
//         {
//             const req_json = try zigjr.composer.makeRequestJson(alloc, "fn_json_value_int_value", .{1, 2, 3}, .{ .num = 1 });
//             defer alloc.free(req_json);
//             // std.debug.print("request: {s}\n", .{req_json});

//             const res_json = try pipeline.runRequestToJson(alloc,  req_json) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             try testing.expect((try res_result.response()).resultEql(6));
//         }

//     }

// }


// test "rpc_dispatcher passing in a struct object as a parameter" {
//     var gpa = std.heap.DebugAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const alloc = gpa.allocator();

//     {
//         var dispatcher = try zigjr.RpcDispatcher.init(alloc);
//         defer dispatcher.deinit();
//         var pipeline = zigjr.RequestPipeline.init(alloc, RequestDispatcher.implBy(&dispatcher), null);
//         defer pipeline.deinit();

//         try dispatcher.addWithCtx("fn_cat_struct", null, fn_cat_struct);

//         {
//             const cat4 = CatInfo { .cat_name = "cat4", .weight = 5.0, .eye_color = "blue" };
//             const req_json = try zigjr.composer.makeRequestJson(alloc, "fn_cat_struct", cat4, .{ .num = 1 });
//             defer alloc.free(req_json);
//             // std.debug.print("request: {s}\n", .{req_json});

//             const res_json = try pipeline.runRequestToJson(alloc,  req_json) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             // std.debug.print("result: {any}\n", .{(try res_result.response()).result});
//             const parsed_cat = try std.json.parseFromValue(CatInfo, alloc, (try res_result.response()).result, .{});
//             defer parsed_cat.deinit();
//             // std.debug.print("cat1: {any}\n", .{parsed_cat.value});
//             try testing.expectEqualSlices(u8, parsed_cat.value.cat_name, "cat4");
//             try testing.expectEqualSlices(u8, parsed_cat.value.eye_color, "blue");
//             try testing.expectEqual(parsed_cat.value.weight, 6);
//         }

//     }

// }


// test "rpc_dispatcher passing in a struct object as a parameter, with Allocator parameter" {
//     var gpa = std.heap.DebugAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const alloc = gpa.allocator();

//     {
//         var dispatcher = try zigjr.RpcDispatcher.init(alloc);
//         defer dispatcher.deinit();
//         var pipeline = zigjr.RequestPipeline.init(alloc, RequestDispatcher.implBy(&dispatcher), null);
//         defer pipeline.deinit();

//         try dispatcher.addWithCtx("fn_cat_struct_alloc", null, fn_cat_struct_alloc);

//         {
//             const cat5 = CatInfo { .cat_name = "cat5", .weight = 5.0, .eye_color = "blue" };
//             const req_json = try zigjr.composer.makeRequestJson(alloc, "fn_cat_struct_alloc", cat5, .{ .num = 1 });
//             defer alloc.free(req_json);
//             // std.debug.print("request: {s}\n", .{req_json});

//             const res_json = try pipeline.runRequestToJson(alloc,  req_json) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             // std.debug.print("result: {any}\n", .{(try res_result.response()).result});
//             const parsed_cat = try std.json.parseFromValue(CatInfo, alloc, (try res_result.response()).result, .{});
//             defer parsed_cat.deinit();
//             // std.debug.print("cat1: {any}\n", .{parsed_cat.value});
//             try testing.expectEqualSlices(u8, parsed_cat.value.cat_name, "cat5's cousin");
//             try testing.expectEqualSlices(u8, parsed_cat.value.eye_color, "double blue");
//             try testing.expectEqual(parsed_cat.value.weight, 6);
//         }

//     }

// }


// test "rpc_dispatcher passing in a struct object as a parameter, on a ctx" {
//     var gpa = std.heap.DebugAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const alloc = gpa.allocator();

//     {
//         var dispatcher = try zigjr.RpcDispatcher.init(alloc);
//         defer dispatcher.deinit();
//         var pipeline = zigjr.RequestPipeline.init(alloc, RequestDispatcher.implBy(&dispatcher), null);
//         defer pipeline.deinit();

//         var ctx = Ctx { .count = 0 };

//         try dispatcher.addWithCtx("fn_cat_struct_ctx", &ctx, Ctx.fn_cat_struct_ctx);

//         {
//             const cat4 = CatInfo { .cat_name = "cat4", .weight = 5.0, .eye_color = "blue" };
//             const req_json = try zigjr.composer.makeRequestJson(alloc, "fn_cat_struct_ctx", cat4, .{ .num = 1 });
//             defer alloc.free(req_json);
//             // std.debug.print("request: {s}\n", .{req_json});

//             const res_json = try pipeline.runRequestToJson(alloc,  req_json) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             // std.debug.print("result: {any}\n", .{(try res_result.response()).result});
//             const parsed_cat = try std.json.parseFromValue(CatInfo, alloc, (try res_result.response()).result, .{});
//             defer parsed_cat.deinit();
//             // std.debug.print("cat1: {any}\n", .{parsed_cat.value});
//             try testing.expectEqualSlices(u8, parsed_cat.value.cat_name, "cat4");
//             try testing.expectEqualSlices(u8, parsed_cat.value.eye_color, "blue");
//             try testing.expectEqual(parsed_cat.value.weight, 6);
//         }

//     }

// }


// test "rpc_dispatcher passing in a struct object as a parameter, on a ctx, with Allocator parameter" {
//     var gpa = std.heap.DebugAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const alloc = gpa.allocator();

//     {
//         var dispatcher = try zigjr.RpcDispatcher.init(alloc);
//         defer dispatcher.deinit();
//         var pipeline = zigjr.RequestPipeline.init(alloc, RequestDispatcher.implBy(&dispatcher), null);
//         defer pipeline.deinit();

//         var ctx = Ctx { .count = 0 };

//         try dispatcher.addWithCtx("fn_cat_struct_ctx_alloc", &ctx, Ctx.fn_cat_struct_ctx_alloc);

//         {
//             const cat4 = CatInfo { .cat_name = "cat4", .weight = 5.0, .eye_color = "blue" };
//             const req_json = try zigjr.composer.makeRequestJson(alloc, "fn_cat_struct_ctx_alloc", cat4, .{ .num = 1 });
//             defer alloc.free(req_json);
//             // std.debug.print("request: {s}\n", .{req_json});

//             const res_json = try pipeline.runRequestToJson(alloc,  req_json) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             // std.debug.print("result: {any}\n", .{(try res_result.response()).result});
//             const parsed_cat = try std.json.parseFromValue(CatInfo, alloc, (try res_result.response()).result, .{});
//             defer parsed_cat.deinit();
//             // std.debug.print("cat1: {any}\n", .{parsed_cat.value});
//             try testing.expectEqualSlices(u8, parsed_cat.value.cat_name, "cat4's cousin");
//             try testing.expectEqualSlices(u8, parsed_cat.value.eye_color, "double blue");
//             try testing.expectEqual(parsed_cat.value.weight, 6);
//         }

//     }

// }


// test "rpc_dispatcher register standalone functions on standalone object." {
//     var gpa = std.heap.DebugAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const alloc = gpa.allocator();

//     {
//         var dispatcher = try zigjr.RpcDispatcher.init(alloc);
//         defer dispatcher.deinit();
//         var pipeline = zigjr.RequestPipeline.init(alloc, RequestDispatcher.implBy(&dispatcher), null);
//         defer pipeline.deinit();

//         var s = Standalone{};

//         try dispatcher.addWithCtx("fn_standalone_on", &s, fn_standalone_on);
//         try dispatcher.addWithCtx("fn_standalone_off", &s, fn_standalone_off);
//         try dispatcher.addWithCtx("fn_standalone_get", &s, fn_standalone_get);
//         try dispatcher.addWithCtx("fn_standalone_msg", &s, fn_standalone_msg);

//         {
//             const req_json = try zigjr.composer.makeRequestJson(alloc, "fn_standalone_on", null, .none);
//             defer alloc.free(req_json);

//             const res_json = try pipeline.runRequestToJson(alloc,  req_json) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});
//         }

//         {
//             const req_json = try zigjr.composer.makeRequestJson(alloc, "fn_standalone_get", null, .{ .num = 1 });
//             defer alloc.free(req_json);

//             const res_json = try pipeline.runRequestToJson(alloc,  req_json) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             try testing.expect((try res_result.response()).resultEql(true));
//         }

//         {
//             const req_json = try zigjr.composer.makeRequestJson(alloc, "fn_standalone_off", null, .none);
//             defer alloc.free(req_json);

//             const res_json = try pipeline.runRequestToJson(alloc,  req_json) orelse "";
//             defer alloc.free(res_json);
//         }

//         {
//             const req_json = try zigjr.composer.makeRequestJson(alloc, "fn_standalone_get", null, .{ .num = 1 });
//             defer alloc.free(req_json);

//             const res_json = try pipeline.runRequestToJson(alloc,  req_json) orelse "";
//             defer alloc.free(res_json);

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             try testing.expect((try res_result.response()).resultEql(false));
//         }

//         {
//             const req_json = try zigjr.composer.makeRequestJson(alloc, "fn_standalone_msg", null, .{ .num = 1 });
//             defer alloc.free(req_json);

//             const res_json = try pipeline.runRequestToJson(alloc, req_json) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             try testing.expect((try res_result.response()).resultEql("flag value is: false"));
//         }
//     }

// }

// test "rpc_dispatcher register functions with an optional parameter." {
//     var gpa = std.heap.DebugAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const alloc = gpa.allocator();

//     {
//         var dispatcher = try zigjr.RpcDispatcher.init(alloc);
//         defer dispatcher.deinit();
//         var pipeline = zigjr.RequestPipeline.init(alloc, RequestDispatcher.implBy(&dispatcher), null);
//         defer pipeline.deinit();

//         try dispatcher.add("fn_opt1_int", fn_opt1_int);
//         try dispatcher.add("fn_opt1_str", fn_opt1_str);
//         try dispatcher.add("fn_opt1_cat", fn_opt1_cat);

//         {
//             const req_json = try zigjr.composer.makeRequestJson(alloc, "fn_opt1_int", null, .{ .num = 1});
//             // std.debug.print("request: {s}\n", .{req_json});
//             defer alloc.free(req_json);

//             const res_json = try pipeline.runRequestToJson(alloc,  req_json) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});
//             try testing.expect(fn_opt1_int_a == null);
//         }

//         {
//             const req_json = try zigjr.composer.makeRequestJson(alloc, "fn_opt1_int", .{123}, .{ .num = 1});
//             // std.debug.print("request: {s}\n", .{req_json});
//             defer alloc.free(req_json);

//             const res_json = try pipeline.runRequestToJson(alloc,  req_json) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});
//             try testing.expect(fn_opt1_int_a == 123);
//         }

//         {
//             const req_json = try zigjr.composer.makeRequestJson(alloc, "fn_opt1_str", null, .{ .num = 1});
//             // std.debug.print("request: {s}\n", .{req_json});
//             defer alloc.free(req_json);

//             const res_json = try pipeline.runRequestToJson(alloc,  req_json) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});
//             try testing.expect(fn_opt1_str_a == null);
//         }

//         {
//             const req_json = try zigjr.composer.makeRequestJson(alloc, "fn_opt1_str", .{"abc"}, .{ .num = 1});
//             // std.debug.print("request: {s}\n", .{req_json});
//             defer alloc.free(req_json);

//             const res_json = try pipeline.runRequestToJson(alloc,  req_json) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});
//             try testing.expectEqualStrings(fn_opt1_str_a.?, "abc");
//         }

//         {
//             const req_json = try zigjr.composer.makeRequestJson(alloc, "fn_opt1_cat", null, .{ .num = 1});
//             // std.debug.print("request: {s}\n", .{req_json});
//             defer alloc.free(req_json);

//             const res_json = try pipeline.runRequestToJson(alloc,  req_json) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});
//             try testing.expect(fn_opt1_cat_a == null);
//         }

//         {
//             const cat1 = CatInfo { .cat_name = "cat1", .weight = 5.0, .eye_color = "blue" };
//             const req_json = try zigjr.composer.makeRequestJson(alloc, "fn_opt1_cat", cat1, .{ .num = 1});
//             // std.debug.print("request: {s}\n", .{req_json});
//             defer alloc.free(req_json);

//             const res_json = try pipeline.runRequestToJson(alloc,  req_json) orelse "";
//             defer alloc.free(res_json);
//             // std.debug.print("response: {s}\n", .{res_json});
//             try testing.expectEqualStrings(fn_opt1_cat_a.?.cat_name, "cat1");
//         }

//     }

// }

// test "rpc_dispatcher extended handlers" {
//     var gpa = std.heap.DebugAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const alloc = gpa.allocator();

//     {
//         var dispatcher = try zigjr.RpcDispatcher.init(alloc);
//         defer dispatcher.deinit();
//         var pipeline = zigjr.RequestPipeline.init(alloc, RequestDispatcher.implBy(&dispatcher), null);
//         defer pipeline.deinit();

//         try dispatcher.add("fn2", fn2);
//         try dispatcher.add("fn2_with_err", fn2_with_err);
//         try dispatcher.add("fn2_return_value", fn2_return_value);
//         try dispatcher.add("fn2_return_value_with_err", fn2_return_value_with_err);
//         try dispatcher.add("fn2_alloc_with_err", fn2_alloc_with_err);

//         const ExtHandlers = struct {
//             var on_before_called = false;
//             var on_before_id = zigjr.RpcId.ofNone();
//             var on_after_called = false;
//             var on_after_id = zigjr.RpcId.ofNone();
//             var on_error_called = false;
//             var on_error_id = zigjr.RpcId.ofNone();
//             var on_error_err: anyerror = undefined;
//             var on_fallback_called = false;
//             var on_fallback_id = zigjr.RpcId.ofNone();

//             fn onBefore(_: *anyopaque, _: Allocator, req: RpcRequest) void {
//                 on_before_called = true;
//                 on_before_id = req.id;
//             }

//             fn onAfter(_: *anyopaque, _: Allocator, req: RpcRequest, res: DispatchResult) void {
//                 _=res;
//                 on_after_called = true;
//                 on_after_id = req.id;
//             }

//             fn onError(_: *anyopaque, _: Allocator, req: RpcRequest, err: anyerror) void {
//                 on_error_err = err;
//                 on_error_called = true;
//                 on_error_id = req.id;
//             }

//             fn onFallback(_: *anyopaque, _: Allocator, req: RpcRequest) anyerror!DispatchResult {
//                 on_fallback_called = true;
//                 on_fallback_id = req.id;
//                 return DispatchResult.asNone();
//             }
            
//         };

//         dispatcher.setOnBefore(null, ExtHandlers.onBefore);
//         dispatcher.setOnAfter(null, ExtHandlers.onAfter);
//         dispatcher.setOnError(null, ExtHandlers.onError);
//         dispatcher.setOnFallback(null, ExtHandlers.onFallback);

//         ExtHandlers.on_before_called = false;
//         ExtHandlers.on_before_id = zigjr.RpcId.ofNone();
//         ExtHandlers.on_after_called = false;
//         ExtHandlers.on_after_id = zigjr.RpcId.ofNone();
//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn2", "params": [1, true], "id": 1}
//             ) orelse "";
//             defer alloc.free(res_json);

//             try testing.expect(ExtHandlers.on_before_called);
//             try testing.expect(ExtHandlers.on_before_id.eql(1));
//             try testing.expect(ExtHandlers.on_after_called);
//             try testing.expect(ExtHandlers.on_after_id.eql(1));
//             try testing.expect(!ExtHandlers.on_fallback_called);
//         }

//         ExtHandlers.on_before_called = false;
//         ExtHandlers.on_before_id = zigjr.RpcId.ofNone();
//         ExtHandlers.on_after_called = false;
//         ExtHandlers.on_after_id = zigjr.RpcId.ofNone();
//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn2_with_err", "params": [2, false], "id": 2}
//             ) orelse "";
//             defer alloc.free(res_json);

//             try testing.expect(ExtHandlers.on_before_called);
//             try testing.expect(ExtHandlers.on_before_id.eql(2));
//             try testing.expect(ExtHandlers.on_after_called);
//             try testing.expect(ExtHandlers.on_after_id.eql(2));
//             try testing.expect(!ExtHandlers.on_fallback_called);
//         }

//         ExtHandlers.on_before_called = false;
//         ExtHandlers.on_before_id = zigjr.RpcId.ofNone();
//         ExtHandlers.on_after_called = false;
//         ExtHandlers.on_after_id = zigjr.RpcId.ofNone();
//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn2_with_err", "params": [2, true], "id": 2}
//             ) orelse "";
//             defer alloc.free(res_json);

//             var res_result = zigjr.parseRpcResponse(alloc, res_json);
//             defer res_result.deinit();
//             try testing.expect(fn2_with_err_called);
//             try testing.expect((try res_result.response()).hasErr());
//             try testing.expect((try res_result.response()).err().code == @intFromEnum(ErrorCode.ServerError));
//             try testing.expectEqualStrings((try res_result.response()).err().message, "Fn2WithErr");

//             try testing.expect(ExtHandlers.on_before_called);
//             try testing.expect(ExtHandlers.on_before_id.eql(2));
//             try testing.expect(!ExtHandlers.on_after_called);
//             try testing.expect(ExtHandlers.on_error_called);
//             try testing.expect(ExtHandlers.on_error_id.eql(2));
//             try testing.expect(ExtHandlers.on_error_err == error{Fn2WithErr}.Fn2WithErr);
//             try testing.expect(!ExtHandlers.on_fallback_called);
//         }
        
//         ExtHandlers.on_before_called = false;
//         ExtHandlers.on_before_id = zigjr.RpcId.ofNone();
//         ExtHandlers.on_after_called = false;
//         ExtHandlers.on_after_id = zigjr.RpcId.ofNone();
//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn2_return_value", "params": [3, true], "id": 3}
//             ) orelse "";
//             defer alloc.free(res_json);

//             try testing.expect(ExtHandlers.on_before_called);
//             try testing.expect(ExtHandlers.on_before_id.eql(3));
//             try testing.expect(ExtHandlers.on_after_called);
//             try testing.expect(ExtHandlers.on_after_id.eql(3));
//             try testing.expect(!ExtHandlers.on_fallback_called);
//         }
        
//         ExtHandlers.on_before_called = false;
//         ExtHandlers.on_before_id = zigjr.RpcId.ofNone();
//         ExtHandlers.on_after_called = false;
//         ExtHandlers.on_after_id = zigjr.RpcId.ofNone();
//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn2_return_value_with_err", "params": [4, false], "id": 4}
//             ) orelse "";
//             defer alloc.free(res_json);

//             try testing.expect(ExtHandlers.on_before_called);
//             try testing.expect(ExtHandlers.on_before_id.eql(4));
//             try testing.expect(ExtHandlers.on_after_called);
//             try testing.expect(ExtHandlers.on_after_id.eql(4));
//             try testing.expect(!ExtHandlers.on_fallback_called);
//         }
        
//         ExtHandlers.on_before_called = false;
//         ExtHandlers.on_before_id = zigjr.RpcId.ofNone();
//         ExtHandlers.on_after_called = false;
//         ExtHandlers.on_after_id = zigjr.RpcId.ofNone();
//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "fn2_alloc_with_err", "params": [1, true], "id": 5}
//             ) orelse "";
//             defer alloc.free(res_json);

//             try testing.expect(ExtHandlers.on_before_called);
//             try testing.expect(ExtHandlers.on_before_id.eql(5));
//             try testing.expect(ExtHandlers.on_after_called);
//             try testing.expect(ExtHandlers.on_after_id.eql(5));
//             try testing.expect(!ExtHandlers.on_fallback_called);
//         }

//         ExtHandlers.on_before_called = false;
//         ExtHandlers.on_before_id = zigjr.RpcId.ofNone();
//         ExtHandlers.on_after_called = false;
//         ExtHandlers.on_after_id = zigjr.RpcId.ofNone();
//         ExtHandlers.on_fallback_called = false;
//         ExtHandlers.on_fallback_id = zigjr.RpcId.ofNone();
//         {
//             const res_json = try pipeline.runRequestToJson(alloc, 
//                 \\{"jsonrpc": "2.0", "method": "foobar", "params": [1, true], "id": 6}
//             ) orelse "";
//             defer alloc.free(res_json);

//             try testing.expect(ExtHandlers.on_before_called);
//             try testing.expect(ExtHandlers.on_before_id.eql(6));
//             try testing.expect(ExtHandlers.on_after_called);
//             try testing.expect(ExtHandlers.on_after_id.eql(6));
//             try testing.expect(ExtHandlers.on_fallback_called);
//             try testing.expect(ExtHandlers.on_fallback_id.eql(6));
//         }

//     }

// }

