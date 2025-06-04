const std = @import("std");
const testing = std.testing;
const allocPrint = std.fmt.allocPrint;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const nanoTimestamp = std.time.nanoTimestamp;
const Value = std.json.Value;
const Array = std.json.Array;
const ObjectMap = std.json.ObjectMap;

const zigjr = @import("../zigjr.zig");
const RpcRequestMessage = zigjr.RpcRequestMessage;
const RpcRequest = zigjr.RpcRequest;
const ErrorCode = zigjr.ErrorCode;
const JrErrors = zigjr.JrErrors;
const DispatchResult = zigjr.DispatchResult;
const DispatchErrors = zigjr.DispatchErrors;

const reg = @import("../jsonrpc/registry.zig");
const rpc_reg = @import("../jsonrpc/rpc_registry.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};


// Test handler registration.

// TODO: add fn taking in struct,
// add fn taking Value, Array, ObjectMap.

fn fn0() void {
    std.debug.print("fn0() called\n", .{});
}

fn fn0_with_err() !void {
    std.debug.print("fn0_with_err() called\n", .{});
}

fn fn0_return_value() []const u8 {
    std.debug.print("fn0_return_value() called\n", .{});
    return "Hello";
}

fn fn0_return_value_with_err() ![]const u8 {
    std.debug.print("fn0_return_value_with_err() called\n", .{});
    return "Hello";
}


fn fn1(a: i64) void {
    std.debug.print("fn1() called, a:{}\n", .{a});
}

fn fn1_with_err(a: i64) !void {
    std.debug.print("fn1_with_err() called, a:{}\n", .{a});
}

fn fn1_return_value(a: i64) []const u8 {
    std.debug.print("fn1_return_value() called, a:{}\n", .{a});
    return "Hello";
}

fn fn1_return_value_with_err(a: i64) ![]const u8 {
    std.debug.print("fn1_return_value_with_err() called, a:{}\n", .{a});
    return "Hello";
}


fn fn2(a: i64, b: bool) void {
    std.debug.print("fn2() called, a:{}, b:{}\n", .{a, b});
}

fn fn2_with_err(a: i64, b: bool) !void {
    std.debug.print("fn2_with_err() called, a:{}, b:{}\n", .{a, b});
}

fn fn2_return_value(a: i64, b: bool) i64 {
    std.debug.print("fn2_return_value() called, a:{}, b:{}\n", .{a, b});
    return if (b) a * 1 else a * 2;
}

fn fn2_return_value_with_err(a: i64, b: bool) i64 {
    std.debug.print("fn2_return_value_with_err() called, a:{}, b:{}\n", .{a, b});
    return if (b) a * 1 else a * 2;
}


const Ctx = struct {
    count: i64 = 0,
    alloc: Allocator,

    // All methods must have self as pointer as the context is passed in as a pointer.
    fn get(self: *@This()) i64 {
        std.debug.print("ctx.get() called, count:{}\n", .{self.count});
        return self.count;
    }

    fn fn0(self: *@This()) void {
        std.debug.print("ctx.fn0() called, count:{}\n", .{self.count});
    }

    fn fn1(self: *@This(), a: i64) void {
        self.count += a;
        std.debug.print("ctx.fn1() called, count:{}\n", .{self.count});
    }

    fn fn_cat_value_parse(self: *@This(), obj: std.json.ObjectMap) !CatInfo {
        const parsed = try std.json.parseFromValue(CatInfo, self.alloc, obj, .{});
        return .{
            .cat_name = parsed.value.cat_name,
            .weight = parsed.value.weight,
            .eye_color = parsed.value.eye_color,
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

fn fn_cat_objmap(obj: std.json.ObjectMap) CatInfo {
    return .{
        .cat_name = obj.get("cat_name").?.string,
        .weight = obj.get("weight").?.float,
        .eye_color = obj.get("eye_color").?.string,
    };
}

fn fn_cat_add_weight(cat: CatInfo) CatInfo {
    return .{
        .cat_name = cat.cat_name,
        .weight = cat.weight + 1,
        .eye_color = cat.eye_color,
    };
}



fn funArray(alloc: Allocator, array: Array) anyerror![]const u8 {
    const str = try allocPrint(alloc, "Hello {}", .{array});
    defer alloc.free(str);
    return std.json.stringifyAlloc(alloc, str, .{});
}

fn addArray(alloc: Allocator, array: Array) anyerror![]const u8 {
    var sum: isize = 0;
    for (array.items) |value| {
        sum += value.integer;
    }
    return std.json.stringifyAlloc(alloc, sum, .{});
}

const MyErrors = error {
    MissingName,
};

fn funObj(alloc: Allocator, map: ObjectMap) anyerror![]const u8 {
    if (map.get("name")) |name| {
        const str = try allocPrint(alloc, "Hello {s}", .{name.string});
        defer alloc.free(str);
        return std.json.stringifyAlloc(alloc, str, .{});
    } else {
        return MyErrors.MissingName;
    }
}

fn funCat(alloc: Allocator, obj: Value) anyerror![]const u8 {
    const parsed = try std.json.parseFromValue(CatInfo, alloc, obj, .{});
    defer parsed.deinit();
    const cat_info = parsed.value;
    // std.debug.print("cat_info: {any}\n", .{cat_info});
    return std.json.stringifyAlloc(alloc, cat_info, .{});
}

    
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


test "rpc_registry fn0" {
    const alloc = gpa.allocator();
    {
        var registry = rpc_reg.RpcRegistry.init(alloc);
        defer registry.deinit(alloc);

        try registry.register("fn0", fn0, .{});
        try registry.register("fn0_with_err", fn0_with_err, .{});
        try registry.register("fn0_return_value", fn0_return_value, .{});
        try registry.register("fn0_return_value_with_err", fn0_return_value_with_err, .{});

        {
            const res_json = try zigjr.handleRequestToJson(alloc,
                \\{"jsonrpc": "2.0", "method": "fn0", "id": 1}
            , &registry) orelse "";
            defer alloc.free(res_json);
            // std.debug.print("response: {s}\n", .{res_json});

            try testing.expect(res_json.len == 0);
        }

        {
            const res_json = try zigjr.handleRequestToJson(alloc,
                \\{"jsonrpc": "2.0", "method": "fn0_with_err", "id": 1}
            , &registry) orelse "";
            defer alloc.free(res_json);
            // std.debug.print("response: {s}\n", .{res_json});

            try testing.expect(res_json.len == 0);
        }
        
        {
            const res_json = try zigjr.handleRequestToJson(alloc,
                \\{"jsonrpc": "2.0", "method": "fn0_return_value", "id": 1}
            , &registry) orelse "";
            defer alloc.free(res_json);
            // std.debug.print("response: {s}\n", .{res_json});

            var res_result = try zigjr.parseRpcResponse(alloc, res_json);
            defer res_result.deinit();
            try testing.expect((try res_result.response()).resultEql("Hello"));
        }
        
        {
            const res_json = try zigjr.handleRequestToJson(alloc,
                \\{"jsonrpc": "2.0", "method": "fn0_return_value_with_err", "id": 1}
            , &registry) orelse "";
            defer alloc.free(res_json);
            // std.debug.print("response: {s}\n", .{res_json});

            var res_result = try zigjr.parseRpcResponse(alloc, res_json);
            defer res_result.deinit();
            try testing.expect((try res_result.response()).resultEql("Hello"));
        }
        
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "rpc_registry fn1" {
    const alloc = gpa.allocator();
    {
        var registry = rpc_reg.RpcRegistry.init(alloc);
        defer registry.deinit(alloc);

        try registry.register("fn1", fn1, .{});
        try registry.register("fn1_with_err", fn1_with_err, .{});
        try registry.register("fn1_return_value", fn1_return_value, .{});
        try registry.register("fn1_return_value_with_err", fn1_return_value_with_err, .{});

        {
            const res_json = try zigjr.handleRequestToJson(alloc,
                \\{"jsonrpc": "2.0", "method": "fn1", "params": [1], "id": 1}
            , &registry) orelse "";
            defer alloc.free(res_json);

            try testing.expect(res_json.len == 0);
            // var res_result = try zigjr.parseRpcResponse(alloc, res_json);
            // defer res_result.deinit();
            // try testing.expect((try res_result.response()).resultEql(0));
        }

        {
            const res_json = try zigjr.handleRequestToJson(alloc,
                \\{"jsonrpc": "2.0", "method": "fn1_with_err", "params": [2], "id": 1}
            , &registry) orelse "";
            defer alloc.free(res_json);

            try testing.expect(res_json.len == 0);
            // var res_result = try zigjr.parseRpcResponse(alloc, res_json);
            // defer res_result.deinit();
            // try testing.expect((try res_result.response()).resultEql(0));
        }
        
        {
            const res_json = try zigjr.handleRequestToJson(alloc,
                \\{"jsonrpc": "2.0", "method": "fn1_return_value", "params": [3], "id": 1}
            , &registry) orelse "";
            defer alloc.free(res_json);

            var res_result = try zigjr.parseRpcResponse(alloc, res_json);
            defer res_result.deinit();
            try testing.expect((try res_result.response()).resultEql("Hello"));
        }
        
        {
            const res_json = try zigjr.handleRequestToJson(alloc,
                \\{"jsonrpc": "2.0", "method": "fn1_return_value_with_err", "params": [4], "id": 1}
            , &registry) orelse "";
            defer alloc.free(res_json);

            var res_result = try zigjr.parseRpcResponse(alloc, res_json);
            defer res_result.deinit();
            try testing.expect((try res_result.response()).resultEql("Hello"));
        }
        
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}


test "rpc_registry fn2" {
    const alloc = gpa.allocator();
    {
        var registry = rpc_reg.RpcRegistry.init(alloc);
        defer registry.deinit(alloc);

        try registry.register("fn2", fn2, .{});
        try registry.register("fn2_with_err", fn2_with_err, .{});
        try registry.register("fn2_return_value", fn2_return_value, .{});
        try registry.register("fn2_return_value_with_err", fn2_return_value_with_err, .{});

        {
            const res_json = try zigjr.handleRequestToJson(alloc,
                \\{"jsonrpc": "2.0", "method": "fn2", "params": [1, true], "id": 1}
            , &registry) orelse "";
            defer alloc.free(res_json);

            try testing.expect(res_json.len == 0);
        }

        {
            const res_json = try zigjr.handleRequestToJson(alloc,
                \\{"jsonrpc": "2.0", "method": "fn2_with_err", "params": [2, false], "id": 1}
            , &registry) orelse "";
            defer alloc.free(res_json);

            try testing.expect(res_json.len == 0);
        }
        
        {
            const res_json = try zigjr.handleRequestToJson(alloc,
                \\{"jsonrpc": "2.0", "method": "fn2_return_value", "params": [3, true], "id": 1}
            , &registry) orelse "";
            defer alloc.free(res_json);

            var res_result = try zigjr.parseRpcResponse(alloc, res_json);
            defer res_result.deinit();
            try testing.expect((try res_result.response()).resultEql(3));
        }
        
        {
            const res_json = try zigjr.handleRequestToJson(alloc,
                \\{"jsonrpc": "2.0", "method": "fn2_return_value_with_err", "params": [4, false], "id": 1}
            , &registry) orelse "";
            defer alloc.free(res_json);

            var res_result = try zigjr.parseRpcResponse(alloc, res_json);
            defer res_result.deinit();
            try testing.expect((try res_result.response()).resultEql(8));
        }
        
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}


test "rpc_registry with context" {
    const alloc = gpa.allocator();
    {
        var registry = rpc_reg.RpcRegistry.init(alloc);
        defer registry.deinit(alloc);

        var ctx = Ctx { .count = 0, .alloc = alloc };

        try registry.registerWithCtx("ctx.get", &ctx, Ctx.get, .{});
        try registry.registerWithCtx("ctx.fn0", &ctx, Ctx.fn0, .{});
        try registry.registerWithCtx("ctx.fn1", &ctx, Ctx.fn1, .{});

        {
            const res_json = try zigjr.handleRequestToJson(alloc,
                \\{"jsonrpc": "2.0", "method": "ctx.get", "id": 1}
            , &registry) orelse "";
            defer alloc.free(res_json);
            // std.debug.print("response: {s}\n", .{res_json});

            var res_result = try zigjr.parseRpcResponse(alloc, res_json);
            defer res_result.deinit();
            try testing.expect((try res_result.response()).resultEql(0));
        }

        {
            const res_json = try zigjr.handleRequestToJson(alloc,
                \\{"jsonrpc": "2.0", "method": "ctx.fn0", "id": 1}
            , &registry) orelse "";
            defer alloc.free(res_json);

            try testing.expect(res_json.len == 0);
        }

        {
            const res_json = try zigjr.handleRequestToJson(alloc,
                \\{"jsonrpc": "2.0", "method": "ctx.fn1", "params": [2], "id": 1}
            , &registry) orelse "";
            defer alloc.free(res_json);

            try testing.expect(res_json.len == 0);
        }

        {
            const res_json = try zigjr.handleRequestToJson(alloc,
                \\{"jsonrpc": "2.0", "method": "ctx.get", "id": 1}
            , &registry) orelse "";
            defer alloc.free(res_json);

            var res_result = try zigjr.parseRpcResponse(alloc, res_json);
            defer res_result.deinit();
            try testing.expect((try res_result.response()).resultEql(2));
        }

    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}


test "rpc_registry with return struct value" {
    const alloc = gpa.allocator();
    {
        var registry = rpc_reg.RpcRegistry.init(alloc);
        defer registry.deinit(alloc);

        try registry.register("fn_cat", fn_cat, .{});

        {
            const res_json = try zigjr.handleRequestToJson(alloc,
                \\{"jsonrpc": "2.0", "method": "fn_cat", "params": ["cat1", 9, "blue"], "id": 1}
            , &registry) orelse "";
            defer alloc.free(res_json);
            // std.debug.print("response: {s}\n", .{res_json});

            var res_result = try zigjr.parseRpcResponse(alloc, res_json);
            defer res_result.deinit();
            // std.debug.print("result: {any}\n", .{(try res_result.response()).result});
            const parsed_cat = try std.json.parseFromValue(CatInfo, alloc, (try res_result.response()).result, .{});
            defer parsed_cat.deinit();
            // std.debug.print("cat: {any}\n", .{parsed_cat.value});
            try testing.expectEqualSlices(u8, parsed_cat.value.cat_name, "cat1");
            try testing.expectEqualSlices(u8, parsed_cat.value.eye_color, "blue");
            try testing.expectEqual(parsed_cat.value.weight, 9);
        }

    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}


test "rpc_registry passing in an ObjectMap as a parameter" {
    const alloc = gpa.allocator();
    {
        var registry = rpc_reg.RpcRegistry.init(alloc);
        defer registry.deinit(alloc);

        try registry.register("fn_cat_objmap", fn_cat_objmap, .{});

        {
            const cat2 = CatInfo { .cat_name = "cat2", .weight = 5.0, .eye_color = "brown" };
            const req_json = try zigjr.messages.toRequestJson(alloc, "fn_cat_objmap", cat2, .{ .num = 1 });
            defer alloc.free(req_json);
            // std.debug.print("request: {s}\n", .{req_json});

            const res_json = try zigjr.handleRequestToJson(alloc, req_json , &registry) orelse "";
            defer alloc.free(res_json);
            // std.debug.print("response: {s}\n", .{res_json});

            var res_result = try zigjr.parseRpcResponse(alloc, res_json);
            defer res_result.deinit();
            // std.debug.print("result: {any}\n", .{(try res_result.response()).result});
            const parsed_cat = try std.json.parseFromValue(CatInfo, alloc, (try res_result.response()).result, .{});
            defer parsed_cat.deinit();
            // std.debug.print("cat: {any}\n", .{parsed_cat.value});
            try testing.expectEqualSlices(u8, parsed_cat.value.cat_name, "cat2");
            try testing.expectEqualSlices(u8, parsed_cat.value.eye_color, "brown");
            try testing.expectEqual(parsed_cat.value.weight, 5.0);
        }

    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}


// test "rpc_registry passing in an ObjectMap Value as a parameter, with a context, parsing the Value to a struct" {
//     const alloc = gpa.allocator();
//     {
//         var registry = rpc_reg.RpcRegistry.init(alloc);
//         defer registry.deinit(alloc);

//         var ctx = Ctx { .count = 0, .alloc = alloc };

//         try registry.registerWithCtx("ctx.fn_cat_value_parse", &ctx, Ctx.fn_cat_value_parse, .{});

//         {
//             const cat3 = CatInfo { .cat_name = "cat3", .weight = 5.0, .eye_color = "brown" };
//             const req_json = try zigjr.messages.toRequestJson(alloc, "ctx.fn_cat_objmap_parse", cat3, .{ .num = 1 });
//             defer alloc.free(req_json);
//             std.debug.print("request: {s}\n", .{req_json});

//             const res_json = try zigjr.handleRequestToJson(alloc, req_json , &registry) orelse "";
//             defer alloc.free(res_json);
//             std.debug.print("response: {s}\n", .{res_json});

//             // var res_result = try zigjr.parseRpcResponse(alloc, res_json);
//             // defer res_result.deinit();
//             // // std.debug.print("result: {any}\n", .{(try res_result.response()).result});
//             // const parsed_cat = try std.json.parseFromValue(CatInfo, alloc, (try res_result.response()).result, .{});
//             // defer parsed_cat.deinit();
//             // // std.debug.print("cat1: {any}\n", .{parsed_cat.value});
//             // try testing.expectEqualSlices(u8, parsed_cat.value.cat_name, "cat1");
//             // try testing.expectEqualSlices(u8, parsed_cat.value.eye_color, "blue");
//             // try testing.expectEqual(parsed_cat.value.weight, 9);
//         }

//     }
//     if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
// }


// test "rpc_registry passing in a struct as a parameter" {
//     const alloc = gpa.allocator();
//     {
//         var registry = rpc_reg.RpcRegistry.init(alloc);
//         defer registry.deinit(alloc);

//         // try registry.register("fn_cat_add_weight", fn_cat_add_weight, .{});

//         // const cat2 = CatInfo { .cat_name = "cat2", .weight = 5.0, .eye_color = "brown" };

//         // {
//         //     const res_json = try zigjr.handleRequestToJson(alloc,
//         //         \\{"jsonrpc": "2.0", "method": "fn_cat", "params": ["cat1", 9, "blue"], "id": 1}
//         //     , &registry) orelse "";
//         //     defer alloc.free(res_json);
//         //     // std.debug.print("response: {s}\n", .{res_json});

//         //     var res_result = try zigjr.parseRpcResponse(alloc, res_json);
//         //     defer res_result.deinit();
//         //     // std.debug.print("result: {any}\n", .{(try res_result.response()).result});
//         //     const parsed_cat = try std.json.parseFromValue(CatInfo, alloc, (try res_result.response()).result, .{});
//         //     defer parsed_cat.deinit();
//         //     // std.debug.print("cat1: {any}\n", .{parsed_cat.value});
//         //     try testing.expectEqualSlices(u8, parsed_cat.value.cat_name, "cat1");
//         //     try testing.expectEqualSlices(u8, parsed_cat.value.eye_color, "blue");
//         //     try testing.expectEqual(parsed_cat.value.weight, 9);
//         // }

//     }
//     if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
// }




// test "Register handlers" {
//     const alloc = gpa.allocator();
//     {
//         var registry = zigjr.Registry.init(alloc);
//         defer registry.deinit();

//         try registry.register("fun0", fun0, .{});
//         try testing.expect(registry.get("fun0") != null);
//         try registry.register("fun1", fun1, .{});
//         try registry.register("subtract", fun2, .{});
//         try registry.register("sum3", fun3, .{});
//         try registry.register("sum9", fun9, .{});
//         try registry.register("funArray", funArray, .{});
//         try registry.register("funObj", funObj, .{});
//         try registry.register("funCat", funCat, .{ .raw_params = true });

//         // Re-register handler
//         try registry.register("fun2", fun2a, .{});
//         try testing.expect(registry.get("fun2") != null);
//         try testing.expect(registry.get("fun2").?.handler_fn.fn2 != fun2);
//         try testing.expect(registry.get("fun2").?.handler_fn.fn2 == fun2a);
//     }
//     if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
// }

// test "Test validation on registering handler with too many params, expect error" {
//     const alloc = gpa.allocator();
//     {
//         var registry = zigjr.Registry.init(alloc);
//         defer registry.deinit();
//         try testing.expectError(zigjr.RegistrationErrors.HandlerTooManyParams,
//                                 registry.register("fun_too_many_params", fun_too_many_params, .{}));
//     }
//     if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
// }

// test "Test validation on registering handler with the wrong param type, expect error" {
//     const alloc = gpa.allocator();
//     {
//         var registry = zigjr.Registry.init(alloc);
//         defer registry.deinit();
//         try testing.expectError(zigjr.RegistrationErrors.HandlerInvalidParameterType,
//                                 registry.register("fun_wrong_param_type", fun_wrong_param_type, .{}));
//     }
//     if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
// }

// test "Test validation on registering a reserved name prefix 'rpc.', expect error" {
//     const alloc = gpa.allocator();
//     {
//         var registry = zigjr.Registry.init(alloc);
//         defer registry.deinit();
//         try testing.expectError(zigjr.RegistrationErrors.InvalidMethodName,
//                                 registry.register("rpc.abc", fun0, .{}));
//     }
//     if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
// }

// test "Test validation on registering a handler with missing allocator, expect error" {
//     const alloc = gpa.allocator();
//     {
//         var registry = zigjr.Registry.init(alloc);
//         defer registry.deinit();
//         try testing.expectError(zigjr.RegistrationErrors.MissingAllocator,
//                                 registry.register("fun_missing_allocator", fun_missing_allocator, .{}));
//     }
//     if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
// }

// test "Uncomment to test catching registration errors on compile, expect compile error" {
//     const alloc = gpa.allocator();
//     {
//         var registry = zigjr.Registry.init(alloc);
//         defer registry.deinit();
//         // These would cause compile errors, as expected.
//         // try registry.register("fun_wrong_return_type", fun_wrong_return_type, .{});
//         // try registry.register("fun_wrong_param_type2", fun_wrong_param_type2, .{});
//     }
//     if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
// }

// // Test request dispatching

// fn registerFunctions(alloc: Allocator) !zigjr.Registry {
//     var registry = zigjr.Registry.init(alloc);
//     try registry.register("fun0", fun0, .{});
//     try registry.register("fun1", fun1, .{});
//     try registry.register("subtract", fun2, .{});
//     try registry.register("sum3", fun3, .{});
//     try registry.register("sum9", fun9, .{});
//     try registry.register("funArray", funArray, .{});
//     try registry.register("funObj", funObj, .{});
//     try registry.register("funCat", funCat, .{ .raw_params = true });
//     try registry.register("addArray", addArray, .{});

//     // std.debug.print("addArray handler: {any}\n", .{registry.get("addArray")});

//     return registry;
// }

// test "Dispatching to 0-parameter method" {
//     const alloc = gpa.allocator();
//     {
//         var registry = try registerFunctions(alloc);
//         defer registry.deinit();

//         var result = zigjr.parseRpcRequest(alloc,
//             \\{"jsonrpc": "2.0", "method": "fun0", "id": 1}
//         );
//         defer result.deinit();

//         const response = try registry.run(try result.request());
//         defer registry.freeResponse(response);

//         const parsed = try std.json.parseFromSlice(Value, alloc, response, .{});
//         defer parsed.deinit();
//         try testing.expectEqualSlices(u8, parsed.value.object.get("result").?.string, "Hello");
//         try testing.expectEqual(parsed.value.object.get("id").?.integer, 1);

//         // std.debug.print("response: {s}\n", .{response});
//         // std.debug.print("parsed: {any}\n", .{parsed.value.object.get("result").?});
//     }
//     if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
// }

// test "Dispatching to 2-integer parameter method" {
//     const alloc = gpa.allocator();
//     {
//         var registry = try registerFunctions(alloc);
//         defer registry.deinit();

//         var result = zigjr.parseRpcRequest(alloc,
//             \\{"jsonrpc": "2.0", "method": "subtract", "params": [42, 22], "id": 1}
//         );
//         defer result.deinit();

//         const response = try registry.run(try result.request());
//         defer registry.freeResponse(response);

//         const parsed = try std.json.parseFromSlice(Value, alloc, response, .{});
//         defer parsed.deinit();
//         try testing.expectEqual(parsed.value.object.get("result").?.integer, 20);
//         try testing.expectEqual(parsed.value.object.get("id").?.integer, 1);

//         // std.debug.print("response: {s}\n", .{response});
//         // std.debug.print("parsed: {any}\n", .{parsed.value.object.get("result").?});
//     }
//     if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
// }

// test "Dispatching to 1-string parameter method" {
//     const alloc = gpa.allocator();
//     {
//         var registry = try registerFunctions(alloc);
//         defer registry.deinit();

//         var result = zigjr.parseRpcRequest(alloc,
//             \\{"jsonrpc": "2.0", "method": "fun1", "params": ["FUN1"], "id": 1}
//         );
//         defer result.deinit();

//         const response = try registry.run(try result.request());
//         defer registry.freeResponse(response);

//         const parsed = try std.json.parseFromSlice(Value, alloc, response, .{});
//         defer parsed.deinit();
//         try testing.expectEqualSlices(u8, parsed.value.object.get("result").?.string, "Hello FUN1");
//         try testing.expectEqual(parsed.value.object.get("id").?.integer, 1);
//     }
//     if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
// }

// test "Dispatching to 3-integer parameter method" {
//     const alloc = gpa.allocator();
//     {
//         var registry = try registerFunctions(alloc);
//         defer registry.deinit();

//         var result = zigjr.parseRpcRequest(alloc,
//             \\{"jsonrpc": "2.0", "method": "sum3", "params": [1, 2, 3], "id": 1}
//         );
//         defer result.deinit();

//         const response = try registry.run(try result.request());
//         defer registry.freeResponse(response);

//         const parsed = try std.json.parseFromSlice(Value, alloc, response, .{});
//         defer parsed.deinit();
//         try testing.expectEqual(parsed.value.object.get("result").?.integer, 6);
//         try testing.expectEqual(parsed.value.object.get("id").?.integer, 1);
//     }
//     if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
// }

// test "Dispatching to 9-integer parameter method" {
//     const alloc = gpa.allocator();
//     {
//         var registry = try registerFunctions(alloc);
//         defer registry.deinit();

//         var result = zigjr.parseRpcRequest(alloc,
//             \\{"jsonrpc": "2.0", "method": "sum9", "params": [1, 2, 3, 4, 5, 6, 7, 8, 9], "id": 1}
//         );
//         defer result.deinit();

//         const response = try registry.run(try result.request());
//         defer registry.freeResponse(response);

//         const parsed = try std.json.parseFromSlice(Value, alloc, response, .{});
//         defer parsed.deinit();
//         try testing.expectEqual(parsed.value.object.get("result").?.integer, 45);
//         try testing.expectEqual(parsed.value.object.get("id").?.integer, 1);
//     }
//     if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
// }

// test "Dispatching to an array-based parameter method" {
//     const alloc = gpa.allocator();
//     {
//         var registry = try registerFunctions(alloc);
//         defer registry.deinit();

//         var result = zigjr.parseRpcRequest(alloc,
//             \\{"jsonrpc": "2.0", "method": "addArray", "params": [1, 2, 3, 4, 5, 6, 7, 8, 9], "id": 1}
//         );
//         defer result.deinit();

//         const response = try registry.run(try result.request());
//         defer registry.freeResponse(response);

//         const parsed = try std.json.parseFromSlice(Value, alloc, response, .{});
//         defer parsed.deinit();
//         try testing.expectEqual(parsed.value.object.get("result").?.integer, 45);
//         try testing.expectEqual(parsed.value.object.get("id").?.integer, 1);
//     }
//     if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
// }

// test "Dispatching to an object-based parameter method" {
//     const alloc = gpa.allocator();
//     {
//         var registry = try registerFunctions(alloc);
//         defer registry.deinit();

//         var result = zigjr.parseRpcRequest(alloc,
//             \\{"jsonrpc": "2.0", "method": "funObj", "params": {"name": "abc"}, "id": 1}
//         );
//         defer result.deinit();

//         const response = try registry.run(try result.request());
//         defer registry.freeResponse(response);

//         const parsed = try std.json.parseFromSlice(Value, alloc, response, .{});
//         defer parsed.deinit();
//         try testing.expectEqualSlices(u8, parsed.value.object.get("result").?.string, "Hello abc");
//         try testing.expectEqual(parsed.value.object.get("id").?.integer, 1);
//         // std.debug.print("response: {s}\n", .{response});
//         // std.debug.print("parsed: {any}\n", .{parsed.value.object.get("result").?});
//     }
//     if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
// }

// test "Dispatching to an object-based parameter method FunCat" {
//     const alloc = gpa.allocator();
//     {
//         var registry = try registerFunctions(alloc);
//         defer registry.deinit();

//         const cat_info = CatInfo {
//             .cat_name = "foo",
//             .weight = 7.5,
//             .eye_color = "brown",
//         };
//         const cat_json = try std.json.stringifyAlloc(alloc, cat_info, .{});
//         defer alloc.free(cat_json);
//         const req_json = try allocPrint(alloc,
//             \\{{"jsonrpc": "2.0", "method": "funCat", "params": {s}, "id": 1}}
//             , .{cat_json});
//         defer alloc.free(req_json);
//         var result = zigjr.parseRpcRequest(alloc, req_json);
//         defer result.deinit();

//         const response = try registry.run(try result.request());
//         defer registry.freeResponse(response);
//         // std.debug.print("response: {s}\n", .{response});

//         const parsed = try std.json.parseFromSlice(Value, alloc, response, .{});
//         defer parsed.deinit();
//         try testing.expectEqual(parsed.value.object.get("id").?.integer, 1);

//         const res_result = parsed.value.object.get("result").?;
//         const parsed_cat = try std.json.parseFromValue(CatInfo, alloc, res_result, .{});
//         defer parsed_cat.deinit();
//         try testing.expectEqualDeep(cat_info, parsed_cat.value);
//     }
//     if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
// }


// test "Dispatching to an object-based parameter method without the needed value, expect error" {
//     const alloc = gpa.allocator();
//     {
//         var registry = try registerFunctions(alloc);
//         defer registry.deinit();

//         var result = zigjr.parseRpcRequest(alloc,
//             \\{"jsonrpc": "2.0", "method": "funObj", "params": {"no-name": "abc"}, "id": 1}
//         );
//         defer result.deinit();

//         const response = try registry.run(try result.request());
//         defer registry.freeResponse(response);

//         const parsed = try std.json.parseFromSlice(Value, alloc, response, .{});
//         defer parsed.deinit();
//         try testing.expectEqual(parsed.value.object.get("error").?.object.get("code").?.integer, @intFromEnum(ErrorCode.ServerError));
//         try testing.expectEqual(parsed.value.object.get("id").?.integer, 1);
//         // std.debug.print("response: {s}\n", .{response});
//         // std.debug.print("parsed: {any}\n", .{parsed.value.object.get("result").?});
//     }
//     if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
// }

// test "Dispatching to non-existing method, expect error" {
//     const alloc = gpa.allocator();
//     {
//         var registry = try registerFunctions(alloc);
//         defer registry.deinit();

//         var result = zigjr.parseRpcRequest(alloc,
//             \\{"jsonrpc": "2.0", "method": "no-method"}
//         );
//         defer result.deinit();

//         const response = try registry.run(try result.request());
//         defer registry.freeResponse(response);

//         const parsed = try std.json.parseFromSlice(Value, alloc, response, .{});
//         defer parsed.deinit();
//         try testing.expectEqual(parsed.value.object.get("error").?.object.get("code").?.integer, @intFromEnum(ErrorCode.MethodNotFound));
//         try testing.expectEqual(parsed.value.object.get("id").?.null, {});

//         // std.debug.print("response: {s}\n", .{response});
//         // std.debug.print("parsed: {any}\n", .{parsed.value.object.get("id").?});
//     }
//     if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
// }

// test "Dispatching to 0-parameter method with mismatched parameter count, expect error" {
//     const alloc = gpa.allocator();
//     {
//         var registry = try registerFunctions(alloc);
//         defer registry.deinit();

//         var result = zigjr.parseRpcRequest(alloc,
//             \\{"jsonrpc": "2.0", "method": "fun0", "params": [1], "id": 1}
//         );
//         defer result.deinit();

//         const response = try registry.run(try result.request());
//         defer registry.freeResponse(response);

//         const parsed = try std.json.parseFromSlice(Value, alloc, response, .{});
//         defer parsed.deinit();
//         try testing.expectEqual(parsed.value.object.get("error").?.object.get("code").?.integer, @intFromEnum(ErrorCode.InvalidParams));
//         try testing.expectEqual(parsed.value.object.get("id").?.integer, 1);

//         // std.debug.print("response: {s}\n", .{response});
//         // std.debug.print("parsed: {any}\n", .{parsed.value.object.get("id").?});
//     }
//     if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
// }

// test "Dispatching to 0-parameter method with empty parameter array" {
//     const alloc = gpa.allocator();
//     {
//         var registry = try registerFunctions(alloc);
//         defer registry.deinit();

//         var result = zigjr.parseRpcRequest(alloc,
//             \\{"jsonrpc": "2.0", "method": "fun0", "params": [], "id": 1}
//         );
//         defer result.deinit();

//         const response = try registry.run(try result.request());
//         defer registry.freeResponse(response);

//         const parsed = try std.json.parseFromSlice(Value, alloc, response, .{});
//         defer parsed.deinit();
//         try testing.expectEqualSlices(u8, parsed.value.object.get("result").?.string, "Hello");
//         try testing.expectEqual(parsed.value.object.get("id").?.integer, 1);

//         // std.debug.print("response: {s}\n", .{response});
//         // std.debug.print("parsed: {any}\n", .{parsed.value.object.get("id").?});
//     }
//     if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
// }

// test "Dispatching to 1-parameter method with mismatched parameters, expect error" {
//     const alloc = gpa.allocator();
//     {
//         var registry = try registerFunctions(alloc);
//         defer registry.deinit();

//         var buffer = std.ArrayList(u8).init(alloc);
//         defer buffer.deinit();

//         for (0..10)|i| {
//             if (i == 1) continue;
//             buffer.clearRetainingCapacity();
//             for (0..i)|j| {
//                 if (j != 0) try buffer.appendSlice(", ");
//                 try buffer.writer().print("{}", .{j});
//             }
//             const req_json = try allocPrint(alloc,
//                 \\{{"jsonrpc": "2.0", "method": "fun1", "params": [{s}], "id": 1}}
//                 , .{buffer.items});
//             // std.debug.print("req_json: {s}\n", .{req_json});
//             defer alloc.free(req_json);

//             var result = zigjr.parseRpcRequest(alloc, req_json);
//             defer result.deinit();

//             const response = try registry.run(try result.request());
//             defer registry.freeResponse(response);
//             // std.debug.print("response: {s}\n", .{response});

//             const parsed = try std.json.parseFromSlice(Value, alloc, response, .{});
//             defer parsed.deinit();
//             try testing.expectEqual(parsed.value.object.get("error").?.object.get("code").?.integer, @intFromEnum(ErrorCode.InvalidParams));
//         }            
//     }
//     if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
// }


