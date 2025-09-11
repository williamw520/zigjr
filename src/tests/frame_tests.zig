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
        var frame_data = frame.FrameData.init(alloc);
        defer frame_data.deinit();
        const frame_text =
            \\Content-Length: 30
            \\Header1: abc   
            \\  Header2: Xyz
            ++ "\r\n\r\n" ++
            \\content-data
            \\more content-data
        ;
        // std.debug.print("frame_text: {s}\n", .{frame_text});
        var input_reader = std.Io.Reader.fixed(frame_text);
        try frame.readHttpHeaders(&input_reader, &frame_data);

        // for (0..frame_data.headerCount())|idx| {
        //     const key = frame_data.headerKey(idx);
        //     const value = frame_data.headerValue(idx);
        //     std.debug.print("key: '{s}', value: '{s}'\n", .{ key, value });
        // }
        try testing.expectEqualStrings(frame_data.findHeader("Content-Length").?, "30");
        try testing.expectEqualStrings(frame_data.findHeader("Header1").?, "abc");
        try testing.expectEqualStrings(frame_data.findHeader("Header2").?, "Xyz");
        try testing.expect(frame_data.content_length == 30);

        var input_reader2 = std.Io.Reader.fixed(frame_text);
        frame_data.reset();
        const has_more1 = try frame.readContentLengthFrame(&input_reader2, &frame_data);
        try testing.expect(has_more1);
        // std.debug.print("content: |{s}|\n", .{frame_data.getContent()});
        try testing.expectEqualStrings(frame_data.getContent(),
                                       \\content-data
                                       \\more content-data
                                       );
        // frame_data.reset();
        // const has_more2 = try frame.readContentLengthFrame(&input_reader2, &frame_data);
        // try testing.expect(!has_more2);
        // std.debug.print("content: |{s}|\n", .{frame_data.getContent()});
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
        
}

test "writeContentLengthFrame" {
    const alloc = gpa.allocator();
    {
        var w = std.Io.Writer.Allocating.init(alloc);
        defer w.deinit();
        try frame.writeContentLengthFrame(&w.writer, "abc");
        try testing.expectEqualStrings(w.written(),
                                       "Content-Length: 3\r\n\r\nabc");
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
        
}

test "writeContentLengthFrames" {
    const alloc = gpa.allocator();
    {
        const data = [_][]const u8{
            \\abc
                ,
            \\efgh
                ,
            \\ijk
        };

        var w = std.Io.Writer.Allocating.init(alloc);
        defer w.deinit();
        try frame.writeContentLengthFrames(&w.writer, &data);
        try testing.expectEqualStrings(w.written(),
                                       "Content-Length: 3\r\n\r\nabc" ++
                                       "Content-Length: 4\r\n\r\nefgh" ++
                                       "Content-Length: 3\r\n\r\nijk"
                                       );
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
        
}
    
