const std = @import("std");
const Type = std.builtin.Type;
const testing = std.testing;
const allocPrint = std.fmt.allocPrint;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const nanoTimestamp = std.time.nanoTimestamp;
const Value = std.json.Value;
const Array = std.json.Array;
const zigjr = @import("zigjr");
const frame = zigjr.frame;
// const frame = @import("../src/streaming/frame.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};


test "readHttpHeaders" {
    const alloc = gpa.allocator();
    {
        var header_buf = frame.HeaderBuf.init(alloc);
        defer header_buf.deinit();
        const frame_data =
            \\Content-Length: 29  
            \\  Header1: abc
            ++ "\r\n\r\n" ++
            \\context-data
            \\more context-data
        ;
        // std.debug.print("frame_data: {s}\n", .{frame_data});
        var frame_stream = std.io.fixedBufferStream(frame_data);

        const count = try frame.readHttpHeaders(frame_stream.reader(), &header_buf);
        // var itr = header_buf.headers.iterator();
        // while (itr.next()) |entry| {
        //     std.debug.print("key: '{s}', value: '{s}'\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        // }        
        try testing.expect(count == 2);
        try testing.expectEqualStrings(header_buf.headers.get("Content-Length").?, "29");
        try testing.expectEqualStrings(header_buf.headers.get("Header1").?, "abc");
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
        
}

