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

var gpa = std.heap.GeneralPurposeAllocator(.{}){};


// Test handler registration.

fn fn0(alloc: Allocator) anyerror!DispatchResult {
    return .{
        .result = try std.json.stringifyAlloc(alloc, "Hello", .{}),
    };
}

fn fn0_with_result(alloc: Allocator) anyerror!DispatchResult {
    return DispatchResult.withResult(try std.json.stringifyAlloc(alloc, "Hello", .{}));
}

fn fn0_with_result_lit(alloc: Allocator) anyerror!DispatchResult {
    _=alloc;
    return DispatchResult.withResultLit("\"Hello\"");
}

fn fn0_with_err(_: Allocator) anyerror!DispatchResult {
    return DispatchResult.withErr(ErrorCode.InternalError, "Hello error");
}



fn fun0(alloc: Allocator) anyerror![]const u8 {
    return std.json.stringifyAlloc(alloc, "Hello", .{});
}

fn fun1(alloc: Allocator, p1: Value) anyerror![]const u8 {
    const n1 = p1.string;
    const str = try allocPrint(alloc, "Hello {s}", .{n1});
    defer alloc.free(str);
    return std.json.stringifyAlloc(alloc, str, .{});
}

fn fun2(alloc: Allocator, p1: Value, p2: Value) anyerror![]const u8 {
    const n1 = p1.integer;
    const n2 = p2.integer;
    return std.json.stringifyAlloc(alloc, n1 - n2, .{});
}

fn fun2a(alloc: Allocator, p1: Value, p2: Value) anyerror![]const u8 {
    return std.json.stringifyAlloc(alloc, (p1.integer - p2.integer) * 2, .{});
}

fn fun3(alloc: Allocator, p1: Value, p2: Value, p3: Value) anyerror![]const u8 {
    return std.json.stringifyAlloc(alloc, p1.integer + p2.integer + p3.integer, .{});
}

fn fun9(alloc: Allocator, p1: Value, p2: Value, p3: Value, p4: Value,
        p5: Value, p6: Value, p7: Value, p8: Value, p9: Value) anyerror![]const u8 {
    return std.json.stringifyAlloc(alloc,
                                   p1.integer + p2.integer + p3.integer + p4.integer +
                                   p5.integer + p6.integer + p7.integer + p8.integer + p9.integer,
                                   .{});
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

const CatInfo = struct {
    cat_name: []const u8,
    weight: f64,
    eye_color: []const u8,
};

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

test "Registry. Dispatching to 0-parameter method" {
    const alloc = gpa.allocator();
    {
        var registry = reg.Registry.init(alloc);
        defer registry.deinit();

        try registry.register("fn0", fn0, .{});
        try registry.register("fn0_with_result", fn0_with_result, .{});
        try registry.register("fn0_with_result_lit", fn0_with_result_lit, .{});
        try testing.expect(registry.has("fn0"));
        try testing.expect(registry.has("fn0_with_result"));
        try testing.expect(registry.has("fn0_with_result_lit"));
        try testing.expect(!registry.has("non-existing"));

        {
            const res_json = try zigjr.handleRequestJson(alloc,
                \\{"jsonrpc": "2.0", "method": "fn0", "id": 1}
            , &registry) orelse "";
            defer alloc.free(res_json);
            std.debug.print("response: {s}\n", .{res_json});
        }
        {
            const res_json = try zigjr.handleRequestJson(alloc,
                \\{"jsonrpc": "2.0", "method": "fn0_with_result", "id": 2}
            , &registry) orelse "";
            defer alloc.free(res_json);
            std.debug.print("response: {s}\n", .{res_json});
        }
        {
            const res_json = try zigjr.handleRequestJson(alloc,
                \\{"jsonrpc": "2.0", "method": "fn0_with_result_lit", "id": 3}
            , &registry) orelse "";
            defer alloc.free(res_json);
            std.debug.print("response: {s}\n", .{res_json});
        }
        
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Registry. Dispatching to 0-parameter method, with error" {
    const alloc = gpa.allocator();
    {
        var registry = reg.Registry.init(alloc);
        defer registry.deinit();

        try registry.register("fn0", fn0, .{});
        try registry.register("fn0_with_result", fn0_with_result, .{});
        try registry.register("fn0_with_result_lit", fn0_with_result_lit, .{});
        try registry.register("fn0_with_err", fn0_with_err, .{});

        {
            const res_json = try zigjr.handleRequestJson(alloc,
                \\{"jsonrpc": "2.0", "method": "fn0_with_err", "id": 1}
            , &registry) orelse "";
            defer alloc.free(res_json);
            std.debug.print("response: {s}\n", .{res_json});
        }
        
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}



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

//         var result = zigjr.parseRequest(alloc,
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

//         var result = zigjr.parseRequest(alloc,
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

//         var result = zigjr.parseRequest(alloc,
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

//         var result = zigjr.parseRequest(alloc,
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

//         var result = zigjr.parseRequest(alloc,
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

//         var result = zigjr.parseRequest(alloc,
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

//         var result = zigjr.parseRequest(alloc,
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
//         var result = zigjr.parseRequest(alloc, req_json);
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

//         var result = zigjr.parseRequest(alloc,
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

//         var result = zigjr.parseRequest(alloc,
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

//         var result = zigjr.parseRequest(alloc,
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

//         var result = zigjr.parseRequest(alloc,
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

//             var result = zigjr.parseRequest(alloc, req_json);
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


