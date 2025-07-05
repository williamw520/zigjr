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

const MyErrors = error{ MissingCfg, MissingCmd, MissingSourceFile };


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
        \\Usage:  lsp_client --file source.zig lsp_server arguments
        \\
        , .{});
}

// Poorman's quick and dirty command line argument parsing.
const CmdArgs = struct {
    arg_itr:        std.process.ArgIterator,
    cmd_argv:       std.ArrayList([]const u8),
    src_file:       []const u8,

    fn init(alloc: Allocator) !@This() {
        return .{
            .arg_itr = try std.process.argsWithAllocator(alloc),
            .cmd_argv = std.ArrayList([]const u8).init(alloc),
            .src_file = "",
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
            if (std.mem.eql(u8, arg, "--file")) {
                if (std.mem.sliceTo(argv.next(), 0)) |src_file| {
                    self.src_file = src_file;
                } else {
                    return error.MissingSourceFile;
                }
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
    var id: i64 = 1;
    var buf = std.ArrayList(u8).init(alloc);
    defer buf.deinit();

    std.debug.print("\n[==== request_worker ====] starts\n", .{});

    std.time.sleep(1_000_000_000);  // Wait a bit to let the LSP server to come up.
    std.debug.print("\n[==== request_worker ====] Send 'initialize' message. id: {}\n", .{id});
    const initializeParams = InitializeParams {
        .rootUri = "file:///tmp",
        .capabilities = .{},
    };
    try writeContentLengthRequest(alloc, in_writer, "initialize", initializeParams, RpcId.of(id));
    id += 1;

    std.time.sleep(1_000_000_000);
    std.debug.print("\n[==== request_worker ====] Send 'initialized' notification. id: none\n", .{});
    try writeContentLengthRequest(alloc, in_writer, "initialized", InitializedParams{}, RpcId.ofNone());
    id += 1;

    std.time.sleep(1_000_000_000);
    std.debug.print("\n[==== request_worker ====] Send 'textDocument/didOpen' notification. id: none\n", .{});
    const didOpenTextDocumentParams = DidOpenTextDocumentParams {
        .textDocument = TextDocumentItem {
            .uri = "file:///tmp/foo.zig",
            .languageId = "zig",
            .version = 1,
            .text =
                \\  fn add(a: i64, b: i64) i64 {
                \\      return a + b;
                \\  }
                \\  fn inc1(a: i64) i64 {
                \\      return 1 + add
                \\  }
                ,
        },
    };
    try writeContentLengthRequest(alloc, in_writer, "textDocument/didOpen", didOpenTextDocumentParams, RpcId.ofNone());
    id += 1;

    std.time.sleep(1_000_000_000);
    std.debug.print("\n[==== request_worker ====] Send 'textDocument/definition' message. id: {}\n", .{id});
    const definitionParams = DefinitionParams {
        .textDocument = .{ .uri = "file:///tmp/foo.zig" },
        .position =     .{ .line = 1, .character = 17   },  // at the "b" parameter
    };
    try writeContentLengthRequest(alloc, in_writer, "textDocument/definition", definitionParams, RpcId.of(id));
    id += 1;

    std.time.sleep(1_000_000_000);
    std.debug.print("\n[==== request_worker ====] Send 'textDocument/hover' message. id: {}\n", .{id});
    const hoverParams = HoverParams {
        .textDocument = .{ .uri = "file:///tmp/foo.zig" },
        .position =     .{ .line = 3, .character = 9    },  // at the "inc1" identifier
    };
    try writeContentLengthRequest(alloc, in_writer, "textDocument/hover", hoverParams, RpcId.of(id));
    id += 1;

    std.time.sleep(1_000_000_000);
    std.debug.print("\n[==== request_worker ====] Send 'textDocument/signatureHelp' message. id: {}\n", .{id});
    const signatureHelpParams = SignatureHelpParams {
        .textDocument = .{ .uri = "file:///tmp/foo.zig" },
        .position =     .{ .line = 3, .character = 9    },  // at the "inc1" identifier
    };
    try writeContentLengthRequest(alloc, in_writer, "textDocument/signatureHelp", signatureHelpParams, RpcId.of(id));
    id += 1;

    std.time.sleep(1_000_000_000);
    std.debug.print("\n[==== request_worker ====] Send 'textDocument/completion' message. id: {}\n", .{id});
    const completionParams = CompletionParams {
        .textDocument = .{ .uri = "file:///tmp/foo.zig" },
        .position =     .{ .line = 2, .character = 19   },  // right after the "add" identifier
    };
    try writeContentLengthRequest(alloc, in_writer, "textDocument/completion", completionParams, RpcId.of(id));
    id += 1;

    std.time.sleep(1_000_000_000);
    std.debug.print("\n[==== request_worker ====] Send 'shutdown' request. id: {}\n", .{id});
    try writeContentLengthRequest(alloc, in_writer, "shutdown", null, RpcId.of(id));
    id += 1;

    std.time.sleep(1_000_000_000);
    std.debug.print("\n[==== request_worker ====] Send 'exit' notification\n", .{});
    try writeContentLengthRequest(alloc, in_writer, "exit", null, RpcId.ofNone());
    id += 1;

    std.time.sleep(1_000_000_000);
    in_stdin.close();   // send an EOF signal to subprocess in case shutdown/exit didn't work.
    std.debug.print("\n[==== request_worker ====] exits\n", .{});
}

fn response_worker(child_stdout: std.fs.File) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const out_reader = child_stdout.reader();
    std.debug.print("[response_worker] starts\n", .{});

    var buf = std.ArrayList(u8).init(alloc);
    defer buf.deinit();
    var chunk: [1024]u8 = undefined;
    while (true) {
        const chunk_len = try out_reader.read(&chunk);
        if (chunk_len == 0) break;
        try buf.appendSlice(chunk[0..chunk_len]);
        if (chunk_len == 1024) continue;    // bug if the whole msg is aligned at 1024.
        std.debug.print("\n[---- response_worker ---] LSP server response:\n{s}\n\n", .{buf.items});
        buf.clearRetainingCapacity();
    }

    std.debug.print("[response_worker] exits\n", .{});
}

// LSP messages, with much omissions.
// https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/

const InitializeParams = struct {
    processId: ?i32 = null,
    clientInfo: ?struct {
        name: []const u8,               // The name of the client.
        version: ?[]const u8 = null,    // The client's version.
    } = null,
    locale: ?[]const u8 = null,
    rootUri: ?[]const u8 = null,        // rootPath of the workspace
    capabilities: ClientCapabilities,   // client capabilities
};

const ClientCapabilities = struct {
};

const InitializedParams = struct {
};

const DidOpenTextDocumentParams = struct {
    textDocument: TextDocumentItem,
};

const TextDocumentItem = struct {
    uri: []const u8,
    languageId: []const u8,
    version: i32,
    text: []const u8,
};

const CompletionParams = struct {
    textDocument: TextDocumentIdentifier,
    position: Position,
};

const HoverParams = struct {
    textDocument: TextDocumentIdentifier,
    position: Position,
};

const SignatureHelpParams = struct {
    textDocument: TextDocumentIdentifier,
    position: Position,
};

const DefinitionParams = struct {
    textDocument: TextDocumentIdentifier,
    position: Position,
};

const TextDocumentIdentifier = struct {
    uri: []const u8,
};

const Position = struct {
    line: u32,
    character: u32,
};

