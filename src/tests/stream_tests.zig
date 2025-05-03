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

const ds = @import("../streaming/delimiter_stream.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

const EchoDispatcher = struct {
    pub fn run(alloc: Allocator, req: RpcRequest) !zigjr.DispatchResult {
        const params = req.arrayParams() orelse
            return .{ .err = .{ .code = ErrorCode.InvalidParams } };
        if (params.items.len != 1 or params.items[0] != .string) {
            return .{ .err = .{ .code = ErrorCode.InvalidParams } };
        }

        return .{
            .result = try std.json.stringifyAlloc(alloc, params.items[0].string, .{}),
        };
    }

    pub fn free(alloc: Allocator, dresult: zigjr.DispatchResult) void {
        switch (dresult) {
            .result => |json| alloc.free(json),
            .err => {},
            .none => {},
        }
    }
};

test "Parsing valid request, single param, id" {
    const alloc = gpa.allocator();
    {
        const req_jsons = 
            \\{"jsonrpc": "2.0", "method": "fun0", "params": ["abc"], "id": "5a" }
            \\{"jsonrpc": "2.0", "method": "fun0", "params": ["xyz"],  "id": "5b" }
            \\{"jsonrpc": "2.0", "method": "fun0", "id": "5c" }
            \\
        ;
        // std.debug.print("req_jsons: |{s}|\n", .{req_jsons});
        var json_stream = std.io.fixedBufferStream(req_jsons);
        const reader = json_stream.reader();

        var write_buffer = ArrayList(u8).init(alloc);
        defer write_buffer.deinit();
        const writer = write_buffer.writer();
        var buf_writer = std.io.bufferedWriter(writer);

        try ds.streamByDelimiter(alloc, '\n', '\n', reader, &buf_writer, EchoDispatcher);
        // std.debug.print("output_jsons: ##\n{s}##\n", .{write_buffer.items});

        try testing.expectEqualSlices(u8, write_buffer.items,
            \\{ "jsonrpc": "2.0", "result": "abc", "id": "5a" }
            \\{ "jsonrpc": "2.0", "result": "xyz", "id": "5b" }
            \\{ "jsonrpc": "2.0", "id": "5c", "error": { "code": -32602, "message": "InvalidParams" } }
            \\
        );
        
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

