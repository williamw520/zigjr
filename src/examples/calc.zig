// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William W. Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.hash_map.StringHashMap;

const zigjr = @import("zigjr");


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    {
        var stash = Stash.init(alloc);
        defer stash.deinit();

        var registry = zigjr.RpcRegistry.init(alloc);
        defer registry.deinit();

        try registry.register("add", null, Handlers.add);   // register functions in a struct scope.
        try registry.register("subtract", null, Handlers.subtract);
        try registry.register("multiply", null, Handlers.multiply);
        try registry.register("divide", null, Handlers.divide);
        try registry.register("pow", null, raiseToPower);   // register function from any scope.
        try registry.register("logNum", null, logNum);      // function with no result.
        try registry.register("inc", &g_sum, increase);     // attach a context to the function.
        try registry.register("dec", &g_sum, decrease);     // attach the same context to another function.
        try registry.register("load", &stash, Stash.load);  // handler on a struct object.
        try registry.register("save", &stash, Stash.save);  // handler on a struct object.

        const request = try std.io.getStdIn().reader().readAllAlloc(alloc, 64*1024);
        if (request.len > 0) {
            defer alloc.free(request);
            std.debug.print("Request:  {s}\n", .{request});

            if (try zigjr.handleRequestToJson(alloc, request, registry)) |response| {
                defer alloc.free(response);
                std.debug.print("Response: {s}\n", .{response});
            } else {
                std.debug.print("No response\n", .{});
            }
        } else {
            usage();
        }
    }

    if (gpa.detectLeaks()) {
        std.debug.print("Memory leak detected!\n", .{});
    }    
}

const Handlers = struct {
    fn add(a: i64, b: i64) i64      { return a + b; }
    fn subtract(a: i64, b: i64) i64 { return a - b; }
    fn multiply(a: i64, b: i64) i64 { return a * b; }

    // function that can return errors.
    fn divide(a: i64, b: i64) error{DivideByZero, HeyCantDivide99}!i64 {
        if (b == 0)
            return error.DivideByZero;      // catch a panic and turn it into an error.
        if (a == 99)
            return error.HeyCantDivide99;
        return @divTrunc(a, b);
    }
};


fn raiseToPower(a: f64, b: i64) f64 {
    return std.math.pow(f64, a, @floatFromInt(b));
}

fn logNum(a: i64) void {
    std.debug.print("logNum: {}\n", .{a});
}


var g_sum: i64 = 10;    // sum starts at 10.  The sum variable is passed in as context to functions.

fn increase(ctx_sum: *i64, a: i64) i64 {
    ctx_sum.* += a;
    return ctx_sum.*;
}

fn decrease(ctx_sum: *i64, a: i64) i64 {
    ctx_sum.* -= a;
    return ctx_sum.*;
}


const Stash = struct {
    alloc:  Allocator,
    map:    StringHashMap(f64),

    fn init(alloc: Allocator) @This() {
        return .{
            .alloc = alloc,
            .map = StringHashMap(f64).init(alloc),
        };
    }

    fn deinit(self: *@This()) void {
        var iter = self.map.keyIterator();
        while (iter.next()) |key| self.alloc.free(key.*);
        self.map.deinit();
    }

    fn load(self: *@This(), key: []const u8) ?f64 {
        return self.map.get(key);
    }

    fn save(self: *@This(), key: []const u8, amount: f64) !bool {
        const existed = self.map.contains(key);
        try self.map.put(try self.alloc.dupe(u8, key), amount);
        return existed;
    }
};


fn usage() void {
    std.debug.print(
        \\Usage:  example_program
        \\Usage:  example_program < message.json
        \\
        \\The program reads from stdin.
        , .{});
}



