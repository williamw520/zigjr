// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William W. Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayHashMap = std.json.ArrayHashMap;

const zigjr = @import("zigjr");
const DelimiterStream = zigjr.DelimiterStream;
const Logger = zigjr.Logger;


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    {
        var logger = try zigjr.FileLogger.init("log.txt");
        defer logger.deinit();

        // Create a registry for the JSON-RPC handlers.
        var handlers = zigjr.RpcRegistry.init(alloc);
        defer handlers.deinit();

        // Register each RPC method with a handling function.
        try handlers.register("initialize", null, mcp_initialize);
        try handlers.register("notifications/initialized", &logger, mcp_notifications_initialized);
        try handlers.register("tools/list", &logger, mcp_tools_list);
        try handlers.register("tools/call", &logger, mcp_tools_call);

        // Read a stream of JSON requests from the reader, handle each with handlers,
        // and write JSON responses to the writer.  Request frames are delimited by '\n'.
        const streamer = DelimiterStream.init(alloc, .{ .logger = Logger.by(&logger) });
        try streamer.streamRequests(std.io.getStdIn().reader(),
                                    std.io.getStdOut().writer(),
                                    handlers);
    }

    if (gpa.detectLeaks()) {
        std.debug.print("Memory leak detected!\n", .{});
    }    
}


fn mcp_initialize(params: InitializeRequest_Params) InitializeResult {
    _=params;
    return .{
        .protocolVersion = "2025-03-26",    // https://github.com/modelcontextprotocol/modelcontextprotocol/tree/main/schema/2025-03-26
        .capabilities = ServerCapabilities {
            .prompts = .{
                .listChanged = false,
            },
            .resources = .{
                .listChanged = false,
                .subscribe = false,
            },
            .tools = .{
                .listChanged = false,
            },
        },
        .serverInfo = Implementation {
            .name = "zigjr mcp_hello",
            .version = "1.0.0",
        },
        .instructions = "Hello world",
    };
}

fn mcp_notifications_initialized(logger: *zigjr.FileLogger, _: struct {}) void {
    logger.log("mcp_notifications_initialized", "method called", "notification/initialized");
}

fn mcp_tools_list(logger: *zigjr.FileLogger, alloc: Allocator, request: ListToolsRequest) !ListToolsResult {
    const msg = try std.fmt.allocPrint(alloc, "tools/list. request: {any}", .{request});
    logger.log("mcp_tools_list", "method called", msg);
    var tools = std.ArrayList(Tool).init(alloc);
    try tools.append(Tool {
        .name = "hello",
        .description = "Reply hello world.",
        .inputSchema = .{
            .@"type" = "object",
            .properties = .{
            },
            .required = null,
        },
    });
    return .{
        .tools = tools.items,
    };
}

fn mcp_tools_call(logger: *zigjr.FileLogger, alloc: Allocator, params: std.json.Value) !CallToolResult {
    const tool = params.object.get("name").?.string;
    // const arguments = params.object.get("arguments").?.object;
    const msg = try std.fmt.allocPrint(alloc, "name: {s}", .{tool});
    logger.log("mcp_tools_call", "method called", msg);

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
    } else {
        var contents = std.ArrayList(Content).init(alloc);
        try contents.append(.{
            .text = try std.fmt.allocPrint(alloc, "Tool {s} not found", .{tool}),
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

const InitializeRequest_Params = struct {
    protocolVersion:    []const u8,
    capabilities:       ClientCapabilities,
    clientInfo:         Implementation,
};

const Implementation = struct {
    name:               []const u8,
    version:            []const u8,
};

const ClientCapabilities = struct {
    experimental:       ?ArrayHashMap([]const u8) = null,
    roots:              ?struct {
        listChanged:        bool,
    } = null,
    sampling:           ?ArrayHashMap([]const u8) = null,
};

const InitializeResult = struct {
    _meta:              ?ArrayHashMap([]const u8) = null,
    protocolVersion:    []const u8,
    capabilities:       ServerCapabilities,
    serverInfo:         Implementation,
    instructions:       ?[]const u8,
};

const ServerCapabilities = struct {
    completions:        ?ArrayHashMap([]const u8) = null,
    experimental:       ?ArrayHashMap([]const u8) = null,
    logging:            ?ArrayHashMap([]const u8) = null,
    prompts:            ?struct {
        listChanged:        bool,
    } = null,
    resources:          ?struct {
        listChanged:        bool,
        subscribe:          bool,
    } = null,
    tools:              ?struct {
        listChanged:        bool,
    } = null,
};

const ListToolsRequest = struct {
    params: ?struct {
        cursor:   ?[]const u8 = null,
    } = null,

};

const ListToolsResult = struct {
    _meta:      ?ArrayHashMap([]const u8) = null,
    nextCursor: ?[]const u8 = null,
    tools:      []Tool,
};

const Tool = struct {
    name:           []const u8,
    description:    []const u8,
    inputSchema:    InputSchema,
    // annotations:    ?ToolAnnotations,
};

const InputSchema = struct {
    // @"type":        []u8 = .{ 'o', 'b', 'j', 'e', 'c', 't' },
    @"type":        []const u8,
    properties:     ArrayHashMap([]const u8),
    required:       ?[][]const u8 = null,
};

const CallToolResult = struct {
    content:        []Content,
    isError:        bool = false,
};

const Content = struct {
    text:           []const u8,
    @"type":        []const u8,
};


