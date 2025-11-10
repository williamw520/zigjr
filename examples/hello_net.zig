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

    const run_http = if (args.is_http) true else if (args.is_tcp) false
    else {
        usage();
        return;
    };

    const listen_address = try std.fmt.allocPrint(alloc, "0.0.0.0:{s}", .{args.port});
    defer alloc.free(listen_address);
    const local_address = try std.fmt.allocPrint(alloc, "127.0.0.1:{s}", .{args.port});
    defer alloc.free(local_address);
    std.debug.print("Server listening at port: {s}\n", .{args.port});

    var ctx = ServerCtx {
        .is_http = run_http,
        .listen_address = listen_address,
        .local_address = local_address,
        .end_server = std.atomic.Value(bool).init(false),
    };

    const rpc_dispatcher = try createDispatcher(alloc, &ctx);
    defer destroyDispatcher(alloc, rpc_dispatcher);
    try runServer(&ctx, rpc_dispatcher);
}

const ServerCtx = struct {
    is_http: bool,
    listen_address: []const u8,
    local_address: []const u8,
    end_server: std.atomic.Value(bool),
};

fn createDispatcher(alloc: Allocator, ctx: *ServerCtx) !*zigjr.RpcDispatcher {
    var rpc_dispatcher = try alloc.create(zigjr.RpcDispatcher);
    rpc_dispatcher.* = zigjr.RpcDispatcher.init(alloc);
    
    try rpc_dispatcher.add("hello", hello);
    try rpc_dispatcher.add("hello-name", helloName);
    try rpc_dispatcher.add("hello-xtimes", helloXTimes);
    try rpc_dispatcher.add("substr", substr);
    try rpc_dispatcher.add("say", say);
    try rpc_dispatcher.add("opt-text", optionalText);
    try rpc_dispatcher.add("end-session", endSession);
    try rpc_dispatcher.addWithCtx("end-server", ctx, endServer);

    return rpc_dispatcher;
}

fn destroyDispatcher(alloc: Allocator, dispatcher: *zigjr.RpcDispatcher) void {
    dispatcher.deinit();
    alloc.destroy(dispatcher);
}

fn runServer(ctx: *ServerCtx, dispatcher: *zigjr.RpcDispatcher) !void {
    const net_addr  = try std.net.Address.parseIpAndPort(ctx.listen_address);
    var server      = try net_addr.listen(.{ .reuse_address = true });
    defer server.deinit();

    while (true) {
        if (ctx.end_server.load(std.builtin.AtomicOrder.seq_cst))
            break;
        const connection = try server.accept();
        if (ctx.end_server.load(std.builtin.AtomicOrder.seq_cst))
            break;

        if (ctx.is_http) {
            _ = try std.Thread.spawn(.{}, httpWorker, .{dispatcher, connection});
        } else {
            _ = try std.Thread.spawn(.{}, netWorker, .{dispatcher, connection});
        }
    }
}

fn httpWorker(dispatcher: *zigjr.RpcDispatcher, connection: std.net.Server.Connection) void {
    std.debug.print("Start HTTP session.\n", .{});

    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    runHttpSession(alloc, dispatcher, connection) catch |e| {
        std.debug.print("Error in HTTP session: {any}\n", .{e});
    };

    connection.stream.close();
    std.debug.print("End HTTP session.\n", .{});
}

fn netWorker(dispatcher: *zigjr.RpcDispatcher, connection: std.net.Server.Connection) void {
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

fn runHttpSession(alloc: Allocator, rpc_dispatcher: *zigjr.RpcDispatcher,
                  connection: std.net.Server.Connection) !void {
    const dispatcher    = zigjr.RequestDispatcher.implBy(rpc_dispatcher);
    var rbuf: [1024]u8  = undefined;
    var wbuf: [1024]u8  = undefined;
    var s_reader        = connection.stream.reader(&rbuf);
    var s_writer        = connection.stream.writer(&wbuf);
    const reader        = s_reader.interface();
    const writer        = &s_writer.interface;
    var dbg_logger      = zigjr.DbgLogger{};
    var pipeline        = zigjr.RequestPipeline.init(alloc, dispatcher, dbg_logger.asLogger());
    var frame           = zigjr.frame.FrameData.init(alloc);

    defer pipeline.deinit();
    defer frame.deinit();

    try zigjr.frame.readHttpLine(reader, &frame);
    std.debug.print("HTTP Line: {s} {s} {s}\n", .{ frame.http_method, frame.http_path, frame.http_version });
    const has_data = try zigjr.frame.readContentLengthFrame(reader, &frame);
    if (!has_data)
        return;

    const request_json = std.mem.trim(u8, frame.getContent(), " \t\n\r");
    // std.debug.print("content_length: {any}, request_json: |{s}|\n", .{ frame.content_length, request_json });
    if (try pipeline.runRequestToJson(alloc, request_json)) |response| {
        defer alloc.free(response);
        try zigjr.frame.writeHttpStatusLine(writer, "1.1", 200, "OK");  // HTTP/1.1 200 OK\r\n
        try zigjr.frame.writeContentLengthFrame(writer, response);
        try writer.flush();
    } else {
        std.debug.print("No response\n", .{});
    }
}

fn runNetSession(alloc: Allocator, dispatcher: *zigjr.RpcDispatcher,
                 connection: std.net.Server.Connection) !void {
    var rbuf: [1024]u8  = undefined;
    var wbuf: [1024]u8  = undefined;
    var s_reader        = connection.stream.reader(&rbuf);
    var s_writer        = connection.stream.writer(&wbuf);
    const reader        = s_reader.interface();
    const writer        = &s_writer.interface;
    var dbg_logger      = zigjr.DbgLogger{};

    zigjr.stream.runByDelimiter(alloc, reader, writer, dispatcher, .{
        .logger = dbg_logger.asLogger()
    }) catch |e| {
        if (e == error.ReadFailed) return else return e;
    };
}

fn touchServer(address: []const u8) !void {
    const net_addr  = try std.net.Address.parseIpAndPort(address);
    var stream      = try std.net.tcpConnectToAddress(net_addr);
    defer stream.close();
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

fn endServer(ctx: *ServerCtx) zigjr.DispatchResult {
    // Set server termination flag.
    ctx.end_server.store(true, std.builtin.AtomicOrder.seq_cst);
    // Need to wake up server blocking at the .accept() call.
    touchServer(ctx.local_address) catch |e| {
        std.debug.print("Error in touching server at {s}. Error: {any}\n", .{ctx.local_address, e});
    };
    return zigjr.DispatchResult.asEndStream();
}


fn usage() void {
    std.debug.print(
        \\Usage:  hello_net [--http | --tcp] [--port N]
        \\
        \\  --http - runs the server over HTTP. JSON-RPC messages using Content-Length headers.
        \\  --tcp  - runs the server over plain TCP. JSON-RPC messages using LF delimiters.
        \\  --port N - set the listening port of the server.
        \\
        , .{});
}


const CmdArgs = struct {
    const Self = @This();

    arg_itr:    std.process.ArgIterator,
    is_http:    bool = false,
    is_tcp:     bool = false,
    port:       []const u8 = "35354",

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
            } else if (std.mem.eql(u8, arg, "--tcp")) {
                self.is_tcp = true;
            } else if (std.mem.eql(u8, arg, "--port")) {
                if (argv.next())|argz1| {
                    self.port = std.mem.sliceTo(argz1, 0);
                }
            }
        }
    }

};


