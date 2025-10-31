// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William W. Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

// Note: For now this example doesn't work on Windows with the Zig 0.15.1 changes.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;
const ArrayList = std.ArrayList;
const Value = std.json.Value;
const ObjectMap = std.json.ObjectMap;
const allocPrint = std.fmt.allocPrint;
const StringifyOptions = std.json.Stringify.Options;

const zigjr = @import("zigjr");
const RpcId = zigjr.RpcId;
const writeContentLengthRequest = zigjr.frame.writeContentLengthRequest;
const responsesByContentLength = zigjr.stream.responsesByContentLength;
const messagesByContentLength = zigjr.stream.messagesByContentLength;
const RpcDispatcher = zigjr.RpcDispatcher;
const RequestDispatcher = zigjr.RequestDispatcher;
const ResponseDispatcher = zigjr.ResponseDispatcher;
const RpcRequest = zigjr.RpcRequest;
const RpcResponse = zigjr.RpcResponse;
const DispatchResult = zigjr.DispatchResult;

const MyErrors = error{ MissingCfg, MissingCmd, MissingSourceFile };


/// A LSP client example that spawns a LSP server as a sub-process and
/// talks to it over the stdin/stdout transport.
pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var args = try CmdArgs.init(alloc);
    defer args.deinit();
    args.parse() catch { usage(); return; };
    std.debug.print("[lsp_client] LSP server cmd: {s}\n", .{ args.cmd_argv.items[0] });

    var child = std.process.Child.init(args.cmd_argv.items, alloc);
    child.stdin_behavior    = .Pipe;
    child.stdout_behavior   = .Pipe;
    child.stderr_behavior   = if (args.stderr) .Inherit else .Ignore;
    try child.spawn();

    const request_thread    = try Thread.spawn(.{}, request_worker,  .{ child.stdin.? });
    const response_thread   = try Thread.spawn(.{}, response_worker, .{ child.stdout.?, args });

    request_thread.join();
    response_thread.join();

    child.stdin = null; // already closed by the request_worker; clear so it won't be closed again.
    _ = try child.wait();
}

fn usage() void {
    std.debug.print(
        \\Usage:  lsp_client [--json | --pp-json | --dump | --stderr ] lsp_server [arguments]
        \\        --json    print the JSON result from server.
        \\        --pp-json pretty-print the JSON result from server.
        \\        --dump    dump the raw response messages.
        \\        --stderr  print LSP server's stderr to this process' stderr.
        \\
        \\e.g.    lsp_client /zls/zls.exe
        \\e.g.    lsp_client --pp-json /zls/zls.exe
        \\e.g.    lsp_client --pp-json /zls/zls.exe --enable-stderr-logs
        , .{});
}

// Poorman's quick and dirty command line argument parsing.
const CmdArgs = struct {
    alloc:          Allocator,
    arg_itr:        std.process.ArgIterator,
    cmd_argv:       ArrayList([]const u8),
    json:           bool = false,
    pp_json:        bool = false,
    dump:           bool = false,
    stderr:         bool = false,

    fn init(alloc: Allocator) !@This() {
        return .{
            .alloc = alloc,
            .arg_itr = try std.process.argsWithAllocator(alloc),
            .cmd_argv = .empty,
        };
    }

    fn deinit(self: *@This()) void {
        self.arg_itr.deinit();
        self.cmd_argv.deinit(self.alloc);
    }

    fn parse(self: *@This()) !void {
        var argv = self.arg_itr;
        _ = argv.next();            // skip this program's name.
        while (argv.next())|argz| {
            const arg = std.mem.sliceTo(argz, 0);
            if (false) {}
            else if (std.mem.eql(u8, arg, "--json"))    { self.json = true; }
            else if (std.mem.eql(u8, arg, "--pp-json")) { self.pp_json = true; }
            else if (std.mem.eql(u8, arg, "--dump"))    { self.dump = true; }
            else if (std.mem.eql(u8, arg, "--stderr"))  { self.stderr = true; }
            else { try self.cmd_argv.append(self.alloc, arg); } // collect the lsp-server cmd and args.
        }

        if (self.cmd_argv.items.len == 0) return error.MissingCmd;
    }

};

fn request_worker(in_stdin: std.fs.File) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const alloc = gpa.allocator();
    var writer_buf: [1024]u8 = undefined;
    var in_fwriter = in_stdin.writer(&writer_buf);
    const in_writer = &in_fwriter.interface;
    var id: i64 = 1;

    std.debug.print("\n[==== request_worker ====] starts\n", .{});

    std.Thread.sleep(1_000_000_000);  // Wait a bit to let the LSP server to come up.
    std.debug.print("\n[==== request_worker ====] Send 'initialize' message. id: {}\n", .{id});
    const initializeParams = InitializeParams {
        .rootUri = "file:///tmp",
        .capabilities = .{},
    };
    try writeContentLengthRequest(alloc, in_writer, "initialize", initializeParams, RpcId.of(id));
    id += 1;

    std.Thread.sleep(1_000_000_000);
    std.debug.print("\n[==== request_worker ====] Send 'initialized' notification. id: none\n", .{});
    try writeContentLengthRequest(alloc, in_writer, "initialized", InitializedParams{}, RpcId.ofNone());
    id += 1;

    std.Thread.sleep(1_000_000_000);
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

    std.Thread.sleep(1_000_000_000);
    std.debug.print("\n[==== request_worker ====] Send 'textDocument/definition' message. id: {}\n", .{id});
    const definitionParams = DefinitionParams {
        .textDocument = .{ .uri = "file:///tmp/foo.zig" },
        .position =     .{ .line = 1, .character = 17   },  // at the "b" parameter
    };
    try writeContentLengthRequest(alloc, in_writer, "textDocument/definition", definitionParams, RpcId.of(id));
    id += 1;

    std.Thread.sleep(1_000_000_000);
    std.debug.print("\n[==== request_worker ====] Send 'textDocument/hover' message. id: {}\n", .{id});
    const hoverParams = HoverParams {
        .textDocument = .{ .uri = "file:///tmp/foo.zig" },
        .position =     .{ .line = 3, .character = 9    },  // at the "inc1" identifier
    };
    try writeContentLengthRequest(alloc, in_writer, "textDocument/hover", hoverParams, RpcId.of(id));
    id += 1;

    std.Thread.sleep(1_000_000_000);

    std.debug.print("\n[==== request_worker ====] Send 'textDocument/signatureHelp' message. id: {}\n", .{id});
    const signatureHelpParams = SignatureHelpParams {
        .textDocument = .{ .uri = "file:///tmp/foo.zig" },
        .position =     .{ .line = 3, .character = 9    },  // at the "inc1" identifier
    };
    try writeContentLengthRequest(alloc, in_writer, "textDocument/signatureHelp", signatureHelpParams, RpcId.of(id));
    id += 1;

    std.Thread.sleep(1_000_000_000);
    std.debug.print("\n[==== request_worker ====] Send 'textDocument/completion' message. id: {}\n", .{id});
    const completionParams = CompletionParams {
        .textDocument = .{ .uri = "file:///tmp/foo.zig" },
        .position =     .{ .line = 2, .character = 19   },  // right after the "add" identifier
    };
    try writeContentLengthRequest(alloc, in_writer, "textDocument/completion", completionParams, RpcId.of(id));
    id += 1;

    std.Thread.sleep(1_000_000_000);
    std.debug.print("\n[==== request_worker ====] Send 'shutdown' request. id: {}\n", .{id});
    try writeContentLengthRequest(alloc, in_writer, "shutdown", null, RpcId.of(id));
    id += 1;

    std.Thread.sleep(1_000_000_000);
    std.debug.print("\n[==== request_worker ====] Send 'exit' notification\n", .{});
    try writeContentLengthRequest(alloc, in_writer, "exit", null, RpcId.ofNone());
    id += 1;

    std.Thread.sleep(1_000_000_000);
    in_stdin.close();   // send an EOF signal to subprocess in case shutdown/exit didn't work.
    std.debug.print("\n[==== request_worker ====] exits\n", .{});
}

fn response_worker(child_stdout: std.fs.File, args: CmdArgs) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const alloc = gpa.allocator();

    var reader_buf: [1024]u8 = undefined;
    var out_freader = child_stdout.readerStreaming(&reader_buf);
    var out_reader = &out_freader.interface;
    std.debug.print("[---- response_worker ---] starts\n", .{});

    if (args.dump) {
        // Dump the raw messages from LSP server.
        var buf: ArrayList(u8) = .empty;
        defer buf.deinit(alloc);
        var chunk: [1024]u8 = undefined;
        while (true) {
            const chunk_len = try out_reader.readSliceShort(&chunk);
            if (chunk_len == 0) break;
            try buf.appendSlice(alloc, chunk[0..chunk_len]);
            if (chunk_len == 1024)
                continue;   // if the msg aligns at 1024, will read the next msg and combine both.
            std.debug.print("\n[---- response_worker ---] Server json:\n{s}\n\n", .{buf.items});
        }
    } else {
        // LSP server can send 'server_to_client' notifications/events as JSON-RPC requests.
        // Use ZigJR's RpcRegistry and Fallback to process the request messages.
        var rpc_dispatcher = zigjr.RpcDispatcher.init(alloc);
        defer rpc_dispatcher.deinit();

        rpc_dispatcher.setOnBefore(null, onBefore);

        var fallbackCtx: FallbackCtx = .{
            .log_json = (args.json or args.pp_json),
            .json_opt = if (args.pp_json) .{ .whitespace = .indent_2 } else .{},
        };
        rpc_dispatcher.setOnFallback(&fallbackCtx, onFallback);

        // Comment out this to see the fallback_handler being called.
        try rpc_dispatcher.add("window/logMessage", window_logMessage);

        // Use ZigJR's ResponseDispatcher to process the response messages.
        var res_dispatcher = ResDispatcher {
            .log_json = (args.json or args.pp_json),
            .json_opt = if (args.pp_json) .{ .whitespace = .indent_2 } else .{},
        };

        var stderr_buffer: [1024]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
        const stderr = &stderr_writer.interface;

        // Use the generic 'messagesByContentLength' to handle both requests and responses.
        try messagesByContentLength(alloc, out_reader, stderr,
                                    RequestDispatcher.implBy(&rpc_dispatcher),
                                    ResponseDispatcher.implBy(&res_dispatcher), .{});
    }

    std.debug.print("[---- response_worker ---] exits\n", .{});
}

fn onBefore(_: *anyopaque, _: Allocator, req: RpcRequest) void {
    // req.result has the result JSON object from server.
    // req.id is the request id; dispatch based on the id recorded in request_worker().
    std.debug.print("\n[---- response_worker ---] Server sent request, method: {s}, id: {any}\n",
                    .{req.method, req.id});
}

const FallbackCtx = struct {
    log_json:   bool,
    json_opt:   StringifyOptions,
};

fn onFallback(ctx_ptr: *anyopaque, alloc: Allocator, req: RpcRequest) anyerror!DispatchResult {
    const ctx =  @as(*FallbackCtx, @ptrCast(@alignCast(ctx_ptr)));
    if (ctx.log_json) {
        const params_json = try std.json.Stringify.valueAlloc(alloc, req.params, ctx.json_opt);
        defer alloc.free(params_json);
        std.debug.print("{s}\n", .{params_json});
    }
    return DispatchResult.asNone();
}

// Handler for the 'window/logMessage' request from server.
fn window_logMessage(params: LogMessageParams) void {
    std.debug.print("type:    {}\nmessage: {s}\n", .{params.@"type", params.message});
}

const ResDispatcher = struct {
    log_json:   bool,
    json_opt:   StringifyOptions,

    pub fn dispatch(self: *@This(), alloc: Allocator, res: RpcResponse) anyerror!void {
        // res.result has the result JSON object from server.
        // res.id is the request id; dispatch based on the id recorded in request_worker().
        if (res.hasErr()) {
            std.debug.print("\n[---- response_worker ---] Server sent error response, error code: {}, msg, {s}\n",
                            .{res.err().code, res.err().message});
        } else {
            std.debug.print("\n[---- response_worker ---] Server sent response, id: {any}\n", .{res.id.num});
            if (self.log_json) {
                const result_json = try std.json.Stringify.valueAlloc(alloc, res.result, self.json_opt);
                defer alloc.free(result_json);
                std.debug.print("{s}\n", .{result_json});
            }
        }
    }
};


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

const LogMessageParams = struct {
    @"type": MessageType,
    message: []const u8,
};

const MessageType = enum(i64) {
    Error = 1,
    Warning = 2,
    Info = 3,
    Log = 4,
    Debug = 5,
};

