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

    const run_http = if (args.is_http) true else if (args.is_net) false
    else {
        usage();
        return;
    };

    const rpc_dispatcher = try createDispatcher(alloc);
    defer destroyDispatcher(alloc, rpc_dispatcher);

    try runServer(run_http, rpc_dispatcher);
}

fn createDispatcher(alloc: Allocator) !*zigjr.RpcDispatcher {
    var rpc_dispatcher = try alloc.create(zigjr.RpcDispatcher);
    rpc_dispatcher.* = zigjr.RpcDispatcher.init(alloc);
    
    try rpc_dispatcher.add("hello", hello);
    try rpc_dispatcher.add("hello-name", helloName);
    try rpc_dispatcher.add("hello-xtimes", helloXTimes);
    try rpc_dispatcher.add("substr", substr);
    try rpc_dispatcher.add("say", say);
    try rpc_dispatcher.add("opt-text", optionalText);
    try rpc_dispatcher.add("end-session", endSession);

    return rpc_dispatcher;
}

fn destroyDispatcher(alloc: Allocator, dispatcher: *zigjr.RpcDispatcher) void {
    dispatcher.deinit();
    alloc.destroy(dispatcher);
}

fn runServer(is_http: bool, dispatcher: *const zigjr.RpcDispatcher) !void {
    const address   = "0.0.0.0:25354";
    const net_addr  = try std.net.Address.parseIpAndPort(address);
    var server      = try net_addr.listen(.{ .reuse_address = true });
    defer server.deinit();

    while (true) {
        const connection = try server.accept();
        if (is_http) {
            _ = try std.Thread.spawn(.{}, httpWorker, .{dispatcher, connection});
        } else {
            _ = try std.Thread.spawn(.{}, netWorker, .{dispatcher, connection});
        }
    }
}

fn httpWorker(dispatcher: *const zigjr.RpcDispatcher, connection: std.net.Server.Connection) void {
    std.debug.print("Start session (netWorker).\n", .{});

    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    runHttpSession(alloc, dispatcher, connection) catch |e| {
        std.debug.print("Error in runSession: {any}\n", .{e});
    };

    connection.stream.close();
    std.debug.print("End session (netWorker).\n", .{});
}

fn netWorker(dispatcher: *const zigjr.RpcDispatcher, connection: std.net.Server.Connection) void {
    std.debug.print("Start session (netWorker).\n", .{});

    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    runNetSession(alloc, dispatcher, connection) catch |e| {
        std.debug.print("Error in runSession: {any}\n", .{e});
    };

    connection.stream.close();
    std.debug.print("End session (netWorker).\n", .{});
}

fn runHttpSession(alloc: Allocator, dispatcher: *const zigjr.RpcDispatcher,
                  connection: std.net.Server.Connection) !void {
    var rbuf: [1024]u8  = undefined;
    var wbuf: [1024]u8  = undefined;
    var s_reader        = connection.stream.reader(&rbuf);
    var s_writer        = connection.stream.writer(&wbuf);
    const reader        = s_reader.interface();
    const writer        = &s_writer.interface;
    var dbg_logger      = zigjr.DbgLogger{};
    const logger        = zigjr.Logger.implBy(&dbg_logger);

    // TODO: Read and parse HTTP line, though ZigJR's header parser can ignore them.

    // Run until client disconnects.
    zigjr.stream.runByContentLength(alloc, reader, writer, dispatcher, .{
        .logger = logger
    }) catch |e| {
        if (e == error.ReadFailed) return else return e;
    };
}

fn runNetSession(alloc: Allocator, dispatcher: *const zigjr.RpcDispatcher,
              connection: std.net.Server.Connection) !void {
    var rbuf: [1024]u8  = undefined;
    var wbuf: [1024]u8  = undefined;
    var s_reader        = connection.stream.reader(&rbuf);
    var s_writer        = connection.stream.writer(&wbuf);
    const reader        = s_reader.interface();
    const writer        = &s_writer.interface;
    var dbg_logger      = zigjr.DbgLogger{};
    const logger        = zigjr.Logger.implBy(&dbg_logger);

    zigjr.stream.runByDelimiter(alloc, reader, writer, dispatcher, .{
        .logger = logger
    }) catch |e| {
        if (e == error.ReadFailed) return else return e;
    };
}


// A handler with no parameter and returns a string.
fn hello() []const u8 {
    return "Hello world";
}

// A handler takes in a string parameter and returns a string with error.
// It also asks the library for an allocator, which is passed in automatically.
// Allocated memory is freed automatically, making memory usage simple.
fn helloName(alloc: Allocator, name: [] const u8) Allocator.Error![]const u8 {
    return try std.fmt.allocPrint(alloc, "Hello {s}", .{name});
}

// This one takes one more parameter. Note that i64 is JSON's integer type.
fn helloXTimes(alloc: Allocator, name: [] const u8, times: i64) ![]const u8 {
    const repeat: usize = if (0 < times and times < 100) @intCast(times) else 1;
    var buf = std.Io.Writer.Allocating.init(alloc);
    for (0..repeat) |_| try buf.writer.print("Hello {s}! ", .{name});
    return buf.written();
}

fn substr(name: [] const u8, start: i64, len: i64) []const u8 {
    return name[@intCast(start) .. @intCast(len)];
}

// A handler takes in a string and has no return value, for RPC notification.
fn say(msg: [] const u8) void {
    std.debug.print("Message to say: {s}\n", .{msg});
}

fn optionalText(text: ?[] const u8) []const u8 {
    if (text)|txt| {
        return txt;
    } else {
        return "No text";
    }
}

fn endSession() zigjr.DispatchResult {
    return zigjr.DispatchResult.asEndStream();
}


fn usage() void {
    std.debug.print(
        \\Usage:  hello_net [--http | --net]
        \\
        \\  --http - runs the server over HTTP. JSON-RPC messages using Content-Length headers.
        \\  --net  - runs the server over plain TCP. JSON-RPC messages using LF delimiters.
        \\
        , .{});
}


const CmdArgs = struct {
    const Self = @This();

    arg_itr:    std.process.ArgIterator,
    is_http:    bool = false,
    is_net:     bool = false,

    fn init(alloc: Allocator) !CmdArgs {
        var args = CmdArgs { .arg_itr = try std.process.argsWithAllocator(alloc) };
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
            if (std.mem.eql(u8, arg, "--http")) {
                self.is_http = true;
            } else if (std.mem.eql(u8, arg, "--net")) {
                self.is_net = true;
            }
        }
    }

};


