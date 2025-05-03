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


test "Parsing valid request, single integer param, integer id" {
    const alloc = gpa.allocator();
    {
        const req_jsons = 
            \\{"jsonrpc": "2.0", "method": "fun0", "id": "5a" }
            \\{"jsonrpc": "2.0", "method": "fun0", "id": "5b" }
            \\{"jsonrpc": "2.0", "method": "fun0", "id": "5c" }
            \\{"jsonrpc": "2.0", "method": "fun0", "id": "5d" }
            \\{"jsonrpc": "2.0", "method": "fun0", "id": "5e" }
            \\
        ;
        // std.debug.print("req_jsons: |{s}|\n", .{req_jsons});
        var json_stream = std.io.fixedBufferStream(req_jsons);
        const reader = json_stream.reader();

        var write_buffer = ArrayList(u8).init(alloc);
        defer write_buffer.deinit();
        const writer = write_buffer.writer();
        var buf_writer = std.io.bufferedWriter(writer);

        try ds.streamByDelimiter(alloc, '\n', reader, &buf_writer, null);

        std.debug.print("output_jsons: ##\n{s}##\n", .{write_buffer.items});
        
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

