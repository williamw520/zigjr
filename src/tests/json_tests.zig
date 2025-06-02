const std = @import("std");
const Type = std.builtin.Type;
const testing = std.testing;
const allocPrint = std.fmt.allocPrint;
const Allocator = std.mem.Allocator;
const StringHashMap = std.hash_map.StringHashMap;
const ArrayList = std.ArrayList;
const nanoTimestamp = std.time.nanoTimestamp;
const Value = std.json.Value;
const Array = std.json.Array;
const ObjectMap = std.json.ObjectMap;

const zigjr = @import("../zigjr.zig");
const jsonutil = @import("../jsonrpc/jsonutil.zig");
const JrErrors = zigjr.JrErrors;



var gpa = std.heap.GeneralPurposeAllocator(.{}){};


test "Test simple JSON value conversion." {
    const alloc = gpa.allocator();
    {
        _=alloc;
        try testing.expectEqual(jsonutil.ValueAs(i64).from(.{ .integer = 10 }), 10);
        try testing.expectEqual(jsonutil.ValueAs(i128).from(.{ .integer = 10 }), 10);

        try testing.expectEqual(jsonutil.ValueAs(bool).from(.{ .bool = true }), true);
        try testing.expectEqual(jsonutil.ValueAs(bool).from(.{ .bool = false }), false);
        try testing.expectEqual(jsonutil.ValueAs(bool).from(.{ .integer = 0 }), false);
        try testing.expectEqual(jsonutil.ValueAs(bool).from(.{ .integer = 1 }), true);
        try testing.expectEqual(jsonutil.ValueAs(bool).from(.{ .integer = 2 }), true);
        try testing.expectEqual(jsonutil.ValueAs(bool).from(.{ .integer = -2 }), true);
        try testing.expectEqual(jsonutil.ValueAs(bool).from(.{ .float = 0 }), false);
        try testing.expectEqual(jsonutil.ValueAs(bool).from(.{ .float = 1 }), true);
        try testing.expectEqual(jsonutil.ValueAs(bool).from(.{ .float = -1 }), true);
        try testing.expectEqual(jsonutil.ValueAs(bool).from(.{ .float = -1.2 }), true);

        try testing.expectEqual(jsonutil.ValueAs(f64).from(.{ .float = 1.2 }), 1.2);
        try testing.expectEqual(jsonutil.ValueAs(f64).from(.{ .float = -1.2 }), -1.2);
        try testing.expectEqual(jsonutil.ValueAs(f128).from(.{ .float = 10 }), 10);
        try testing.expectEqual(jsonutil.ValueAs(f64).from(.{ .integer = 12 }), 12);

        try testing.expectEqualSlices(u8, try jsonutil.ValueAs([]const u8).from(.{ .string = "hello" }), "hello");
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Test simple JSON value conversion on invalid JSON values." {
    const alloc = gpa.allocator();
    {
        _=alloc;
        try testing.expectEqual(jsonutil.ValueAs(i64).from(.{ .float = 0 }), JrErrors.InvalidJsonValueType);
        try testing.expectEqual(jsonutil.ValueAs(i128).from(.{ .bool = true }), JrErrors.InvalidJsonValueType);
        try testing.expectEqual(jsonutil.ValueAs(i64).from(.{ .string = "abc" }), error.InvalidCharacter);

        try testing.expectEqual(jsonutil.ValueAs(f128).from(.{ .bool = true }), JrErrors.InvalidJsonValueType);
        try testing.expectEqual(jsonutil.ValueAs(f64).from(.{ .string = "abc" }), error.InvalidCharacter);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Test JSON value conversion with alloc." {
    const alloc = gpa.allocator();
    {
        const x = try jsonutil.ValueAs([]const u8).fromAlloc(.{ .string = "hello" }, .{ .alloc = alloc });
        try testing.expectEqualSlices(u8, x, "hello");

        try testing.expectEqual(jsonutil.ValueAs(i64).fromAlloc(.{ .integer = 10 }, .{ .alloc = alloc }), 10);
        
        alloc.free(x);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}


fn foo(a: i64, b: bool) void { std.debug.print("foo: a={}, b={}\n", .{a, b}); }
fn bar(a: f64) void { std.debug.print("bar: a={}\n", .{a}); }
fn baz(a: []const u8, b: i64, c: bool) void { std.debug.print("baz: a={s}, b={}, c={}\n", .{a, b, c}); }

test "Test calling function with with JSON Values." {
    const alloc = gpa.allocator();
    {
        const param_tt = jsonutil.ParamTupleType(foo);
        var args = Array.init(alloc);
        defer args.deinit();
        try args.append(.{ .integer = 1 });
        try args.append(.{ .bool = true });
        const param_tuple = try jsonutil.valuesToTuple(param_tt, args);
        @call(.auto, foo, param_tuple);
    }
    {
        const param_tt = jsonutil.ParamTupleType(bar);
        var args = Array.init(alloc);
        defer args.deinit();
        try args.append(.{ .float = 1.11 });
        const param_tuple = try jsonutil.valuesToTuple(param_tt, args);
        @call(.auto, bar, param_tuple);
    }
    {
        const param_tt = jsonutil.ParamTupleType(baz);
        var args = Array.init(alloc);
        defer args.deinit();
        try args.append(.{ .string = "hello" });
        try args.append(.{ .integer = 4 });
        try args.append(.{ .bool = true });
        const param_tuple = try jsonutil.valuesToTuple(param_tt, args);
        @call(.auto, baz, param_tuple);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

fn foo_c1(a: i64, b: bool) []const u8 {
    std.debug.print("foo_c1: a={}, b={}\n", .{a, b});
    return "return for foo_c1";
}
fn bar_c1(a: f64) []const u8 {
    std.debug.print("bar_c1: a={}\n", .{a});
    return "return for bar_c1";
}
fn foo_c2(_: Allocator, a: i64, b: bool) []const u8 {
    std.debug.print("foo_c2: a={}, b={}\n", .{a, b});
    return "return for foo_c2";
}
fn bar_c2(_: Allocator, a: f64) []const u8 {
    std.debug.print("bar_c2: a={}\n", .{a});
    return "return for bar_c2";
}
const FooObj = struct {
    foo_field: i64 = 1,
    
    fn foo_struct(a: i64, b: bool) [] const u8 {
        std.debug.print("foo_struct: a={}, b={}\n", .{a, b});
        return "return for foo_struct";
    }
    fn foo_obj(self: *@This(), a: i64, b: bool) [] const u8 {
        std.debug.print("foo_obj: a={}, b={}, foo_field={}\n", .{a, b, self.foo_field});
        self.foo_field += 1;
        return "return for foo_obj";
    }
};

test "Using Callable" {
    const alloc = gpa.allocator();
    {
        // _=alloc;
        var handlers = StringHashMap(jsonutil.Callable).init(alloc);
        defer handlers.deinit();

        const fc1 = jsonutil.makeCallable(foo_c2);
        const bc1 = jsonutil.makeCallable(bar_c2);
        // const fc1 = jsonutil.makeCallable(foo_c1);
        // const bc1 = jsonutil.makeCallable(bar_c1);
        // const fos1 = jsonutil.makeCallable(FooObj.foo_struct);
        // var fobj1: FooObj = .{ .foo_field = 11 };
        // const fo1 = jsonutil.makeCallable(&fobj1.foo_obj);

        try handlers.put("foo", fc1);
        try handlers.put("bar", bc1);
        // try handlers.put("foo_struct", fos1);
        // try handlers.put("foo_obj", fo1);

        var args = Array.init(alloc);
        defer args.deinit();
        try args.append(.{ .integer = 1 });
        try args.append(.{ .bool = true });
        const dresult1 = try fc1.invoke(alloc, .{ .array = args });
        std.debug.print("result1={s}\n", .{dresult1.result});
        switch (dresult1) {
            .result => alloc.free(dresult1.result),
            else => {},
        }

        if (handlers.get("foo"))|c| {
            const dresult = try c.invoke(alloc, .{ .array = args });
            std.debug.print("result2={s}\n", .{dresult.result});
            switch (dresult) {
                .result => alloc.free(dresult.result),
                else => {},
            }
        }
        if (handlers.get("bar"))|c| {
            var bar_args = Array.init(alloc);
            defer bar_args.deinit();
            try bar_args.append(.{ .float = 1.11 });
            const dresult = try c.invoke(alloc, .{ .array = bar_args });
            std.debug.print("result3={s}\n", .{dresult.result});
            switch (dresult) {
                .result => alloc.free(dresult.result),
                else => {},
            }
        }

        if (handlers.get("foo_struct"))|c| {
            const dresult = try c.invoke(alloc, .{ .array = args });
            std.debug.print("result4={s}\n", .{dresult.result});
            switch (dresult) {
                .result => alloc.free(dresult.result),
                else => {},
            }
        }
            
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}



