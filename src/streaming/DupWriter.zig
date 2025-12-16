// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William W. Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const DupWriter = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Provides a writer implementing the std.Io.Writer interface that
/// duplicates the data written to two destination writers.

// The first destination writer to write data.
writer1: *std.Io.Writer,
// The second destination writer to write data.
writer2: *std.Io.Writer,
// Turn on/off writing for the second destination writer.
writer2_enabled: bool = true,
// The std.Io.Writer interface for this writer implementation.
writer_interface: std.Io.Writer,


pub fn init(buffer: []u8, writer1: *std.Io.Writer, writer2: *std.Io.Writer) DupWriter {
    return .{
        .writer1 = writer1,
        .writer2 = writer2,
        .writer_interface = .{
            .vtable = &.{
                .drain = drainDup,
                .sendFile = sendFileDup,
            },
            .buffer = buffer,
            .end = 0,
        },
    };
}


/// Get the std.Io.Writer interface pointer, to avoid an accidental copy.
pub fn interface(self: *DupWriter) *std.Io.Writer {
    return &self.writer_interface;
}

pub fn enableWriter2(self: *DupWriter, flag: bool) void {
    self.writer2_enabled = flag;
}

fn drainDup(io_w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
    const dw: *DupWriter = @alignCast(@fieldParentPtr("writer_interface", io_w));
    const buffered = io_w.buffered();
    const total_len = try dw.writer1.writeSplatHeader(buffered, data, splat);
    if (dw.writer2_enabled) {
        _ = try dw.writer2.writeSplatHeader(buffered, data, splat);
    }
    _ = io_w.consume(buffered.len);
    return total_len;
}


fn sendFileDup(io_w: *std.Io.Writer, file_reader: *std.fs.File.Reader, limit: std.Io.Limit) std.Io.Writer.FileError!usize {
    const dw: *DupWriter = @alignCast(@fieldParentPtr("writer_interface", io_w));
    const len = try dw.writer1.sendFile(file_reader, limit);
    if (dw.writer2_enabled) {
        _ = try dw.writer2.sendFile(file_reader, limit);
    }
    return len;
}


test "Write dup with .write()" {
    var gpa = std.heap.DebugAllocator(.{}){};
    const alloc = gpa.allocator();
    {
        var writer1 = std.Io.Writer.Allocating.init(alloc);
        var writer2 = std.Io.Writer.Allocating.init(alloc);
        defer writer1.deinit();
        defer writer2.deinit();

        var buf: [10]u8 = undefined;
        var dup_writer = DupWriter.init(&buf, &writer1.writer, &writer2.writer);
        const writer = dup_writer.interface();
        _ = try writer.write("abc");
        // std.debug.print("buf: {any}, end: {}\n", .{writer.buffer, writer.end});
        try writer.flush();
        // std.debug.print("w1: |{s}|\n", .{writer1.written()});
        // std.debug.print("w2: |{s}|\n", .{writer2.written()});
        try std.testing.expect(writer1.written().len == 3);
        try std.testing.expect(writer2.written().len == 3);
        try std.testing.expectEqualSlices(u8, writer1.written(), writer2.written());
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Write dup with streaming" {
    var gpa = std.heap.DebugAllocator(.{}){};
    const alloc = gpa.allocator();
    {
        var reader: std.Io.Reader = .fixed("abc");
        var writer1 = std.Io.Writer.Allocating.init(alloc);
        var writer2 = std.Io.Writer.Allocating.init(alloc);
        defer writer1.deinit();
        defer writer2.deinit();

        var buf: [10]u8 = undefined;
        var dup_writer = DupWriter.init(&buf, &writer1.writer, &writer2.writer);
        const writer = dup_writer.interface();
        _ = try reader.stream(writer, .unlimited);
        try writer.flush();
        // std.debug.print("w1: |{s}|\n", .{writer1.written()});
        // std.debug.print("w2: |{s}|\n", .{writer2.written()});
        try std.testing.expect(writer1.written().len == 3);
        try std.testing.expect(writer2.written().len == 3);
        try std.testing.expectEqualSlices(u8, writer1.written(), writer2.written());
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Write dup with streaming, small buffer" {
    var gpa = std.heap.DebugAllocator(.{}){};
    const alloc = gpa.allocator();
    {
        var reader: std.Io.Reader = .fixed("0123456789012345678901234567890123456789");
        var writer1 = std.Io.Writer.Allocating.init(alloc);
        var writer2 = std.Io.Writer.Allocating.init(alloc);
        defer writer1.deinit();
        defer writer2.deinit();

        var buf: [2]u8 = undefined;     // small buffer to force flushing intermediate data 
        var dup_writer = DupWriter.init(&buf, &writer1.writer, &writer2.writer);
        const writer = dup_writer.interface();
        _ = try reader.stream(writer, .unlimited);
        try writer.flush();
        // std.debug.print("w1: |{s}|\n", .{writer1.written()});
        // std.debug.print("w2: |{s}|\n", .{writer2.written()});
        try std.testing.expect(writer1.written().len == 40);
        try std.testing.expect(writer2.written().len == 40);
        try std.testing.expectEqualSlices(u8, writer1.written(), writer2.written());
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Write dup with .write() and enableWriter2" {
    var gpa = std.heap.DebugAllocator(.{}){};
    const alloc = gpa.allocator();
    {
        var writer1 = std.Io.Writer.Allocating.init(alloc);
        var writer2 = std.Io.Writer.Allocating.init(alloc);
        defer writer1.deinit();
        defer writer2.deinit();

        var buf: [10]u8 = undefined;
        var dup_writer = DupWriter.init(&buf, &writer1.writer, &writer2.writer);
        const writer = dup_writer.interface();
        _ = try writer.write("a");
        try writer.flush();
        dup_writer.enableWriter2(false);
        _ = try writer.write("b");
        try writer.flush();
        dup_writer.enableWriter2(true);
        _ = try writer.write("c");
        try writer.flush();
        // std.debug.print("w1: |{s}|\n", .{writer1.written()});
        // std.debug.print("w2: |{s}|\n", .{writer2.written()});
        try std.testing.expect(writer1.written().len == 3);
        try std.testing.expect(writer2.written().len == 2);
        try std.testing.expectEqualSlices(u8, writer1.written(), "abc");
        try std.testing.expectEqualSlices(u8, writer2.written(), "ac");
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

