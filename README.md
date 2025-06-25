# ZigJR - JSON-RPC 2.0 Library for Zig

ZigJR is a lightweight Zig library providing a full implementation of the JSON-RPC 2.0 protocol,
with message streaming on top, and a smart function dispatcher that turns native Zig functions 
into RPC handlers. It aims to make building JSON-RPC applications in Zig simple and straightforward.

This small library is packed with the following features:

* Parsing and composing JSON-RPC 2.0 messages.
* Support for Request, Response, Notification, and Error JSON-RPC 2.0 messages.
* Support for batch requests and batch responses in JSON-RPC 2.0.
* Message streaming via delimiter based streams (`\n`, etc.).
* Message streaming via `Content-Length` header-based streams.
* RPC pipeline to process the full request-to-response lifecycle.
* Native Zig functions as message handlers with automatic type mapping.
* Flexible logging mechanism for inspecting the JSON-RPC messages.

## Content

* [Quick Usage](#quick-usage)
* [Installation](#installation)
* [Usage](#usage)
* [Dispatcher](#dispatcher)
* [RpcRegistry](#rpcregistry)
* [Custom Dispatcher](#custom-dispatcher)
* [Invocation and Cleanup](#invocation-and-cleanup)
* [Handler Function](#handler-function)
* [Transport](#transport)
* [Project Build](#project-build)
* [Examples](#examples)
* [Run the MCP Server Example](#run-the-mcp-server-example)
* [License](#license)
* [References](#references)


## Quick Usage

The following example shows a JSON-RPC server that registers native Zig functions 
as RPC handlers in a registry, creates a dispatcher from the registry,
and uses it to stream JSON-RPC messages from `stdin` to `stdout`.

The functions take in native Zig data types and return native result values or errors,
which are mapped to the JSON data types automatically.

```zig
{
    var registry = zigjr.RpcRegistry.init(alloc);

    try registry.add"say", say);
    try registry.add("hello", hello);
    try registry.add("hello-name", helloName);
    try registry.add("substr", substr);
    try registry.add("weigh-cat", weigh);

    try zigjr.stream.requestsByDelimiter(alloc, 
        std.io.getStdIn().reader(), std.io.getStdOut().writer(), 
        RequestDispatcher.implBy(&registry), .{});
}

fn say(msg: []const u8) void {
    std.debug.print("Message to say: {s}\n", .{msg});
}

fn hello() []const u8 {
    return "Hello world";
}

fn helloName(alloc: Allocator, name: [] const u8) ![]const u8 {
    return try std.fmt.allocPrint(alloc, "Hello {s}", .{name});
}

fn substr(name: [] const u8, start: i64, len: i64) []const u8 {
    return name[@intCast(start) .. @intCast(len)];
}

fn weigh(cat: CatInfo) f64 {
    return cat.weight;
}
```
Check [hello.zig](examples/hello.zig) for a complete example.  

Sample request and response messages.
```
Request:  {"jsonrpc": "2.0", "method": "hello", "id": 1}
Response: {"jsonrpc": "2.0", "result": "Hello world", "id": 1}
```
```
Request:  {"jsonrpc": "2.0", "method": "hello-name", "params": ["Spiderman"], "id": 2}
Response: {"jsonrpc": "2.0", "result": "Hello Spiderman", "id": 2}
```

## Installation

Select a version of the library in the [Releases](https://github.com/williamw520/zigjr/releases) page,
and copy its asset URL. E.g. https://github.com/williamw520/zigjr/archive/refs/tags/1.0.0.tar.gz

Use `zig fetch` to add the ZigJR package to your project's dependencies. Replace `<VERSION>` with the version you selected.
```shell
zig fetch --save https://github.com/williamw520/zigjr/archive/refs/tags/<VERSION>.tar.gz
```

This command updates your `build.zig.zon` file, adding ZigJR to the `dependencies` section with its URL and content hash.

 ```diff
 .{
    .name = "my-project",
    ...
    .dependencies = .{
 +       .zigjr = .{
 +           .url = "zig fetch https://github.com/williamw520/zigjr/archive/refs/tags/<VERSION>.tar.gz",
 +           .hash = "zigjr-...",
 +       },
    },
 }
 ```

Next, update your `build.zig` to add the ZigJR module to your executable.

```diff
pub fn build(b: *std.Build) void {
    ...
+  const opts = .{ .target = target, .optimize = optimize };
+  const zigjr_module = b.dependency("zigjr", opts).module("zigjr");
    ...
    const exe = b.addExecutable(.{
        .name = "my_project",
        .root_module = exe_mod,
    });
+  exe.root_module.addImport("zigjr", zigjr_module);
```

The `.addImport("zigjr")` call makes the library's module available to your executable, allowing you to import it in your source files:
```zig
const zigjr = @import("zigjr");
```


## Usage

You can build JSON-RPC 2.0 applications with ZigJR at several levels of abstraction:
* **Streaming API:** Handle message frames for continuous communication (recommended).
* **RPC Pipeline:** Process individual requests and responses.
* **Parsers and Composers:** Manually build and parse JSON-RPC messages for maximum control.

For most use cases, the Streaming API is the simplest and most powerful approach.

### Streaming API
The following example handles a stream of messages prefixed with a `Content-Length` header, 
reading requests from `stdin` and writing responses to `stdout`.
```zig
{
    var registry = zigjr.RpcRegistry.init(alloc);
    defer registry.deinit();
    try registry.add("add", addTwoNums);

    const dispatcher = zigjr.RequestDispatcher.implBy(&registry);
    try zigjr.stream.requestsByContentLength(alloc, std.io.getStdIn().reader(), 
        std.io.getStdOut().writer(), dispatcher, .{});
}

fn addTwoNums(a: i64, b: i64) i64 { return a + b; }
```

This example streams messages from one in-memory buffer to another, 
using a newline character (`\n`) as a delimiter.
```zig
{
    var registry = zigjr.RpcRegistry.init(alloc);
    defer registry.deinit();
    try registry.add("add", addTwoNums);

    const req_jsons =
        \\{"jsonrpc": "2.0", "method": "add", "params": [1, 2], "id": 1}
        \\{"jsonrpc": "2.0", "method": "add", "params": [3, 4], "id": 2}
        \\{"jsonrpc": "2.0", "method": "add", "params": [5, 6], "id": 3}
    ;
    var in_stream = std.io.fixedBufferStream(req_jsons);

    var out_buf = ArrayList(u8).init(alloc);
    defer out_buf.deinit();

    const dispatcher = zigjr.RequestDispatcher.implBy(&registry);
    try zigjr.stream.requestsByDelimiter(alloc, in_stream.reader(), 
        out_buf.writer(), dispatcher, .{});

    std.debug.print("output_jsons: {s}\n", .{out_buf.items});
}
```

### RPC Pipeline
To handle individual requests, use the `RequestPipeline`. It abstracts away message parsing, 
dispatching, and response composition.

```zig
{
    // Set up the registry as the dispatcher.
    var registry = zigjr.RpcRegistry.init(alloc);
    defer registry.deinit();
    try registry.add("add", addTwoNums);
    const dispatcher = zigjr.RequestDispatcher.implBy(&registry);

    // Set up the request pipeline with the dispatcher.
    var pipeline = zigjr.RequestPipeline.init(alloc, dispatcher, null);
    defer pipeline.deinit();

    // Run the individual requests to the pipeline.
    const response_json1 = pipeline.runRequestToJson(
        \\{"jsonrpc": "2.0", "method": "add", "params": [1, 2], "id": 1}
    );
    defer alloc.free(response_json1);

    const response_json2 = pipeline.runRequestToJson(
        \\{"jsonrpc": "2.0", "method": "add", "params": [3, 4], "id": 2}
    );
    defer alloc.free(response_json2);

    const response_json3 = pipeline.runRequestToJson(
        \\{"jsonrpc": "2.0", "method": "add", "params": [5, 6], "id": 3}
    );
    defer alloc.free(response_json3);
}
```

### Parse JSON-RPC Messages
For lower-level control, you can parse messages directly into `RpcRequest` objects,
where the request's method, parameters, and request ID can be accessed.
```zig
const zigjr = @import("zigjr");
{
    var result = zigjr.parseRpcRequest(alloc,
        \\{"jsonrpc": "2.0", "method": "func42", "params": [42], "id": 1}
    );
    defer result.deinit();
    const req = try result.request();
    try testing.expect(std.mem.eql(u8, req.method, "func42"));
    try testing.expect(req.arrayParams().?.items.len == 1);
    try testing.expect(req.arrayParams().?.items[0].integer == 42);
    try testing.expect(req.id.num == 1);
}
```
`parseRpcRequest()` can parse a single message or a batch of messages.  Use `result.batch()` to get the list of requests in the batch.

### Compose JSON-RPC Messages
The `composer` API helps to build valid JSON-RPC messages.
```zig
const zigjr = @import("zigjr");
{
    const msg1 = try zigjr.composer.makeRequestJson(alloc, "hello", null, zigjr.RpcId { .num = 1 });
    defer alloc.free(msg1);

    const msg2 = try zigjr.composer.makeRequestJson(alloc, "hello-name", ["Spiderman"], zigjr.RpcId { .num = 1 });
    defer alloc.free(msg2);
}
```

## Dispatcher
The dispatcher is the entry point for handling incoming RPC messages. 
After a message is parsed, the RPC pipeline feeds it to the dispatcher, 
which routes it to a handler function based on the message's `method`. 
The `RequestDispatcher` and `ResponseDispatcher` interfaces define the required dispatching functions.

## RpcRegistry
The built-in `RpcRegistry` implements the `RequestDispatcher` interface and 
serves as a powerful, ready-to-use dispatcher. Use `RpcRegistry.add(method_name, function)` 
to register a handler function for a specific JSON-RPC method. When a request comes in, 
the registry looks up the handler, maps the request's parameters to the function's arguments, 
calls the function, and captures the result or error to formulate a response.

```zig
{
    var registry = zigjr.RpcRegistry.init(alloc);
    defer registry.deinit();

    try registry.add("add", addTwoNums);
    try registry.add("sub", subTwoNums);
    ...
    const dispatcher = zigjr.RequestDispatcher.implBy(&registry);
    ...
}
```

## Custom Dispatcher
You can provide a custom dispatcher as long as it implements the `dispatch()` and `dispatchEnd()` 
functions of the `RequestDispatcher` interface. See the `dispatcher_hello.zig` example for details.

## Invocation and Cleanup
Each request is processed in two phases: `dispatch()`, which executes the handler, 
and `dispatchEnd()`, which performs per-invocation cleanup (such as freeing memory).

## Handler Function
Message handler functions are native Zig functions.

### Scopes
Handler functions can be defined in the global scope, a struct scope, or a struct instance scope.

For instance-scoped methods, pass a pointer to the struct instance as the context 
when registering the handler. This context pointer will be passed as the first parameter 
to the handler function when it is invoked.

```zig
{
    try registry.add("global-fn", global_fn);
    try registry.add("group-fn", Group.group_fn);
    ...
    var counter = Counter{};
    try registry.addWithCtx("counter-inc", &counter, Counter.inc);
    try registry.addWithCtx("counter-get", &counter, Counter.get);
    ...
}

fn global_fn() void { }

const Group = struct {
    fn group_fn() void { }
};

const Counter = struct {
    count:  i64 = 0;

    fn inc(self: *@This()) void { self.count += 1; }
    fn get(self: *@This()) i64  { return self.count; }
};
```

### Parameters
Handler function parameters are native Zig types, with a few limitations related 
to JSON compatibility. Parameter types should generally map to JSON types:

*   `bool`: JSON boolean
*   `i64`: JSON number (compatible with JavaScript's 53-bit safe integer range)
*   `f64`: JSON number (64-bit float)
*   `[]const u8`: JSON string
*   `struct`: JSON object

There're some light automatic type conversion when the function parameter's type
and the JSON message's parameter type are closely related. (See `ValueAs()` in json_call.zig for details).

Struct parameters must be deserializable from JSON. The corresponding handler 
parameter's struct must have fields that match the JSON object. ZigJR uses `std.json` 
for deserialization. Nested objects are supported, and you can implement custom 
parsing by adding a `jsonParseFromValue` function to your struct. See the `std.json` 
documentation for details.

### Special Parameters

#### Context

If a context pointer is supplied to `RpcRegistry.addWithCtx()`, it is passed as 
the first parameter to the handler function, effectively serving as a `self` pointer.

The first parameter's type and the context type need to be the same.

#### Allocator
If an `std.mem.Allocator` is the first parameter of a handler (or the second, 
if a context is used as the first), an arena allocator is passed in. The handler does 
not need to free memory allocated with it; the arena is automatically reset after the request completes.
The arena memory is reset in dispatchEnd() called by higher level callers.

#### Value
To handle parameters manually, you can use `std.json.Value`:
* As the **only** parameter: The entire `params` field from the request (`array` or `object`) is passed as a single `std.json.Value`.
    ```zig
    fn h1(params: std.json.Value) void { /* ... */ }
    ```
* As **one of several** parameters: The corresponding JSON-RPC parameter is passed as a `std.json.Value` without being converted to a native Zig type.
    ```zig
    fn h3(a: std.json.Value, b: i64, c: std.json.Value) void { /* ... */ }
    ```

### Return Value
The return value of a handler function is serialized to JSON and becomes the `result` 
of the JSON-RPC response. You can return any Zig type that can be serialized by `std.json`.

If your function returns a `void`, it is treated as a Notification, and no response message is generated.

### Error
You can declare an error union as the return type. Any error returned will be 
packaged into a JSON-RPC error response with the `InternalError` code.

### Memory Management
When using `RpcRegistry`, memory management is straightforward. Any memory 
obtained from the allocator passed to a handler is automatically freed 
after the request completes. Handlers do not need to perform manual cleanup.
Memory is freed in the `dispatcher.dispatchEnd()` phase.

If you implement a custom dispatcher, you are responsible for managing the memory's lifecycle.

### Logging

Logging is a great way to learn about a protocol by watching the messages exchanged between
the client and server. ZigJR has a built-in logging mechanism to help you inspect messages 
and debug handlers. You can use a pre-built logger or implement a custom one.

#### DbgLogger
Use `DbgLogger` in a request pipeline. This logger prints to `stderr`.
```zig
    var logger = zigjr.DbgLogger{};
    const pipeline = zigjr.pipeline.RequestPipeline.init(alloc, 
        RequestDispatcher.implBy(&registry), zigjr.Logger.implBy(&logger));
    
```
#### FileLogger
Use `FileLogger` in a request stream. This logger writes to a file.
```zig
    var logger = try zigjr.FileLogger.init("log.txt");
    defer logger.deinit();
    try zigjr.stream.requestsByDelimiter(alloc,
        std.io.getStdIn().reader(), std.io.getStdOut().writer(),
        dispatcher, .{ .logger = Logger.implBy(&logger) });
```
#### Custom Logger
Use a custom logger in a request pipeline.
```zig
{
    var logger = MyLogger{};
    const pipeline = zigjr.pipeline.RequestPipeline.init(alloc, 
        RequestDispatcher.implBy(&registry), zigjr.Logger.implBy(&logger));
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
```

## Transport

A few words on message transport. ZigJR doesn't deal with transport at all. 
It sits on top of any transport, network or others.
It's assumed the JSON-RPC messages are sent over some transport before arriving at ZigJR.

## Project Build

You do not need to build this project if you are only using it as a library 
via `zig fetch`. To run the examples, clone the repository and run `zig build` to build the project.
The example binaries will be located in `zig-out/bin/`.

## Examples

The project has a number of examples showing how to build applications with ZigJR.

* [hello.zig](examples/hello.zig): Showcase the basics of handler function registration and the streaming API.
* [calc.zig](examples/calc.zig): Showcase different kinds of handler functions.
* [dispatcher_hello.zig](examples/dispatcher_hello.zig): Custom dispatcher.
* [mcp_hello.zig](examples/mcp_hello.zig): A basic MCP server written from the ground up.

Check [examples](examples) for other examples.

### Run Examples Interactively
Running the programs interactively is a great way to experiment with the handlers.
Just type in the JSON requests and see the result.
```
zig-out/bin/hello
```
The program will wait for input. Type or paste the JSON-RPC request and press Enter.
```
{"jsonrpc": "2.0", "method": "hello", "id": 1}
```
It will print the JSON result.
```
{"jsonrpc": "2.0", "result": "Hello world", "id": 1}
```

Other sample requests,
```
{"jsonrpc": "2.0", "method": "hello-name", "params": ["Foobar"], "id": 1}
```
```
{"jsonrpc": "2.0", "method": "hello-name", "params": ["Spiderman"], "id": 1}
```
```
{"jsonrpc": "2.0", "method": "hello-xtimes", "params": ["Spiderman", 3], "id": 1}
```
```
{"jsonrpc": "2.0", "method": "say", "params": ["Abc Xyz"], "id": 1}
```

### Run Examples with Data Files
You can also run the examples by piping test data from a file, which is useful for creating repeatable tests.
```
zig-out/bin/hello < data/hello.json
zig-out/bin/hello < data/hello_name.json
zig-out\bin/hello < data/hello_xtimes.json
zig-out/bin/hello < data/hello_say.json
zig-out/bin/hello < data/hello_stream.json
```

Some more sample data files.  Examine the data files in the [Data](data) directory to 
see how they exercise the message handlers.
```
zig-out/bin/calc.exe < data/calc_add.json
zig-out/bin/calc.exe < data/calc_weight.json
zig-out/bin/calc.exe < data/calc_sub.json
zig-out/bin/calc.exe < data/calc_multiply.json
zig-out/bin/calc.exe < data/calc_divide.json
zig-out/bin/calc.exe < data/calc_divide_99.json
zig-out/bin/calc.exe < data/calc_divide_by_0.json
```

## Run the MCP Server Example

The `mcp_hello` executible can be run standalone on a console for testing its message handling,
or run as an embedded subprocess in a MCP host.

#### Standalone Run

Run it standalone. Feed the MCP requests by hand.

```
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","clientInfo":{"name":"mcphost","version":"1.0.0"},"capabilities":{}}}
```
```
{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}
```
```
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
```
```
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"hello","arguments":{}}}
```
```
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"hello-name","arguments":{"name":"Mate"}}}
```

#### Embedded in a MCP Host

This uses [MCP Host](https://github.com/mark3labs/mcphost) as an example.  

Create a configuration file `config-mcp-hello.json` with `command` pointing to the mcp_hello executible.
```json
{
  "mcpServers": {
    "mcp-hello": {
      "command": "/zigjr/zig-out/bin/mcp_hello.exe",
      "args": []
    }
  }
}
```

Run `mcphost` with one of the LLM providers.
```
mcphost --config config-mcp-hello.json --provider-api-key YOUR-API-KEY --model anthropic:claude-3-5-sonnet-latest
mcphost --config config-mcp-hello.json --provider-api-key YOUR-API-KEY --model openai:gpt-4
mcphost --config config-mcp-hello.json --provider-api-key YOUR-API-KEY --model google:gemini-2.0-flash
```

Type `hello`, `hello Joe` or `hello Joe 10` in the prompt for testing. The `log.txt` file captures the interaction.

## License

ZigJR is [MIT licensed](./LICENSE).

## References

- [JSON-RPC 2.0 Specification](https://www.jsonrpc.org/specification)
- [MCP Schema](https://github.com/modelcontextprotocol/modelcontextprotocol/tree/main/schema)

