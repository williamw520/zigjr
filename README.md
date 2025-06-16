# ZigJR - JSON-RPC 2.0 Library for Zig

ZigJR is a Zig library for building applications using the JSON-RPC 2.0 protocol.
It has implemented the full spec of the JSON-RPC 2.0 for low level communication.
It has enhanced support for higher level message-frame protocols for message streaming.
In addition it has a smart function dispatcher that can dispatch RPC requests to 
Zig functions in native data types, making development of RPC handlers easy.

This small library is packed with the following features:

* Parsing and building of JSON-RPC 2.0 messages.
* Support Request, Response, Notification, and Error in JSON-RPC 2.0.
* Support batch requests and batch responses in JSON-RPC 2.0.
* Message streaming via delimiter based stream ('\n' or others).
* Message streaming via Content-Length header based stream.
* RPC handling pipeline from request to response, vice versa.
* RPC registry that dispatches RPC messages to Zig functions in native data.
* A versatile logging mechanism for inspecting the JSON-RPC messages.

## Content

* [Installation](#installation)
* [Usage](#usage)
  * [Memory Ownership](#memory-ownership)
  * [Configuration](#configuration)
  * [More Usage](#more-usage)
* [CLI Tool](#command-line-tool)
* [License](#license)

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

ZigJR allows the building of JSON-RPC applications at different levels.

- At the lower protocol level, it provides parsers and builders to parse and to build the JSON messages. 
- At the RPC level, it provides a RPC handling pipeline for handling an individual request.
- At the message-frame level, it provides the handling of a stream of requests from reader 
and sending responses to writer.

Separately the library provides a dispatching RPC registry to host a group
of handling functions for handling different RPC messages. It can be used
with the single message handling or the stream based message handling.

The following example uses the stream based messaging plus the dispatching registry.
It's the simplest usage.

### Stream Based with RpcRegistry.
```zig
const zigjr = @import("zigjr");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    // Create a registry for the JSON-RPC handlers.
    var handlers = zigjr.RpcRegistry.init(alloc);
    defer handlers.deinit();

    // Register each RPC method with a handling function.
    try handlers.register("hello", null, hello);
    try handlers.register("hello-name", null, helloName);
    try handlers.register("say", null, say);

    // Implement the RequestDispatcher interface by the 'handlers' registry.
    const dispatcher = zigjr.RequestDispatcher.impl_by(&handlers);

    // Read requests from stdin, dispatch to handlers, and write responses to stdout.
    const ds = zigjr.DelimiterStream.init(alloc, .{});
    try ds.streamRequests(std.io.getStdIn().reader(), std.io.getStdOut().writer(), dispatcher);
}
```
The RPC handlers are normal Zig functions with native data type parameters and return values.
(With some limitations, i.e. they should correspond to the JSON data types.)
```zig
// A handler with no parameter and returns a string.
fn hello() []const u8 {
    return "Hello world";
}

// A handler takes in a string parameter and returns a string with error.
// It also asks the library for an allocator, which is passed in automatically.
// Allocated memory is freed automatically, making memory usage simple.
fn helloName(alloc: Allocator, name: [] const u8) ![]const u8 {
    return try std.fmt.allocPrint(alloc, "Hello {s}", .{name});
}

// This one takes one more parameter. Note that i64 is JSON's integer type.
fn helloXTimes(alloc: Allocator, name: [] const u8, times: i64) ![]const u8 {
    const repeat: usize = if (0 < times and times < 100) @intCast(times) else 1;
    var buf = std.ArrayList(u8).init(alloc);
    var writer = buf.writer();
    for (0..repeat) |_| try writer.print("Hello {s}! ", .{name});
    return buf.items;
}

// A handler takes in a string and has no return value, for RPC notification.
fn say(msg: [] const u8) void {
    std.debug.print("Message to say: {s}\n", .{msg});
}
```
See [hello](src/examples/hello.zig) for a running example. 
See below [Running the Examples](#running-the-examples) on how to run it with test data.

### Logging

Logging is a great way to learn about a protocol by watching the messages exchanged between
the client and the server. It's indispensable for debugging the message handlers, to see
what parameters are going in and what results coming out. ZigJR has logging built into
the library. It has a pre-built logger logging to file and a pre-built logger logging to stderr.
You can also build your own logger easily by implementing a few methods for the Logger interface.




## Standalone Build

Normally you don't need to build the project if you just use the library.
You might want to build the project for running the examples.
Git clone the repository, then run the `zig build` command.
The binary output is in zig-out/bin/, which consists of the examples mostly.

```
zig build
```

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

