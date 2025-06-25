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

        try registry.add("add", Basic.add);             // register functions in a struct scope.
        try registry.add("subtract", Basic.subtract);
        try registry.add("multiply", Basic.multiply);
        try registry.add("divide", Basic.divide);
        try registry.add("pow", raiseToPower);          // register function from any scope.
        try registry.add("logNum", logNum);             // function with no result.
        try registry.addCtx("inc", &g_sum, increase);   // attach a context to the function.
        try registry.addCtx("dec", &g_sum, decrease);   // attach the same context to another function.
        try registry.addCtx("load", &stash,Stash.load); // handler on a struct object context.
        try registry.addCtx("save", &stash,Stash.save); // handler on a struct object context.
        try registry.add("weigh-cat", weighCat);        // function with a struct parameter.
        try registry.add("make-cat", makeCat);          // function returns a struct parameter.
        try registry.add("clone-cat", cloneCat);        // function returns an array.
        try registry.add("desc-cat", descCat);          // function returns a tuple.
        try registry.add("add-weight", addWeight);

        const dispatcher = zigjr.RequestDispatcher.implBy(&registry);
        var pipeline = zigjr.RequestPipeline.init(alloc, dispatcher, null);
        defer pipeline.deinit();

        const request = try std.io.getStdIn().reader().readAllAlloc(alloc, 64*1024);
        if (request.len > 0) {
            defer alloc.free(request);
            std.debug.print("Request:  {s}\n", .{request});

            if (try pipeline.runRequestToJson(request)) |response| {
                defer alloc.free(response);
                std.debug.print("Response: {s}\n", .{response});
            } else {
                std.debug.print("No response\n", .{});
            }
        } else {
            usage();
        }
    }

    if (gpa.detectLeaks()) { std.debug.print("Memory leak detected!\n", .{}); }    
}


const Basic = struct {
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
        self.map.deinit();
    }

    fn load(self: *@This(), key: []const u8) ?f64 {
        return self.map.get(key);
    }

    fn save(self: *@This(), key: []const u8, amount: f64) !bool {
        const existed = self.map.contains(key);
        try self.map.put(key, amount);
        return existed;
    }
};


const CatInfo = struct {
    cat_name: []const u8,
    weight: f64,
    eye_color: []const u8,
};

fn weighCat(cat: CatInfo) []const u8 {
    if (std.mem.eql(u8, cat.cat_name, "Garfield")) return "Fat Cat!";
    if (std.mem.eql(u8, cat.cat_name, "Odin")) return "Not a cat!";
    if (0 < cat.weight and cat.weight <= 2.0) return "Tiny cat";
    if (2.0 < cat.weight and cat.weight <= 10.0) return "Normal weight";
    if (10.0 < cat.weight ) return "Heavy cat";
    return "Something wrong";
}

fn makeCat(name: []const u8, eye_color: []const u8) CatInfo {
    const seed: u64 = @truncate(name.len);
    var prng = std.Random.DefaultPrng.init(seed);
    return .{
        .cat_name = name,
        .weight = @floatFromInt(prng.random().uintAtMost(u32, 20)),
        .eye_color = eye_color,
    };
}

fn cloneCat(alloc: Allocator, cat: CatInfo) ![2]CatInfo {
    return .{
        cat,
        CatInfo {
            .cat_name = try std.fmt.allocPrint(alloc, "Clone of {s}", .{cat.cat_name}),
            .weight = cat.weight * 2,
            .eye_color = cat.eye_color,
        },
    };
}

fn descCat(cat: CatInfo) struct { []const u8, f64, f64, []const u8 } {
    return .{
        cat.cat_name,
        cat.weight,
        cat.weight * 2,
        cat.eye_color,
    };
}

fn addWeight(weight: f64, cat: CatInfo) CatInfo {
    var cat2 = cat;
    cat2.weight += weight;
    return cat2;
}


fn usage() void {
    std.debug.print(
        \\Usage:  calc
        \\Usage:  calc < message.json
        \\
        \\The program reads from stdin.
        , .{});
}



