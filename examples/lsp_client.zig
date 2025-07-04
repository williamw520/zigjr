// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William W. Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;
const Value = std.json.Value;
const ObjectMap = std.json.ObjectMap;
const allocPrint = std.fmt.allocPrint;

const zigjr = @import("zigjr");
const RpcId = zigjr.RpcId;
const makeRequestJson = zigjr.composer.makeRequestJson;
const writeContentLengthFrame = zigjr.frame.writeContentLengthFrame;
const writeContentLengthRequest = zigjr.frame.writeContentLengthRequest;

const MyErrors = error{ MissingCfg, MissingCmd };


/// A LSP client example that spawns a LSP server as a sub-process and
/// talks to it over the stdin/stdout transport.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    {
        var args = try CmdArgs.init(alloc);
        defer args.deinit();
        args.parse() catch { usage(); return; };
        std.debug.print("[lsp_client] LSP server cmd: {s}\n", .{ args.cmd_argv.items });

        var child = std.process.Child.init(args.cmd_argv.items, alloc);
        child.stdin_behavior    = .Pipe;
        child.stdout_behavior   = .Pipe;
        child.stderr_behavior   = .Inherit;  // show child's stderr in the parent's stderr
        try child.spawn();

        const response_thread  = try Thread.spawn(.{}, response_worker, .{ child.stdout.? });
        try request_worker(child.stdin.?);  // Run request_worker in the main thread.

        response_thread.join();
        child.stdin = null;                 // already closed by the request_worker; clear so it won't be closed again.
        _ = try child.wait();
    }
    if (gpa.detectLeaks()) {
        std.debug.print("Memory leak detected!\n", .{});
    }    
}

fn usage() void {
    std.debug.print(
        \\Usage:  lsp_client lsp_server arguments
        \\
        , .{});
}

// Poorman's quick and dirty command line argument parsing.
const CmdArgs = struct {
    arg_itr:        std.process.ArgIterator,
    cmd_argv:       std.ArrayList([]const u8),

    fn init(alloc: Allocator) !@This() {
        return .{
            .arg_itr = try std.process.argsWithAllocator(alloc),
            .cmd_argv = std.ArrayList([]const u8).init(alloc),
        };
    }

    fn deinit(self: *@This()) void {
        self.arg_itr.deinit();
        self.cmd_argv.deinit();
    }

    fn parse(self: *@This()) !void {
        var argv = self.arg_itr;
        _ = argv.next();            // skip this program's name.
        while (argv.next())|argz| {
            const arg = std.mem.sliceTo(argz, 0);
            if (std.mem.eql(u8, arg, "--cfg")) {
                // if (std.mem.sliceTo(argv.next(), 0)) |cfg| {
                //     self.cfg = cfg;
                // } else {
                //     return error.MissingCfg;
                // }
            } else {
                try self.cmd_argv.append(arg);  // collect the sub-process cmd and args.
            }
        }

        if (self.cmd_argv.items.len == 0) return error.MissingCmd;
    }

};

fn request_worker(in_stdin: std.fs.File) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    const in_writer = in_stdin.writer();
    var id: i64 = 0;

    std.debug.print("[request_worker] starts\n", .{});
    std.time.sleep(1_000_000_000);  // Wait a bit to let the LSP server to come up.

    std.debug.print("[request_worker] sending 'initialize' message \n", .{});
    id += 1;
    const initialize_params = InitializeParams {
        .capabilities = .{},
    };
    try writeContentLengthRequest(alloc, in_writer, "initialize", initialize_params, RpcId.of(id));

    try writeContentLengthRequest(alloc, in_writer, "initialized", InitializedParams{}, RpcId.ofNone());

    // TODO: input-request loop

    std.time.sleep(5_000_000_000);

    std.debug.print("[request_worker] shutdown request\n", .{});
    id += 1;
    try writeContentLengthRequest(alloc, in_writer, "shutdown", null, RpcId.of(id));
    try writeContentLengthRequest(alloc, in_writer, "exit", null, RpcId.ofNone());

    std.time.sleep(500_000_000);
    in_stdin.close();   // force an EOF signal to the subprocess.
    std.debug.print("[request_worker] exits\n", .{});
}

fn response_worker(child_stdout: std.fs.File) !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // const alloc = gpa.allocator();

    const out_reader = child_stdout.reader();
    std.debug.print("[response_worker] starts\n", .{});

    const buf_size = 1024;
    var buf: [buf_size]u8 = undefined;
    while (true) {
        const read_len = try out_reader.read(&buf);
        if (read_len == 0) break;
        std.debug.print("[response_worker] Child response: {s}\n", .{buf[0..read_len]});
    }

    std.debug.print("[response_worker] exits\n", .{});
}


// LSP messages

pub const InitializeParams = struct {
    processId: ?i32 = null,
    clientInfo: ?struct {
        name: []const u8,               // The name of the client.
        version: ?[]const u8 = null,    // The client's version.
    } = null,
    locale: ?[]const u8 = null,
    rootPath: ?[]const u8 = null,       // rootPath of the workspace
    capabilities: ClientCapabilities,   // client capabilities
};

/// Defines the capabilities provided by the client.
pub const ClientCapabilities = struct {
};

/// Client let the server know that it's ready to accept requests.
pub const InitializedParams = struct {
};


