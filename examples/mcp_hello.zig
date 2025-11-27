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
const ObjectMap = std.json.ObjectMap;
const allocPrint = std.fmt.allocPrint;

const zigjr = @import("zigjr");
const Logger = zigjr.Logger;


/// A simple MCP server example using the stdin/stdout transport. It implements:
/// - MCP handshake
/// - MCP tool discovery
/// - MCP tool call
/// - A few sample tools:
///     hello: replies "Hello World!" when called.
///     hello-name: replies "Hello 'NAME'!" when called with a name.
///     hello-xtimes: replies "Hello 'NAME'" X times when called with a name and a number.
pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // Getting the stdin and stdout boilerplate.
    var stdin_buffer: [1024]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
    const stdin = &stdin_reader.interface;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    // Use a file-based logger since the executable is run in a MCP host
    // as a sub-process and cannot log to the host's stdout.
    var f_logger = try zigjr.FileLogger.init(alloc, "log.txt");
    defer f_logger.deinit();

    var rpc_dispatcher = try zigjr.RpcDispatcher.init(alloc);
    defer rpc_dispatcher.deinit();

    // Register the MCP RPC methods.
    // Pass the logger in as the context so handlers can also log to the log file.
    try rpc_dispatcher.addWithCtx("initialize", &f_logger, mcp_initialize);
    try rpc_dispatcher.addWithCtx("notifications/initialized", &f_logger, mcp_notifications_initialized);
    try rpc_dispatcher.addWithCtx("tools/list", &f_logger, mcp_tools_list);
    try rpc_dispatcher.addWithCtx("tools/call", &f_logger, mcp_tools_call);

    // Starts the JSON streaming pipeline from stdin to stdout.
    try zigjr.stream.runByDelimiter(alloc, stdin, stdout, &rpc_dispatcher,
                                    .{ .logger = f_logger.asLogger() });
}

// The MCP message handlers.
//
// All the MCP message parameters and return values are defined in below 
// as Zig structs or tagged unions according to the MCP JSON schema spec.
// ZigJR automatically does the mapping between the structs and the JSON objects.

// First message from a MCP client to do the initial handshake.
fn mcp_initialize(logger: *zigjr.FileLogger, alloc: Allocator,
                  params: InitializeRequest_params) !InitializeResult {
    const msg = try allocPrint(alloc, "client name: {s}, version: {s}", .{params.clientInfo.name, params.clientInfo.version});
    logger.log("mcp_initialize", "initialize", msg);

    return .{
        .protocolVersion = "2025-03-26",    // https://github.com/modelcontextprotocol/modelcontextprotocol/tree/main/schema/2025-03-26
        .serverInfo = Implementation {
            .name = "zigjr mcp_hello",
            .version = "1.0.0",
        },
        .instructions = "It has a number of tools for replying to the 'hello' requests.",
        .capabilities = ServerCapabilities {
            .tools = .{},                   // server capable of doing tools
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
    var tools: std.ArrayList(Tool) = .empty;

    const helloTool = Tool.init(alloc, "hello", "Replying a 'Hello World' when called.");
    try tools.append(alloc, helloTool);

    var helloNameTool = Tool.init(alloc, "hello-name", "Replying a 'Hello NAME' when called with a NAME.");
    try helloNameTool.inputSchema.addProperty("name", "string", "The name to say hello to");
    try helloNameTool.inputSchema.addRequired("name");
    try tools.append(alloc, helloNameTool);

    var helloXTimesTool = Tool.init(alloc, "hello-xtimes", "Replying a 'Hello NAME NUMBER' repeated X times when called with a NAME and a number.");
    try helloXTimesTool.inputSchema.addProperty("name", "string", "The name to say hello to");
    try helloXTimesTool.inputSchema.addRequired("name");
    try helloXTimesTool.inputSchema.addProperty("times", "integer", "The number of times to repeat");
    try helloXTimesTool.inputSchema.addRequired("times");
    try tools.append(alloc, helloXTimesTool);

    return .{
        .tools = tools,
    };
}

fn mcp_tools_call(logger: *zigjr.FileLogger, alloc: Allocator, params: Value) !CallToolResult {
    const tool = params.object.get("name").?.string;
    const msg = try allocPrint(alloc, "tool name: {s}", .{tool});
    logger.log("mcp_tools_call", "tools/call", msg);

    // We'll just do a poorman's dispatching on the MCP tool name.
    if (std.mem.eql(u8, tool, "hello")) {
        var ctr = CallToolResult.init(alloc);
        try ctr.addTextContent("Hello World!");
        return ctr;
    } else if (std.mem.eql(u8, tool, "hello-name")) {
        const arguments = params.object.get("arguments").?.object;
        const name = arguments.get("name") orelse Value{ .string = "not set" };
        logger.log("mcp_tools_call", "arguments", name.string);

        var ctr = CallToolResult.init(alloc);
        try ctr.addTextContent(try allocPrint(alloc, "Hello '{s}'!", .{name.string}));
        return ctr;
    } else if (std.mem.eql(u8, tool, "hello-xtimes")) {
        const arguments = params.object.get("arguments").?.object;
        const name = arguments.get("name") orelse Value{ .string = "not set" };
        const times = arguments.get("times") orelse Value{ .integer = 1 };
        const repeat: usize = if (0 < times.integer and times.integer < 100) @intCast(times.integer) else 1;
        var buf = std.Io.Writer.Allocating.init(alloc);
        var writer = &buf.writer;
        for (0..repeat) |_| try writer.print("Hello {s}! ", .{name.string});
        var ctr = CallToolResult.init(alloc);
        try ctr.addTextContent(buf.written());
        return ctr;
    } else {
        var ctr = CallToolResult.init(alloc);
        try ctr.addTextContent(try allocPrint(alloc, "Tool {s} not found", .{tool}));
        ctr.isError = true;
        return ctr;
    }
}


// The following MCP message structs should have been put in a library,
// but they're put here to illustrate that it's not too hard to come up with a MCP server.

/// See the MCP message schema definition and sample messages for detail.
/// https://github.com/modelcontextprotocol/modelcontextprotocol/tree/main/schema/2025-03-26
/// https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2025-03-26/basic/lifecycle.mdx
/// https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2025-03-26/server/tools.mdx

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
    cursor:             ?[]const u8 = null,
};

const ListToolsResult = struct {
    _meta:              ?Value = null,
    nextCursor:         ?[]const u8 = null,
    tools:              std.ArrayList(Tool),

    pub fn jsonStringify(self: @This(), jsonWriteStream: anytype) !void {
        const jws = jsonWriteStream;
        try jws.beginObject();
        {
            if (self._meta) |val| try writeField(jws, "_meta", val);
            if (self.nextCursor) |val| try writeField(jws, "nextCursor", val);
            try jws.objectField("tools");
            try jws.write(self.tools.items);
        }
        try jws.endObject();
    }
};

const Tool = struct {
    name:               []const u8,
    description:        ?[]const u8 = null,
    inputSchema:        InputSchema,
    annotations:        ?ToolAnnotations = null,

    pub fn init(alloc: Allocator, name: []const u8, desc: []const u8) @This() {
        return .{
            .name = name,
            .description = desc,
            .inputSchema = InputSchema.init(alloc),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.inputSchema.deinit();
    }

};

const InputSchema = struct {
    alloc:              Allocator,
    @"type":            [6]u8 = "object".*,
    properties:         Value,
    required:           std.ArrayList([]const u8),

    pub fn init(alloc: Allocator) @This() {
        return .{
            .alloc = alloc,
            .properties = jsonObject(alloc),
            .required = .empty,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.properties.object.deinit();
        self.required.deinit();
    }

    pub fn jsonStringify(self: @This(), jsonWriteStream: anytype) !void {
        const jws = jsonWriteStream;
        try jws.beginObject();
        {
            try jws.objectField("type");
            try jws.write(self.@"type");

            try jws.objectField("properties");
            try jws.write(self.properties);

            try jws.objectField("required");
            try jws.write(self.required.items);
        }
        try jws.endObject();
    }

    pub fn addProperty(self: *@This(), prop_name: []const u8, type_name: []const u8, type_desc: []const u8) !void {
        const typeInfo = try typeObject(self.alloc, type_name, type_desc);
        try self.properties.object.put(prop_name, typeInfo);
    }

    pub fn addRequired(self: *@This(), field_name: []const u8) !void {
        try self.required.append(self.alloc, field_name);
    }

};

const Annotations = struct {
    audience:           std.ArrayList(Role),
    priority:           i64,    // "maximum": 1, "minimum": 0

    pub fn jsonStringify(self: @This(), jsonWriteStream: anytype) !void {
        const jws = jsonWriteStream;
        try jws.beginObject();
        {
            try jws.objectField("audience");
            try jws.beginArray();
            for (self.audience.items)|role| {
                try jws.write(@tagName(role));
            }
            try jws.endArray();

            try jws.objectField("priority");
            try jws.write(self.priority);
        }
        try jws.endObject();
    }
};

const Role = enum {
    assistant,
    user
};

const ToolAnnotations = struct {
    destructiveHint:    bool = false,
    idempotentHint:     bool = false,
    openWorldHint:      bool = false,
    readOnlyHint:       bool = false,
    title:              []const u8,
};

const CallToolResult = struct {
    alloc:              Allocator,
    _meta:              ?Value = null,
    content:            std.ArrayList(Content),
    isError:            bool = false,

    pub fn init(alloc: Allocator) @This() {
        return .{
            .alloc = alloc,
            .content = .empty
        };
    }

    pub fn addTextContent(self: *@This(), text: []const u8) !void {
        try self.content.append(self.alloc, Content{ .text = TextContent{ .text = text } });
    }
    
    pub fn addImageContent(self: *@This(), data: []const u8, mineType: []const u8) !void {
        try self.content.append(self.alloc, Content {
            .image = ImageContent {
                .data = data,
                .mimeType = mineType,
            }
        });
    }
    
    pub fn addAudioContent(self: *@This(), data: []const u8, mineType: []const u8) !void {
        try self.content.append(self.alloc, Content {
            .audio = AudioContent {
                .data = data,
                .mimeType = mineType,
            }
        });
    }
    
    pub fn jsonStringify(self: @This(), jsonWriteStream: anytype) !void {
        const jws = jsonWriteStream;
        try jws.beginObject();
        {
            if (self._meta) |val| try writeField(jws, "_meta", val);

            try jws.objectField("content");
            try jws.write(self.content.items);

            try jws.objectField("isError");
            try jws.write(self.isError);
        }
        try jws.endObject();
    }
    
};

const Content = union(enum) {
    text:               TextContent,
    image:              ImageContent,
    audio:              AudioContent,
    embedded:           EmbeddedResource,

    pub fn jsonStringify(self: @This(), jsonWriteStream: anytype) !void {
        const jws = jsonWriteStream;
        switch (self) {
            .text   => |text|   try jws.write(text),
            .image  => |image|  try jws.write(image),
            .audio  => |audio|  try jws.write(audio),
            .embedded => |emb|  try jws.write(emb),
        }
    }
};

const TextContent = struct {
    @"type":            [4]u8 = "text".*,
    text:               []const u8,
    annotations:        ?Annotations = null,
};

const ImageContent = struct {
    @"type":            [5]u8 = "image".*,
    mimeType:           []const u8,
    data:               []const u8,     // the base64-encoded image data.
    annotations:        ?Annotations = null,
};

const AudioContent = struct {
    @"type":            [5]u8 = "audio".*,
    mimeType:           []const u8,
    data:               []const u8,     // the base64-encoded audio data.
    annotations:        ?Annotations = null,
};

const EmbeddedResource = struct {
    @"type":            [8]u8 = "resource".*,
    resource:           ResourceContents,
    annotations:        ?Annotations = null,
};

const ResourceContents = union(enum) {
    text:               TextResourceContents,
    blob:               BlobResourceContents,

    pub fn jsonStringify(self: @This(), jsonWriteStream: anytype) !void {
        const jws = jsonWriteStream;
        switch (self) {
            .text   => |text|   try jws.write(text),
            .blob   => |blob|   try jws.write(blob),
        }
    }
};

const TextResourceContents = struct {
    mimeType:           ?[]const u8 = null,
    text:               []const u8,
    uri:                []const u8,
};

const BlobResourceContents = struct {
    mimeType:           ?[]const u8 = null,
    blob:               []const u8,
    uri:                []const u8,
};


fn jsonObject(alloc: Allocator) Value {
    return Value { .object = std.json.ObjectMap.init(alloc) };
}

fn typeObject(alloc: Allocator, type_name: []const u8, type_desc: []const u8) !Value {
    var value = jsonObject(alloc);
    try value.object.put("type", Value { .string = type_name });
    try value.object.put("description", Value { .string = type_desc });
    return value;
}

fn writeField(jws: anytype, name: []const u8, value: anytype) !void {
    try jws.objectField(name);
    try jws.write(value);
}

