// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William W. Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const Allocator = std.mem.Allocator;
const ParseOptions = std.json.ParseOptions;
const StringHashMap = std.hash_map.StringHashMap;

const zigjr = @import("zigjr");


pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    var args = try CmdArgs.init(alloc);
    defer args.deinit();
    args.parse() catch { usage(); return; };
    try runExample(alloc, args);
}

fn runExample(alloc: Allocator, args: CmdArgs) !void {
    var stash = Stash.init(alloc);
    defer stash.deinit();

    var rpc_dispatcher = try zigjr.RpcDispatcher.init(alloc);
    defer rpc_dispatcher.deinit();

    try rpc_dispatcher.add("add", Basic.add);                   // register functions in a struct scope.
    try rpc_dispatcher.add("subtract", Basic.subtract);
    try rpc_dispatcher.add("multiply", Basic.multiply);
    try rpc_dispatcher.add("divide", Basic.divide);
    try rpc_dispatcher.add("pow", raiseToPower);                // register function from any scope.
    try rpc_dispatcher.add("logNum", logNum);                   // function with no result.
    try rpc_dispatcher.addWithCtx("inc", &g_sum, increase);     // attach a context to the function.
    try rpc_dispatcher.addWithCtx("dec", &g_sum, decrease);     // attach the same context to another function.
    try rpc_dispatcher.addWithCtx("load", &stash, Stash.load);  // handler on a struct object context.
    try rpc_dispatcher.addWithCtx("save", &stash, Stash.save);  // handler on a struct object context.
    try rpc_dispatcher.add("weigh-cat", weighCat);              // function with a struct parameter.
    try rpc_dispatcher.add("make-cat", makeCat);                // function returns a struct parameter.
    try rpc_dispatcher.add("clone-cat", cloneCat);              // function returns an array.
    try rpc_dispatcher.add("desc-cat", descCat);                // function returns a tuple.
    try rpc_dispatcher.add("add-weight", addWeight);

    var stdin_buffer: [1024]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
    const stdin = &stdin_reader.interface;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var my_logger = MyLogger{};
    if (args.by_delimiter) {
        // Handle streaming of requests separated by a delimiter (LF).
        try zigjr.stream.runByDelimiter(alloc, stdin, stdout, &rpc_dispatcher,
                                        .{ .logger = zigjr.Logger.implBy(&my_logger) });
    } else if (args.by_length) {
        // Handle streaming of requests separated by the Content-Length header.
        try zigjr.stream.runByContentLength(alloc, stdin, stdout, &rpc_dispatcher, .{});
    } else {
        usage();
    }
    try stdout.flush();
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


const MyLogger = struct {
    count: usize = 0,
    
    pub fn start(_: @This(), _: []const u8) void {}
    pub fn log(self: *@This(), source:[] const u8, operation: []const u8, message: []const u8) void {
        self.count += 1;
        std.debug.print("LOG {}: {s} - {s} - {s}\n", .{self.count, source, operation, message});
    }
    pub fn stop(_: @This(), _: []const u8) void {}
    
};


fn usage() void {
    std.debug.print(
        \\Usage:  calc_stream --by-delimiter < messages_by_lf.json
        \\Usage:  calc_stream --by-length < messages_by_length.json
        \\
        \\The program reads from stdin.
        , .{});
}

// Poorman's quick and dirty command line argument parsing.
const CmdArgs = struct {
    const Self = @This();

    arg_itr:        std.process.ArgIterator,
    by_delimiter:   bool = false,
    by_length:      bool = false,

    fn init(allocator: Allocator) !CmdArgs {
        var args = CmdArgs {
            .arg_itr = try std.process.argsWithAllocator(allocator),
        };
        _ = args.arg_itr.next();
        return args;
    }

    fn deinit(self: *CmdArgs) void {
        self.arg_itr.deinit();
    }

    fn parse(self: *Self) !void {
        var argv = self.arg_itr;
        while (argv.next())|argz| {
            const arg = std.mem.sliceTo(argz, 0);
            if (std.mem.eql(u8, arg, "--by-delimiter")) {
                self.by_delimiter = true;
            } else if (std.mem.eql(u8, arg, "--by-length")) {
                self.by_length = true;
            }
        }
    }

};


