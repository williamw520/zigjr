const std = @import("std");
const testing = std.testing;
const allocPrint = std.fmt.allocPrint;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const nanoTimestamp = std.time.nanoTimestamp;
const Value = std.json.Value;

const zigjr = @import("../zigjr.zig");
const RpcRequestMessage = zigjr.RpcRequestMessage;
const RpcRequest = zigjr.RpcRequest;
const RpcResponse = zigjr.RpcResponse;
const RpcMessageResult = zigjr.RpcRequest;
const RequestDispatcher = zigjr.RequestDispatcher;
const ResponseDispatcher = zigjr.ResponseDispatcher;
const DispatchResult = zigjr.DispatchResult;
const ErrorCode = zigjr.ErrorCode;
const JrErrors = zigjr.JrErrors;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};


test "Parsing valid request, single integer param, integer id" {
    const alloc = gpa.allocator();
    {
        var msg_result = zigjr.parseRpcMessage(alloc,
            \\{"jsonrpc": "2.0", "method": "fun0", "params": [42], "id": 1}
        );
        defer msg_result.deinit();
        var result = msg_result.request_result;
        const req = try result.request();
        try testing.expect(@TypeOf(result.request_msg) == RpcRequestMessage);
        try testing.expect(result.request_msg == .request);
        switch (result.request_msg) {
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
        try testing.expect(req.id.eql(1));
        try testing.expect(req.hasError() == false);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parsing valid request, single string param, string id" {
    const alloc = gpa.allocator();
    {
        var msg_result = zigjr.parseRpcMessage(alloc,
            \\{"jsonrpc": "2.0", "method": "fun1", "params": ["FUN1"], "id": "1"}
        );
        defer msg_result.deinit();
        var result = msg_result.request_result;
        const req = try result.request();
        try testing.expect(@TypeOf(result.request_msg) == RpcRequestMessage);
        try testing.expect(result.request_msg == .request);
        switch (result.request_msg) {
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
        try testing.expect(req.id.eql("1"));
        try testing.expect(req.id.eql([_]u8{'1'}));
        try testing.expect(req.hasError() == false);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}



const HelloDispatcher = struct {
    pub fn dispatch(_: *@This(), _: Allocator, req: RpcRequest) !DispatchResult {
        if (std.mem.eql(u8, req.method, "hello")) {
            return .{
                .result = "\"hello back\"",
            };
        } else {
            return .{
                .err = .{
                    .code = ErrorCode.MethodNotFound,
                    .msg = "Method not found.",
                }
            };
        }
    }

    pub fn dispatchEnd(_: *@This(), _: Allocator, _: RpcRequest, dresult: DispatchResult) void {
        // All result data are constant strings.  Nothing to free.
        switch (dresult) {
            .none => {},
            .result => {},
            .err => {},
        }
    }
};


test "Parse response to a request of hello method via " {
    const alloc = gpa.allocator();
    {
        var impl = HelloDispatcher{};
        var pipeline = zigjr.pipeline.RequestPipeline.init(alloc, RequestDispatcher.implBy(&impl), null);
        defer pipeline.deinit();

        const res_json = try pipeline.runRequestToJson(alloc, 
            \\{"jsonrpc": "2.0", "method": "hello", "params": [42], "id": 1}
        );
        defer if (res_json)|json| alloc.free(json);
        
        var msg_result = zigjr.parseRpcMessage(alloc, res_json.?);
        defer msg_result.deinit();
        var parsed_res = msg_result.response_result;
        const res = try parsed_res.response();
        // std.debug.print("res.result: {s}\n", .{res.result.string});

        try testing.expectEqualSlices(u8, res.result.string, "hello back");
        try testing.expect(res.resultEql("hello back"));
        try testing.expect(res.id.eql(1));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse error from a request of unknown method, expect error" {
    const alloc = gpa.allocator();
    {
        var impl = HelloDispatcher{};
        var pipeline = zigjr.pipeline.RequestPipeline.init(alloc, RequestDispatcher.implBy(&impl), null);
        defer pipeline.deinit();

        const res_json = try pipeline.runRequestToJson(alloc, 
            \\{"jsonrpc": "2.0", "method": "non-hello", "params": [42], "id": 1}
        );
        defer if (res_json)|json| alloc.free(json);

        var msg_result = zigjr.parseRpcMessage(alloc, res_json.?);
        defer msg_result.deinit();
        var parsed_res = msg_result.response_result;
        const res = try parsed_res.response();

        try testing.expect(res.hasErr());
        try testing.expectEqual(res.err().code, @intFromEnum(ErrorCode.MethodNotFound));
        try testing.expect(res.id.eql(1));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}


test "Dispatch on the request and response" {
    const alloc = gpa.allocator();
    {
        var req_dispatcher = HelloDispatcher{};

        var res_dispatcher = struct {
            pub fn dispatch(_: *@This(), _: Allocator, res: RpcResponse) anyerror!void {
                // std.debug.print("response: {any}\n", .{res});
                try testing.expectEqualSlices(u8, res.result.string, "hello back");
                try testing.expect(res.id.eql(1));
            }
        } {};

        var pipeline = zigjr.pipeline.MessagePipeline.init(alloc, RequestDispatcher.implBy(&req_dispatcher),
                                                           ResponseDispatcher.implBy(&res_dispatcher),
                                                           null);
        defer pipeline.deinit();

        var response_buf = std.Io.Writer.Allocating.init(alloc);
        defer response_buf.deinit();
        const run_req_result = try pipeline.runMessage(alloc,
            \\{"jsonrpc": "2.0", "method": "hello", "params": [42], "id": 1}
            , &response_buf.writer, .{});
        try testing.expect(run_req_result == .request_has_response);
        // std.debug.print("run_result: {}\n", .{run_result});
        // std.debug.print("response_buf: {s}\n", .{response_buf.items});

        // Feed the response from request back into the message pipeline.
        var response_buf2 = std.Io.Writer.Allocating.init(alloc);
        defer response_buf2.deinit();
        const run_res_result = try pipeline.runMessage(alloc, response_buf.written(),
                                                       &response_buf2.writer, .{});
        try testing.expect(run_res_result == .response_processed);

    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

