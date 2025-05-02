const std = @import("std");
const testing = std.testing;
const allocPrint = std.fmt.allocPrint;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const nanoTimestamp = std.time.nanoTimestamp;
const Value = std.json.Value;
const Array = std.json.Array;
const ObjectMap = std.json.ObjectMap;

const zigjr = @import("../zigjr.zig");
const RpcRequestMessage = zigjr.RpcRequestMessage;
const RpcRequest = zigjr.RpcRequest;
const ErrorCode = zigjr.ErrorCode;
const JrErrors = zigjr.JrErrors;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};


test "Parsing valid request, single integer param, integer id" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\{"jsonrpc": "2.0", "method": "fun0", "params": [42], "id": 1}
                                        );
        defer result.deinit();
        const req = try result.request();
        try testing.expect(@TypeOf(result.rpcmsg) == RpcRequestMessage);
        try testing.expect(result.rpcmsg == .request);
        switch (result.rpcmsg) {
            .request    => |r| { _=r; try testing.expect(true);  },
            .batch      => |b| { _=b; try testing.expect(false); },
        }
        try testing.expect(result.isRequest());
        try testing.expect(!result.isBatch());
        try testing.expect(result.batch() == JrErrors.NotBatchRpcRequest);
        try testing.expect(std.mem.eql(u8, &req.jsonrpc, "2.0"));
        try testing.expect(std.mem.eql(u8, req.method, "fun0"));
        try testing.expect(req.hasParams());
        try testing.expect(req.params == .array);
        try testing.expect(req.params.array.items.len == 1);
        try testing.expect(req.params.array.items[0].integer == 42);
        try testing.expect(req.hasArrayParams());
        try testing.expect(!req.hasObjectParams());
        try testing.expect(req.arrayParams()  != null);
        try testing.expect(req.objectParams() == null);
        try testing.expect(req.arrayParams().?.items.len == 1);
        try testing.expect(req.arrayParams().?.items[0].integer == 42);
        try testing.expect(req.id.isValid());
        try testing.expect(req.id.num == 1);
        try testing.expect(req.hasError() == false);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parsing valid request, single string param, string id" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\{"jsonrpc": "2.0", "method": "fun1", "params": ["FUN1"], "id": "1"}
                                        );
        defer result.deinit();
        const req = try result.request();
        try testing.expect(@TypeOf(result.rpcmsg) == RpcRequestMessage);
        try testing.expect(result.rpcmsg == .request);
        switch (result.rpcmsg) {
            .request    => |r| { _=r; try testing.expect(true);  },
            .batch      => |b| { _=b; try testing.expect(false); },
        }
        try testing.expect(result.isRequest());
        try testing.expect(!result.isBatch());
        try testing.expect(result.batch() == JrErrors.NotBatchRpcRequest);
        try testing.expect(std.mem.eql(u8, &req.jsonrpc, "2.0"));
        try testing.expect(std.mem.eql(u8, req.method, "fun1"));
        try testing.expect(req.hasParams());
        try testing.expect(req.params == .array);
        try testing.expect(req.params.array.items.len == 1);
        try testing.expect(std.mem.eql(u8, req.params.array.items[0].string, "FUN1"));
        try testing.expect(req.hasArrayParams());
        try testing.expect(!req.hasObjectParams());
        try testing.expect(req.arrayParams()  != null);
        try testing.expect(req.objectParams() == null);
        try testing.expect(req.arrayParams().?.items.len == 1);
        try testing.expect(std.mem.eql(u8, req.arrayParams().?.items[0].string, "FUN1"));
        try testing.expect(req.id.isValid());
        try testing.expect(std.mem.eql(u8, req.id.str, "1"));
        try testing.expect(req.hasError() == false);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parsing valid request, tw0 integer params, integer id" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\{"jsonrpc": "2.0", "method": "fun1", "params": [42, 22], "id": 2}
                                        );
        defer result.deinit();
        const req = try result.request();
        try testing.expect(@TypeOf(result.rpcmsg) == RpcRequestMessage);
        try testing.expect(result.rpcmsg == .request);
        switch (result.rpcmsg) {
            .request    => |r| { _=r; try testing.expect(true);  },
            .batch      => |b| { _=b; try testing.expect(false); },
        }
        try testing.expect(result.isRequest());
        try testing.expect(!result.isBatch());
        try testing.expect(result.batch() == JrErrors.NotBatchRpcRequest);
        try testing.expect(std.mem.eql(u8, &req.jsonrpc, "2.0"));
        try testing.expect(std.mem.eql(u8, req.method, "fun1"));
        try testing.expect(req.hasParams());
        try testing.expect(req.params == .array);
        try testing.expect(req.params.array.items.len == 2);
        try testing.expect(req.params.array.items[0].integer == 42);
        try testing.expect(req.params.array.items[1].integer == 22);
        try testing.expect(req.hasArrayParams());
        try testing.expect(!req.hasObjectParams());
        try testing.expect(req.arrayParams()  != null);
        try testing.expect(req.objectParams() == null);
        try testing.expect(req.arrayParams().?.items.len == 2);
        try testing.expect(req.arrayParams().?.items[0].integer == 42);
        try testing.expect(req.arrayParams().?.items[1].integer == 22);
        try testing.expect(req.id.isValid());
        try testing.expect(req.id.num == 2);
        try testing.expect(req.hasError() == false);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parsing valid request, object params, integer id" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\{"jsonrpc": "2.0", "method": "fun_obj", "params": { "name": "foobar", "weight": 150 }, "id": 3}
                                        );
        defer result.deinit();
        const req = try result.request();
        try testing.expect(@TypeOf(result.rpcmsg) == RpcRequestMessage);
        try testing.expect(result.rpcmsg == .request);
        switch (result.rpcmsg) {
            .request    => |r| { _=r; try testing.expect(true);  },
            .batch      => |b| { _=b; try testing.expect(false); },
        }
        try testing.expect(result.isRequest());
        try testing.expect(!result.isBatch());
        try testing.expect(result.batch() == JrErrors.NotBatchRpcRequest);
        try testing.expect(std.mem.eql(u8, &req.jsonrpc, "2.0"));
        try testing.expect(std.mem.eql(u8, req.method, "fun_obj"));
        try testing.expect(req.hasParams());
        try testing.expect(req.params == .object);
        try testing.expect(std.mem.eql(u8, req.params.object.get("name").?.string, "foobar"));
        try testing.expect(req.params.object.get("weight").?.integer == 150);
        try testing.expect(!req.hasArrayParams());
        try testing.expect(req.hasObjectParams());
        try testing.expect(req.arrayParams()  == null);
        try testing.expect(req.objectParams() != null);
        try testing.expect(std.mem.eql(u8, req.objectParams().?.get("name").?.string, "foobar"));
        try testing.expect(req.objectParams().?.get("weight").?.integer == 150);
        try testing.expect(req.id.isValid());
        try testing.expect(req.id.num == 3);
        try testing.expect(req.hasError() == false);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse valid request, with 0 params, with no id" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\{"jsonrpc": "2.0", "method": "fun0", "params": [] }
                                        );
        defer result.deinit();
        const req = try result.request();
        try testing.expect(@TypeOf(result.rpcmsg) == RpcRequestMessage);
        try testing.expect(result.rpcmsg == .request);
        switch (result.rpcmsg) {
            .request    => |r| { _=r; try testing.expect(true);  },
            .batch      => |b| { _=b; try testing.expect(false); },
        }
        try testing.expect(result.isRequest());
        try testing.expect(!result.isBatch());
        try testing.expect(result.batch() == JrErrors.NotBatchRpcRequest);
        try testing.expect(std.mem.eql(u8, &req.jsonrpc, "2.0"));
        try testing.expect(std.mem.eql(u8, req.method, "fun0"));
        try testing.expect(req.hasParams());
        try testing.expect(req.params == .array);
        try testing.expect(req.params.array.items.len == 0);
        try testing.expect(req.hasArrayParams());
        try testing.expect(!req.hasObjectParams());
        try testing.expect(req.arrayParams()  != null);
        try testing.expect(req.objectParams() == null);
        try testing.expect(req.arrayParams().?.items.len == 0);
        try testing.expect(!req.id.isValid());
        try testing.expect(req.id == zigjr.RpcId.none);
        try testing.expect(req.hasError() == false);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse valid request, with no params, with no id" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\{"jsonrpc": "2.0", "method": "fun0" }
                                        );
        defer result.deinit();
        const req = try result.request();
        // std.debug.print("Request: {any}\n", .{req});
        try testing.expect(@TypeOf(result.rpcmsg) == RpcRequestMessage);
        try testing.expect(result.rpcmsg == .request);
        switch (result.rpcmsg) {
            .request    => |r| { _=r; try testing.expect(true);  },
            .batch      => |b| { _=b; try testing.expect(false); },
        }
        try testing.expect(result.isRequest());
        try testing.expect(!result.isBatch());
        try testing.expect(result.batch() == JrErrors.NotBatchRpcRequest);
        try testing.expect(std.mem.eql(u8, &req.jsonrpc, "2.0"));
        try testing.expect(std.mem.eql(u8, req.method, "fun0"));
        try testing.expect(!req.hasParams());
        try testing.expect(req.params == .null);
        try testing.expect(!req.hasArrayParams());
        try testing.expect(!req.hasObjectParams());
        try testing.expect(req.arrayParams()  == null);
        try testing.expect(req.objectParams() == null);
        try testing.expect(!req.id.isValid());
        try testing.expect(req.id == zigjr.RpcId.none);
        try testing.expect(req.hasError() == false);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse valid request, with no params, with null id" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\{"jsonrpc": "2.0", "method": "fun0", "id": null }
                                        );
        defer result.deinit();
        const req = try result.request();
        try testing.expect(!req.hasError());
        try testing.expect(!req.id.isValid());
        try testing.expect(req.id == .null);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse valid request, with no params, with string id" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\{"jsonrpc": "2.0", "method": "fun0", "id": "5a" }
                                        );
        defer result.deinit();
        const req = try result.request();
        try testing.expect(!req.hasError());
        try testing.expect(req.id.isValid());
        try testing.expect(std.mem.eql(u8, req.id.str, "5a"));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse valid request batch, with no params, with string id" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\[ {"jsonrpc": "2.0", "method": "fun0", "id": "5a" },
                                            \\  {"jsonrpc": "2.0", "method": "fun0", "id": "5b" } ]
                                        );
        defer result.deinit();
        try testing.expect(result.isBatch());
        try testing.expect(!result.isRequest());
        const reqs = try result.batch();
        try testing.expect(reqs.len == 2);
        try testing.expect(!reqs[0].hasError());
        try testing.expect(!reqs[1].hasError());
        try testing.expect(reqs[0].id.isValid());
        try testing.expect(reqs[1].id.isValid());
        try testing.expect(std.mem.eql(u8, reqs[0].id.str, "5a"));
        try testing.expect(std.mem.eql(u8, reqs[1].id.str, "5b"));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}



// Testing parsing errors and invalid requests.

test "Parse empty request, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\
                                        );
        defer result.deinit();
        const req = try result.request();
        try testing.expect(req.hasError());
        try testing.expect(req.err.code == ErrorCode.InvalidRequest);
        try testing.expect(req.isError(ErrorCode.InvalidRequest));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse incomplete opening request {, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\{
                                        );
        defer result.deinit();
        const req = try result.request();
        try testing.expect(req.hasError());
        try testing.expect(req.err.code == ErrorCode.InvalidRequest);
        try testing.expect(req.isError(ErrorCode.InvalidRequest));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse incomplete closing request }, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\}
                                        );
        defer result.deinit();
        // std.debug.print("Error {}, {s}\n", .{(try result.request()).err.code, (try result.request()).err.err_msg});
        try testing.expect((try result.request()).err.code == ErrorCode.ParseError);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse empty object request {}, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\{}
                                        );
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.InvalidRequest);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse invalid syntax request, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\ foo abc 123
                                        );
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.ParseError);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse incomplete missing value request, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\{"foo":
                                        );
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.InvalidRequest);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse missing value request, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\{"foo": }
                                        );
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.InvalidRequest);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse missing value for 'jsonrpc' property, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\{"jsonrpc": }
                                        );
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.ParseError);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse incomplete jsonrpc request 'jsonrpc' only, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\{"jsonrpc": "2.0"}
                                        );
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.InvalidRequest);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse duplicate 'params' properties, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\{"jsonrpc": "2.0", "methodx": "foobar", "params": [], "id": "4"}
                                        );
        defer result.deinit();
        // try testing.expect((try result.request()).err.code == ErrorCode.InvalidRequest);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse invalid jsonrpc version 0.0, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\{"jsonrpc": "0.0", "method": "foobar", "params": [], "id": "5"}
                                        );
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.InvalidRequest);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse invalid jsonrpc version 1.0, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\{"jsonrpc": "1.0", "method": "foobar", "params": [], "id": "5"}
                                        );
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.InvalidRequest);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse invalid jsonrpc version 3.0, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\{"jsonrpc": "3.0", "method": "foobar", "params": [], "id": "5"}
                                        );
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.InvalidRequest);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse empty method, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\{"jsonrpc": "2.0", "method": ""}
                                        );
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.InvalidRequest);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse non-object nor non-array params '1234', expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\{"jsonrpc": "2.0", "method": "foobar", "params": 1234, "id": "5d"}
                                        );
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.InvalidParams);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse non-object nor non-array params 'abcd', expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\{"jsonrpc": "2.0", "method": "foobar", "params": "abcd", "id": "5d"}
                                        );
        defer result.deinit();
        // std.debug.print("Request: {any}\n", .{try result.request()});
        try testing.expect((try result.request()).err.code == ErrorCode.InvalidParams);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

// Test parseRequestReader

test "Parsing valid request with parseRequestReader, single integer param, integer id" {
    const alloc = gpa.allocator();
    {
        var json_stream = std.io.fixedBufferStream(
            \\{"jsonrpc": "2.0", "method": "fun0", "params": [42], "id": 1}
        );
        const json_reader = json_stream.reader();
        var result = zigjr.parseRequestReader(alloc, json_reader);
        defer result.deinit();
        const req = try result.request();
        try testing.expect(@TypeOf(result.rpcmsg) == RpcRequestMessage);
        try testing.expect(result.rpcmsg == .request);
        switch (result.rpcmsg) {
            .request    => |r| { _=r; try testing.expect(true);  },
            .batch      => |b| { _=b; try testing.expect(false); },
        }
        try testing.expect(result.isRequest());
        try testing.expect(!result.isBatch());
        try testing.expect(result.batch() == JrErrors.NotBatchRpcRequest);
        try testing.expect(std.mem.eql(u8, &req.jsonrpc, "2.0"));
        try testing.expect(std.mem.eql(u8, req.method, "fun0"));
        try testing.expect(req.hasParams());
        try testing.expect(req.params == .array);
        try testing.expect(req.params.array.items.len == 1);
        try testing.expect(req.params.array.items[0].integer == 42);
        try testing.expect(req.hasArrayParams());
        try testing.expect(!req.hasObjectParams());
        try testing.expect(req.arrayParams()  != null);
        try testing.expect(req.objectParams() == null);
        try testing.expect(req.arrayParams().?.items.len == 1);
        try testing.expect(req.arrayParams().?.items[0].integer == 42);
        try testing.expect(req.id.isValid());
        try testing.expect(req.id.num == 1);
        try testing.expect(req.hasError() == false);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parsing valid request with parseRequestReader, single string param, string id" {
    const alloc = gpa.allocator();
    {
        var json_stream = std.io.fixedBufferStream(
            \\{"jsonrpc": "2.0", "method": "fun1", "params": ["FUN1"], "id": "1"}
        );
        const json_reader = json_stream.reader();
        var result = zigjr.parseRequestReader(alloc, json_reader);
        defer result.deinit();
        const req = try result.request();
        try testing.expect(@TypeOf(result.rpcmsg) == RpcRequestMessage);
        try testing.expect(result.rpcmsg == .request);
        switch (result.rpcmsg) {
            .request    => |r| { _=r; try testing.expect(true);  },
            .batch      => |b| { _=b; try testing.expect(false); },
        }
        try testing.expect(result.isRequest());
        try testing.expect(!result.isBatch());
        try testing.expect(result.batch() == JrErrors.NotBatchRpcRequest);
        try testing.expect(std.mem.eql(u8, &req.jsonrpc, "2.0"));
        try testing.expect(std.mem.eql(u8, req.method, "fun1"));
        try testing.expect(req.hasParams());
        try testing.expect(req.params == .array);
        try testing.expect(req.params.array.items.len == 1);
        try testing.expect(std.mem.eql(u8, req.params.array.items[0].string, "FUN1"));
        try testing.expect(req.hasArrayParams());
        try testing.expect(!req.hasObjectParams());
        try testing.expect(req.arrayParams()  != null);
        try testing.expect(req.objectParams() == null);
        try testing.expect(req.arrayParams().?.items.len == 1);
        try testing.expect(std.mem.eql(u8, req.arrayParams().?.items[0].string, "FUN1"));
        try testing.expect(req.id.isValid());
        try testing.expect(std.mem.eql(u8, req.id.str, "1"));
        try testing.expect(req.hasError() == false);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse missing value request with parseRequestReader, expect error." {
    const alloc = gpa.allocator();
    {
        var json_stream = std.io.fixedBufferStream(
            \\{"foo": }
        );
        const json_reader = json_stream.reader();
        var result = zigjr.parseRequestReader(alloc, json_reader);
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.InvalidRequest);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse empty method with parseRequest, expect error." {
    const alloc = gpa.allocator();
    {
        var json_stream = std.io.fixedBufferStream(
            \\{"jsonrpc": "2.0", "method": ""}
        );
        const json_reader = json_stream.reader();
        var result = zigjr.parseRequestReader(alloc, json_reader);
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.InvalidRequest);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse valid request and get as a batch, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\{"jsonrpc": "2.0", "method": "fun0", "id": "5a" }
                                        );
        try testing.expect(!result.isBatch());
        try testing.expect(result.isRequest());
        defer result.deinit();
        try testing.expect(result.batch() == JrErrors.NotBatchRpcRequest);

    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse valid request batch and get as a request, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
                                        \\[ {"jsonrpc": "2.0", "method": "fun0", "id": "5a" },
                                        \\  {"jsonrpc": "2.0", "method": "fun0", "id": "5b" } ]
                                        );
        try testing.expect(result.isBatch());
        try testing.expect(!result.isRequest());
        try testing.expect(result.isBatch());
        defer result.deinit();
        try testing.expect(result.request() == JrErrors.NotSingleRpcRequest);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}


test "Build request json with no params and none Id." {
    const alloc = gpa.allocator();
    {
        const req_json = try zigjr.requestJson(alloc, "foobar", null, zigjr.RpcId.none);
        defer alloc.free(req_json);
        // std.debug.print("req_json {s}\n", .{req_json});
        try testing.expectEqualSlices(u8, req_json,
                                      \\{ "jsonrpc": "2.0", "method": "foobar" }
                                      );
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Build request json with no params and null Id." {
    const alloc = gpa.allocator();
    {
        const req_json = try zigjr.requestJson(alloc, "foobar", null, zigjr.RpcId.null);
        defer alloc.free(req_json);
        // std.debug.print("req_json {s}\n", .{req_json});
        try testing.expectEqualSlices(u8, req_json,
                                      \\{ "jsonrpc": "2.0", "method": "foobar", "id": null }
                                      );
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Build request json with no params and integer Id." {
    const alloc = gpa.allocator();
    {
        const req_json = try zigjr.requestJson(alloc, "foobar", null, .{ .num = 1 });
        defer alloc.free(req_json);
        // std.debug.print("req_json {s}\n", .{req_json});
        try testing.expectEqualSlices(u8, req_json,
                                      \\{ "jsonrpc": "2.0", "method": "foobar", "id": 1 }
                                      );
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Build request json with no params and string Id." {
    const alloc = gpa.allocator();
    {
        const req_json = try zigjr.requestJson(alloc, "foobar", null, .{ .str = "1" });
        defer alloc.free(req_json);
        // std.debug.print("req_json {s}\n", .{req_json});
        try testing.expectEqualSlices(u8, req_json,
                                      \\{ "jsonrpc": "2.0", "method": "foobar", "id": "1" }
                                      );
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Build request json with array params and none Id." {
    const alloc = gpa.allocator();
    {
        const req_json = try zigjr.requestJson(alloc, "foobar", [_]i64{1, 2}, .{ .none = {} });
        defer alloc.free(req_json);
        // std.debug.print("req_json {s}\n", .{req_json});
        try testing.expectEqualSlices(u8, req_json,
                                      \\{ "jsonrpc": "2.0", "method": "foobar", "params": [1,2] }
                                      );
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

const  ParamsTest = struct {
    a: u8  = 1,
    b: i16 = 2,
};

test "Build request json with object params and none Id." {
    const alloc = gpa.allocator();
    {
        const req_json = try zigjr.requestJson(alloc, "foobar", ParamsTest{}, .{ .none = {} });
        defer alloc.free(req_json);
        // std.debug.print("req_json {s}\n", .{req_json});
        try testing.expectEqualSlices(u8, req_json,
                                      \\{ "jsonrpc": "2.0", "method": "foobar", "params": {"a":1,"b":2} }
                                      );
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Build request json with array params and null Id." {
    const alloc = gpa.allocator();
    {
        const req_json = try zigjr.requestJson(alloc, "foobar", [_]i64{1, 2}, .{ .null = {} });
        defer alloc.free(req_json);
        // std.debug.print("req_json {s}\n", .{req_json});
        try testing.expectEqualSlices(u8, req_json,
                                      \\{ "jsonrpc": "2.0", "method": "foobar", "params": [1,2], "id": null }
                                      );
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Build request json with array params and num Id." {
    const alloc = gpa.allocator();
    {
        const req_json = try zigjr.requestJson(alloc, "foobar", [_]i64{1, 2}, .{ .num = 123 });
        defer alloc.free(req_json);
        // std.debug.print("req_json {s}\n", .{req_json});
        try testing.expectEqualSlices(u8, req_json,
                                      \\{ "jsonrpc": "2.0", "method": "foobar", "params": [1,2], "id": 123 }
                                      );
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Build request json with array params and str Id." {
    const alloc = gpa.allocator();
    {
        const req_json = try zigjr.requestJson(alloc, "foobar", [_]i64{1, 2}, .{ .str = "10" });
        defer alloc.free(req_json);
        // std.debug.print("req_json {s}\n", .{req_json});
        try testing.expectEqualSlices(u8, req_json,
                                      \\{ "jsonrpc": "2.0", "method": "foobar", "params": [1,2], "id": "10" }
                                      );
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Build request json with invalid params type and none Id, expect error." {
    const alloc = gpa.allocator();
    {
        try testing.expectEqual(zigjr.requestJson(alloc, "foobar", 123, .{ .str = "10" }), JrErrors.InvalidParamsType);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}


test "Build batch request json with array params and str Id." {
    const alloc = gpa.allocator();
    {
        const req_jsons = [_][]const u8{
            try zigjr.requestJson(alloc, "foo", [_]i64{1, 2}, .{ .none = {} }),
            try zigjr.requestJson(alloc, "bar", ParamsTest{}, .{ .num = 2 }),
        };
        defer for (req_jsons)|json| alloc.free(json);

        const batch_json = try zigjr.batchJson(alloc, &req_jsons);
        defer alloc.free(batch_json);
        // std.debug.print("req_json {s}\n", .{batch_json.items});
        try testing.expectEqualSlices(u8, batch_json,
            \\[{ "jsonrpc": "2.0", "method": "foo", "params": [1,2] }, { "jsonrpc": "2.0", "method": "bar", "params": {"a":1,"b":2}, "id": 2 }]
        );

        var result = zigjr.parseRequest(alloc, batch_json);
        defer result.deinit();
        try testing.expect(result.isBatch());
        try testing.expect(!(try result.batch())[0].id.isValid());
        try testing.expectEqualSlices(u8, (try result.batch())[0].method, "foo");
        try testing.expect((try result.batch())[1].id.num == 2);
        try testing.expectEqualSlices(u8, (try result.batch())[1].method, "bar");
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

