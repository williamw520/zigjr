// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William W. Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const BufReader = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Provides a buffered reader implementing the std.Io.Reader interface.
/// Wraps a source reader with arbitrary buffer size into a reader with your own buffer size.
/// Some std.Io.Reader operations only work against the data in its buffer and might need bigger buffer.

// The source reader to read data from.
src_reader: std.Io.Reader,
// The std.Io.Reader interface for this reader implementation.
buf_interface: std.Io.Reader,


pub fn init(alloc: Allocator, buf_size: usize, src_reader: std.Io.Reader) Allocator.Error!@This() {
    return .{
        .src_reader = src_reader,
        .buf_interface = .{
            .vtable = &.{
                .stream = streamSource,
            },
            .buffer = try alloc.alloc(u8, buf_size),
            .seek = 0,
            .end = 0,
        },
    };
}

pub fn deinit(self: *BufReader, alloc: Allocator) void {
    alloc.free(self.interface().buffer);
}


/// Get the std.Io.Reader interface pointer, to avoid an accidental copy.
pub fn interface(self: *BufReader) *std.Io.Reader {
    return &self.buf_interface;
}

pub fn getBufSize(self: *const BufReader) usize {
    return self.buf_interface.buffer.len;
}

// std.Io.Reader calls self.vtable.stream() fills its buffer.
// Reads the data from source to provide the streaming data.
fn streamSource(io_reader: *std.Io.Reader, w: *std.Io.Writer,
                limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
    const buf_reader: *BufReader = @alignCast(@fieldParentPtr("buf_interface", io_reader));
    return buf_reader.src_reader.stream(w, limit);
}


test "Test buffer size" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    // buffered size bigger than source buffer size
    {
        const src_reader: std.Io.Reader = .fixed("abc");
        var buf_reader = try BufReader.init(alloc, 80, src_reader);
        defer buf_reader.deinit(alloc);
        var br = buf_reader.interface();
        try std.testing.expectEqualStrings("a", try br.peek(1));
        try std.testing.expectEqualStrings("ab", try br.peek(2));
        try std.testing.expectEqualStrings("abc", try br.peek(3));
        var data: [1024]u8 = undefined;
        const len = try br.readSliceShort(&data);
        try std.testing.expect(len == 3);
        try std.testing.expectEqualStrings("abc", data[0..len]);
    }
    // buffered size equals to source buffer size
    {
        const src_reader: std.Io.Reader = .fixed("abc");
        var buf_reader = try BufReader.init(alloc, 3, src_reader);
        defer buf_reader.deinit(alloc);
        var br = buf_reader.interface();
        try std.testing.expectEqualStrings("a", try br.peek(1));
        try std.testing.expectEqualStrings("ab", try br.peek(2));
        try std.testing.expectEqualStrings("abc", try br.peek(3));
        var data: [1024]u8 = undefined;
        const len = try br.readSliceShort(&data);
        try std.testing.expect(len == 3);
        try std.testing.expectEqualStrings("abc", data[0..len]);
    }
    // buffered size less than source buffer size
    {
        const src_reader: std.Io.Reader = .fixed("abc");
        var buf_reader = try BufReader.init(alloc, 2, src_reader);
        defer buf_reader.deinit(alloc);
        var br = buf_reader.interface();
        try std.testing.expectEqualStrings("a", try br.peek(1));
        try std.testing.expectEqualStrings("ab", try br.peek(2));
        var data1: [1]u8 = undefined;
        const len = try br.readSliceShort(&data1);
        try std.testing.expect(len == 1);
        try std.testing.expectEqualStrings("a", data1[0..len]);

        try std.testing.expectEqualStrings("b", try br.peek(1));
        try std.testing.expectEqualStrings("bc", try br.peek(2));
        var data: [1024]u8 = undefined;
        const len2 = try br.readSliceShort(&data);
        try std.testing.expect(len2 == 2);
        try std.testing.expectEqualStrings("bc", data[0..len2]);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Test buffered data" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    // buffered size bigger than source buffer size, with peek()
    {
        const src_reader: std.Io.Reader = .fixed("abc");
        var buf_reader = try BufReader.init(alloc, 80, src_reader);
        defer buf_reader.deinit(alloc);
        var br = buf_reader.interface();
        _ = try br.peek(1);
        try std.testing.expectEqualStrings("abc", br.buffer[0..3]);
    }
    // buffered size equals to source buffer size, with peek()
    {
        const src_reader: std.Io.Reader = .fixed("abc");
        var buf_reader = try BufReader.init(alloc, 3, src_reader);
        defer buf_reader.deinit(alloc);
        var br = buf_reader.interface();
        _ = try br.peek(1);
        try std.testing.expectEqualStrings("abc", br.buffer[0..3]);
    }
    // buffered size less than source buffer size, with peek()
    {
        const src_reader: std.Io.Reader = .fixed("abc");
        var buf_reader = try BufReader.init(alloc, 2, src_reader);
        defer buf_reader.deinit(alloc);
        var br = buf_reader.interface();
        _ = try br.peek(1);
        try std.testing.expectEqualStrings("ab", br.buffer[0..2]);
    }
    // buffered size less than source buffer size, with take()
    {
        const src_reader: std.Io.Reader = .fixed("abc");
        var buf_reader = try BufReader.init(alloc, 2, src_reader);
        defer buf_reader.deinit(alloc);
        var br = buf_reader.interface();
        _ = try br.take(1);
        try std.testing.expectEqualStrings("ab", br.buffer[0..2]);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}


