const std = @import("std");
const Type = std.builtin.Type;
const testing = std.testing;
const allocPrint = std.fmt.allocPrint;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const nanoTimestamp = std.time.nanoTimestamp;
const Value = std.json.Value;
const Array = std.json.Array;
const frame = @import("../streaming/frame.zig");
    
var gpa = std.heap.GeneralPurposeAllocator(.{}){};


test "readHttpHeaders" {
    const alloc = gpa.allocator();
    {
        var frame_buf = frame.FrameBuf.init(alloc);
        defer frame_buf.deinit();
        const frame_data =
            \\Content-Length: 30  
            \\  Header1: abc
            ++ "\r\n\r\n" ++
            \\content-data
            \\more content-data
        ;
        // std.debug.print("frame_data: {s}\n", .{frame_data});
        var stream1 = std.io.fixedBufferStream(frame_data);

        try frame.readHttpHeaders(stream1.reader(), &frame_buf);
        // var itr = frame_buf.headers.iterator();
        // while (itr.next()) |entry| {
        //     std.debug.print("key: '{s}', value: '{s}'\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        // }        
        try testing.expectEqualStrings(frame_buf.headers.get("Content-Length").?, "30");
        try testing.expectEqualStrings(frame_buf.headers.get("Header1").?, "abc");
        try testing.expect((try frame_buf.getContentLength()) orelse 0 == 30);

        var stream2 = std.io.fixedBufferStream(frame_data);
        frame_buf.reset();
        const has_more1 = try frame.readContentLengthFrame(stream2.reader(), &frame_buf);
        try testing.expect(has_more1);
        std.debug.print("content: |{s}|\n", .{frame_buf.getContent()});

        frame_buf.reset();
        const has_more2 = try frame.readContentLengthFrame(stream2.reader(), &frame_buf);
        try testing.expect(!has_more2);
        std.debug.print("content: |{s}|\n", .{frame_buf.getContent()});
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
        
}

