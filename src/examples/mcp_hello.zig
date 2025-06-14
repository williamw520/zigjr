// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William W. Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = std.json.Value;
const allocPrint = std.fmt.allocPrint;

const zigjr = @import("zigjr");
const DelimiterStream = zigjr.DelimiterStream;
const Logger = zigjr.Logger;


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    {
        // Use a file-based logger so we can save the RPC messages to a file
        // as the executable is run in a mcp host as a subprocess and cannot log to stdout.
        var logger = try zigjr.FileLogger.init("log.txt");
        defer logger.deinit();

        var handlers = zigjr.RpcRegistry.init(alloc);
        defer handlers.deinit();

        // Register the MCP RPC methods.
        // Pass the logger in as context so each handler can also log to the log file.
        try handlers.register("initialize", null, mcp_initialize);
        try handlers.register("notifications/initialized", &logger, mcp_notifications_initialized);
        try handlers.register("tools/list", &logger, mcp_tools_list);
        try handlers.register("tools/call", &logger, mcp_tools_call);

        // Starts the JSON stream pipeline on stdin and stdout.
        const streamer = DelimiterStream.init(alloc, .{ .logger = Logger.by(&logger) });
        try streamer.streamRequests(std.io.getStdIn().reader(),
                                    std.io.getStdOut().writer(),
                                    handlers);
    }

    if (gpa.detectLeaks()) {
        std.debug.print("Memory leak detected!\n", .{});
    }    
}

// The MCP message handlers

fn mcp_initialize(params: InitializeRequest_params) InitializeResult {
    _=params;
    return .{
        .protocolVersion = "2025-03-26",    // https://github.com/modelcontextprotocol/modelcontextprotocol/tree/main/schema/2025-03-26
        .serverInfo = Implementation {
            .name = "zigjr mcp_hello",
            .version = "1.0.0",
        },
        .instructions = "Hello world",
        .capabilities = ServerCapabilities {
            .tools = .{
            },
        },
    };
}

fn mcp_notifications_initialized(logger: *zigjr.FileLogger, alloc: Allocator,
                                 params: InitializedNotification_params) !void {
    const msg = try allocPrint(alloc, "params: {any}", .{params});
    logger.log("mcp_notifications_initialized", "notifications/initialized", msg);
}

fn mcp_tools_list(logger: *zigjr.FileLogger, alloc: Allocator,
                  params: ListToolsRequest_params) !ListToolsResult {
    const msg = try allocPrint(alloc, "params: {any}", .{params});
    logger.log("mcp_tools_list", "tools/list", msg);
    var tools = std.ArrayList(Tool).init(alloc);
    try tools.append(Tool {
        .name = "hello",
        .description = "Replying a 'Hello World' when called.",
        .inputSchema = .{
            .properties = try jsonObject(alloc),
            .required = &.{},       // empty array.
        },
    });

    var helloNameParam = try jsonObject(alloc);
    try helloNameParam.object.put("type", Value { .string = "string" });
    try helloNameParam.object.put("description", Value { .string = "The name to say hello to" });
    var helloNameInput = try jsonObject(alloc);
    try helloNameInput.object.put("name", helloNameParam);

    var helloNameInputRequired = std.ArrayList([]const u8).init(alloc);
    try helloNameInputRequired.append("name");
    try tools.append(Tool {
        .name = "hello-name",
        .description = "Replying a 'Hello NAME' when called with the NAME.",
        .inputSchema = .{
            .properties = helloNameInput,
            .required = helloNameInputRequired.items,
        },
    });

    return .{
        .tools = tools.items,
    };
}

fn mcp_tools_call(logger: *zigjr.FileLogger, alloc: Allocator, params: Value) !CallToolResult {
    const tool = params.object.get("name").?.string;
    const msg = try allocPrint(alloc, "name: {s}", .{tool});
    logger.log("mcp_tools_call", "tools/call", msg);

    if (std.mem.eql(u8, tool, "hello")) {
        var contents = std.ArrayList(Content).init(alloc);
        try contents.append(.{
            .text = "Hello World",
            .@"type" = "text",
        });
        return .{
            .content = contents.items,
            .isError = false,
        };
    } else if (std.mem.eql(u8, tool, "hello-name")) {
        const arguments = params.object.get("arguments").?.object;
        const name = arguments.get("name") orelse Value{ .string = "not set" };
        logger.log("mcp_tools_call", "arguments", name.string);
        var contents = std.ArrayList(Content).init(alloc);
        try contents.append(.{
            .text = try allocPrint(alloc, "Hello '{s}'!", .{name.string}),
            .@"type" = "text",
        });
        return .{
            .content = contents.items,
            .isError = false,
        };
    } else {
        var contents = std.ArrayList(Content).init(alloc);
        try contents.append(.{
            .text = try allocPrint(alloc, "Tool {s} not found", .{tool}),
            .@"type" = "text",
        });
        return .{
            .content = contents.items,
            .isError = true,
        };
    }
}

/// See MCP message schema for detail.
/// https://github.com/modelcontextprotocol/modelcontextprotocol/tree/main/schema/2025-03-26

const InitializeRequest_params = struct {
    protocolVersion:    []const u8,
    capabilities:       ClientCapabilities,
    clientInfo:         Implementation,
};

const Implementation = struct {
    name:               []const u8,
    version:            []const u8,
};

const ClientCapabilities = struct {
    roots:              ?struct {
        listChanged:        bool,
    } = null,
    sampling:           ?Value = null,
    experimental:       ?Value = null,
};

const InitializeResult = struct {
    _meta:              ?Value = null,
    protocolVersion:    []const u8,
    capabilities:       ServerCapabilities,
    serverInfo:         Implementation,
    instructions:       ?[]const u8,
};

const InitializedNotification_params = struct {
    _meta:              ?Value = null,
};

const ServerCapabilities = struct {
    completions:        ?Value = null,
    experimental:       ?Value = null,
    logging:            ?Value = null,
    prompts:            ?struct {
        listChanged:        ?bool = false,
    } = null,
    resources:          ?struct {
        listChanged:        ?bool = false,
        subscribe:          ?bool = false,
    } = null,
    tools:              ?struct {
        listChanged:        ?bool = false,
    } = null,
};

const ListToolsRequest_params = struct {
    cursor:     ?[]const u8 = null,
};

const ListToolsResult = struct {
    _meta:      ?Value = null,
    nextCursor: ?[]const u8 = null,
    tools:      []Tool,
};

const Tool = struct {
    name:           []const u8,
    description:    ?[]const u8 = null,
    inputSchema:    InputSchema,
    annotations:    ?ToolAnnotations = null,
};

const InputSchema = struct {
    @"type":        [6]u8 = "object".*,
    properties:     ?Value = null,
    required:       ?[][]const u8 = null,
};

const ToolAnnotations = struct {
    destructiveHint:    bool = false,
    idempotentHint:     bool = false,
    openWorldHint:      bool = false,
    readOnlyHint:       bool = false,
    title:              []const u8,
};

const CallToolResult = struct {
    content:        []Content,
    isError:        bool = false,
};

const Content = struct {
    text:           []const u8,
    @"type":        []const u8,
};



fn jsonObject(alloc: Allocator) !Value {
    return Value { .object = std.json.ObjectMap.init(alloc) };
}

