# ZigJR - JSON-RPC 2.0 Library for Zig

ZigJR is a Zig library for building applications using the JSON-RPC 2.0 protocol.
It has implemented the full spec of the JSON-RPC 2.0 for low level communication.
It also supports message streaming at message frame level.
In addition it has a smart function dispatcher that can dispatch RPC requests to 
Zig functions in native data types, making development of message handlers easy.

This small library is packed with the following features:

* Parsing and composing JSON-RPC 2.0 messages.
* Support Request, Response, Notification, and Error in JSON-RPC 2.0.
* Support batch requests and batch responses in JSON-RPC 2.0.
* Message streaming via delimiter based stream ('\n' or others).
* Message streaming via Content-Length header based stream.
* RPC pipeline to process request to response, vice versa.
* Dispatcher to dispatch messages to Zig functions in native types.
* Logging mechanism for inspecting the JSON-RPC messages.

## Content

* [Installation](#installation)
* [Usage](#usage)
  * [Memory Ownership](#memory-ownership)
  * [Configuration](#configuration)
  * [More Usage](#more-usage)
* [CLI Tool](#command-line-tool)
* [License](#license)

## Quick Usage
The following example shows a JSON-RPC server registering Zig functions 
as RPC handlers with a registry, creating a dispatcher from the registry,
and streaming JSON-RPC messages from stdin to stdout on it.

The functions take in native Zig data types and return native result values or errors.

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
        RequestDispatcher.impl_by(&registry), .{});
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


## Installation  

Select a version of the library in the [Releases](https://github.com/williamw520/zigjr/releases) page.
Identify the file asset URL for the selected version. 
E.g. https://github.com/williamw520/zigjr/archive/refs/tags/1.0.0.tar.gz

Use `zig fetch` to add the ZigJR package to your Zig project. 
```shell
  zig fetch --save https://github.com/williamw520/zigjr/archive/refs/tags/<VERSION>.tar.gz
```

`zig fetch` updates your `build.zig.zon` file with the URL with file hash added in the .dependency section of the file.

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

Update your `build.zig` with the following marked lines to include the zigjr library.

  ```diff
    pub fn build(b: *std.Build) void {
        ...
 +     const opts = .{ .target = target, .optimize = optimize };
 +     const zigjr_module = b.dependency("zigjr", opts).module("zigjr");
        ...
        const exe = b.addExecutable(.{
            .name = "my_project",
            .root_module = exe_mod,
        });
 +     exe.root_module.addImport("zigjr", zigjr_module);
```

The `.addImport("zigjr")` call let you import the module into your Zig source files.

```zig
const zigjr = @import("zigjr");
```


## Usage

JSON-RPC 2.0 applications can be built with ZigJR at different levels:
- Using the stream API to handle streaming messages at the message-frame level.
- Using the RPC pipeline for handling individual requests at the RPC level.
- Using the parsers and composers to parse and build JSON messages at the protocol level.

For most cases, the streaming API is the simplest.

### Handle Stream of Messages with Streaming API
The following sets up message streaming with reading requests from the StdIn
and writing the responses to the StdOut. The messages have Content-Length prefices.
```zig
{
    var registry = zigjr.RpcRegistry.init(alloc);
    defer registry.deinit();
    try registry.add("add", addTwoNums);

    const dispatcher = zigjr.RequestDispatcher.impl_by(&registry);
    try zigjr.stream.requestsByContentLength(alloc, std.io.getStdIn().reader(), 
        std.io.getStdOut().writer(), dispatcher, .{});
}

fn addTwoNums(a: i64, b: i64) i64 { return a + b; }
```

The following sets up message streaming with reading requests from an in-memory buffer
and writing the responses to an in-memory buffer.  The messages are delimited by LF.
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

    const dispatcher = zigjr.RequestDispatcher.impl_by(&registry);
    try zigjr.stream.requestsByDelimiter(alloc, in_stream.reader(), 
        out_buf.writer(), dispatcher, .{});

    std.debug.print("output_jsons: {s}\n", .{out_buf.items});
}

```

### Handle Single Message with RPC Pipeline
`RequestPipeline` combines request message parsing, dispatching, and response composing in one pipeline.

```zig
{
    var registry = zigjr.RpcRegistry.init(alloc);
    defer registry.deinit();
    try registry.add("add", addTwoNums);

    const dispatcher = zigjr.RequestDispatcher.impl_by(&registry);
    var pipeline = zigjr.RequestPipeline.init(alloc, dispatcher, null);
    defer pipeline.deinit();

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
For low level application, JSON-RPC messages can be parsed into RpcRequest objects,
where the request's method, parameters, and request ID can be retrieved.
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
```zig
const zigjr = @import("zigjr");
{
    const msg1 = try zigjr.composer.makeRequestJson(alloc, "hello", null, zigjr.RpcId { .num = 1 });
    defer alloc.free(msg1);

    const msg2 = try zigjr.composer.makeRequestJson(alloc, "hello-name", ["Spiderman"], zigjr.RpcId { .num = 1 });
    defer alloc.free(msg2);
}
```

## Dispatcher and Handler Functions
Dispatcher is the entry point for handling incoming RPC messages. After a message is parsed,
the RPC pipeline feeds it to the dispatcher to route to a handling function based on the message's method.
The `RequestDispatcher` interface and the `ResponseDispatcher` interface define
the sets of dispatching functions.

### RpcRegistry
The built-in `RpcRegistry` implements the `RequestDispatcher` interface and can serve as
a dispatcher. `RpcRegistry.add(method, function)` registers a handling function for a
JSON-RPC message's method. When a request is fed to `RpcRegistry`, it looks up
the handling function for the request's method, maps the request's parameters
to the function's arguments, calls the function, and captures the result or error 
returned from the function.

```zig
{
    var registry = zigjr.RpcRegistry.init(alloc);
    defer registry.deinit();

    try registry.add("add", addTwoNums);
    try registry.add("sub", subTwoNums);
    ...
    const dispatcher = zigjr.RequestDispatcher.impl_by(&registry);
    ...
}
```

### Custom Dispatcher
Custom dispatcher can be used as long as it implements the `dispatch()` and `dispatchEnd()` functions of
`RequestDispatcher`.  See the example dispatcher_hello.zig for detail.

### Request Invocation and Cleanup

Each request invocation to a dispatcher has two phases: calling `dispatcher.dispatch()` and calling
`dispatcher.dispatchEnd()`. A dispatcher's `dispatch()` performs the message dispatching
and `dispatchEnd()` does per-invocation cleanup.

### Handler Functions
Message handler functions are native Zig functions.

#### Scopes
Handler functions can be in the global scope, in a struct scope, or in a struct instance scope.

For struct instance scope, pass the struct instance as the context pointer when registering the handler function.
The context pointer is passed back as the first parameter to the handler function when invoked.

```zig
{
    try registry.add("global-fn", global_fn);
    try registry.add("group-fn", Group.group_fn);
    ...
    var counter = Counter{};
    try registry.addCtx("counter-inc", &counter, Counter.inc);
    try registry.addCtx("counter-get", &counter, Counter.get);
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
#### Parameters
The parameters of handler functions are of native Zig data types, with a few limitations.

One limitation is the parameter data types should match the JSON data types.
- bool, mapped to JavaScript's Boolean
- i64, mapped to JavaScript's signed 53-bit Integer type
- f64, mapped to JavaScript's 64-bit floating number
- []const u8, mapped to JavaScript's String
- struct, mapped to JavaScript's Object
There're some light automatic type conversion when the function parameter's type
and the JSON message's parameter type are closely related. (See `ValueAs()` in json_call.zig for details).

Another limitation is that for struct parameters they have to be parsable from JSON.
When a JSON message's parameter is a JSON object, the matching handler function's parameter
should have the same fields and data types for the JSON object. 
ZigJR uses the `std.json` package for parsing.

Nested objects are supported as long as they can be parsed to JSON. 
Custom parsing can be done via adding the `jsonParseFromValue()` to the struct. See std.json for detail.

#### Special Parameters

##### Context

If an object pointer is supplied to RpcRegistry.addCtx() as the context,
it is passed in as the first parameter to the handler function. The context
object can serve as the 'self' pointer for the function.
The first parameter's type and the context type need to be the same.

##### Allocator

If an Allocator parameter is declared as the first parameter of a handler function
(or the second parameter if a context object is supplied), an allocator is passed in
during function invocation.  The allocator is an arena allocator so the function 
doesn't need to worry about freeing the memory.  The arena memory is reset via 
the reset() function. The arena memory is reset in dispatchEnd() by higher level callers.

##### Value

If `std.json.Value` is declared as a single parameter of the handler function,
all the JSON-RPC parameters are passed in as a Value object (as an `array` or an `object`) 
without any interpretation.  It's up to the function to interpret the value types
and extract the value data. E.g.
```zig 
    fn h1(a: std.json.Value) {
    }
```

If `std.json.Value` is declared as part of the parameters of the handler function,
the JSON-RPC parameters of the correponding Value type function parameters are passed in
as Value objects without any interpretation. E.g.

```zig
    fn h3(a: std.json.Value, b: i64, c: std.json.Value) {
    }
```

#### Return Value
The return value of a handler function will be returned as the `result` of a JSON-RPC 
Response message in JSON form. The data type of a handler function can be any Zig 
data type as long as it can be stringified to JSON. Some data types are automatically 
converted so it's best to use data types that the clients expect.

If the function has already stringified its return value as JSON string, it can
use zigjr.JsonStr as return type to prevent it from being stringified again.

A `void` return type would not return any JSON-RPC Response message. It's used for 
JSON-RPC Notification, which should not generate any response.

#### Error
Error union set can be declared as part of the handler function's return type.
Any error returned will be packaged as a JSON-RPC error message with the 
`InternalError` error code.

#### Memory Management
Handler functions using `RpcRegistry` as a dispatcher has a simple memory usage policy.
Any memory allocated with the passed in `Allocator` will be freed automatically at the
end of the message dispatching. Handlers don't need to worry about memory management.

Memory is freed in the `dispatcher.dispatchEnd()` phase. Customer dispatchers need to manage
the memory themselves.

## Logging

Logging is a great way to learn about a protocol by watching the messages exchanged between
the client and the server, and it's great for debugging the message handlers. 
ZigJR has logging built into the library. It has pre-built loggers that logs to file or logs to StdErr.
Custom logger can be built easily by implementing a few methods for the Logger interface.

Use DbgLogger in a request pipeline.
```zig
    var logger = zigjr.DbgLogger{};
    const pipeline = zigjr.pipeline.RequestPipeline.init(alloc, 
        RequestDispatcher.impl_by(&registry), zigjr.Logger.impl_by(&logger));
    
```
Use FileLogger in a request stream.
```zig
    var logger = try zigjr.FileLogger.init("log.txt");
    defer logger.deinit();
    try zigjr.stream.requestsByDelimiter(alloc,
        std.io.getStdIn().reader(), std.io.getStdOut().writer(),
        dispatcher, .{ .logger = Logger.impl_by(&logger) });
```
Use a custom logger in a request pipeline.
```zig
{
    var logger = MyLogger{};
    const pipeline = zigjr.pipeline.RequestPipeline.init(alloc, 
        RequestDispatcher.impl_by(&registry), zigjr.Logger.impl_by(&logger));
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

## Standalone Build

You don't need to build the project if you just use the library via `zig fetch`.
You might want to build the project for running the examples.
Git clone the repository, then run the `zig build` command.
The binary output is in zig-out/bin/, which consists of the examples mostly.

### Running the Examples

#### Interactive Run
Running the programs interactively is a great way to debug the message handlers.
Just type in the JSON requests and see the result.
```
zig-out/bin/hello
```
The program reads from stdin. Type the following (or copy and paste), and hit Enter.
```
{"jsonrpc": "2.0", "method": "hello", "id": 1}
```
It should return the result JSON.
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
#### Run with Data Files

Runs the examples with piping the test data files from stdin.
Running the programs with data files is a great way to have repeatable tests.
```
zig-out/bin/hello < data/hello.json
zig-out/bin/hello < data/hello_name.json
zig-out\bin/hello < data/hello_xtimes.json
zig-out/bin/hello < data/hello_say.json
zig-out/bin/hello < data/hello_stream.json
```

Some more sample data files.  Examine the data files in the `data` directory to 
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



## License

ZigJR is [MIT licensed](./LICENSE).

## Further Reading

For reference information, check out these resources:

- [JSON-RPC 2.0 Specification](https://www.jsonrpc.org/specification)
- [MCP Schema](https://github.com/modelcontextprotocol/modelcontextprotocol/tree/main/schema)

