// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William W. Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const Allocator = std.mem.Allocator;
const allocPrint = std.fmt.allocPrint;
const ArrayList = std.ArrayList;
const StringHashMap = std.hash_map.StringHashMap;
const JrErrors = @import("../zigjr.zig").JrErrors;


pub const FrameBuf = struct {
    buf:        ArrayList(u8),
    headers:    StringHashMap([]const u8),
    data_start: usize,

    pub fn init(alloc: Allocator) @This() {
        return .{
            .buf        = ArrayList(u8).init(alloc),
            .headers    = StringHashMap([]const u8).init(alloc),
            .data_start = 0,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.buf.deinit();
        self.headers.deinit();
    }

    pub fn reset(self: *@This()) void {
        self.headers.clearRetainingCapacity();
        self.buf.clearRetainingCapacity();
        self.data_start = 0;
    }

    pub fn getContentLength(self: @This()) !?usize {
        if (self.headers.get("Content-Length")) |value| {
            return try std.fmt.parseInt(usize, value, 10);
        }
        return null;
    }

    pub fn prepareContentBuf(self: *@This(), content_length: usize) !void {
        // Save the content starting offset, and expand items per content_length.
        self.data_start = self.buf.items.len;
        try self.buf.resize(self.data_start + content_length);
    }

    pub fn nextReadBuf(self: *@This(), offset: usize, remaining: usize) []u8 {
        return self.buf.items[(self.data_start + offset)..][0..remaining];
    }

    pub fn getContent(self: @This()) []const u8 {
        return self.buf.items[self.data_start..];
    }

};


/// Read the HTTP-style headers of a data frame.
/// The data frame has the format of:
///     Content-Length: DATA_LENGTH\r\n
///     Other-Header: VALUE\r\n
///     ...
///     \r\n
///     DATA
/// Caller checks frame_buf.headers.count() for headers read.
pub fn readHttpHeaders(reader: anytype, frame_buf: *FrameBuf) !void {
    while (true) {
        const read_idx = frame_buf.buf.items.len;
        try reader.streamUntilDelimiter(frame_buf.buf.writer(), '\n', null);
        const line = std.mem.trim(u8, frame_buf.buf.items[read_idx..], "\r\n");
        if (line.len == 0) {    // reach an empty line \r\n
            return;             // caller checks frame_buf.headers.count() for headers.
        }
        var parts       = std.mem.splitScalar(u8, line, ':');
        const str_key   = parts.next() orelse "";
        const str_val   = parts.next() orelse "";
        const trim_key  = std.mem.trim(u8, str_key, " ");
        const trim_val  = std.mem.trim(u8, str_val, " ");
        try frame_buf.headers.put(trim_key, trim_val);
    }
}

/// Read the headers of a data frame and return the Content-Length value.
/// The data frame has the format of:
///     Content-Length: DATA_LENGTH\r\n
///     Other-Header: VALUE\r\n
///     ...
///     \r\n
///     DATA
fn readContentLengthHeader(reader: anytype, frame_buf: *ArrayList(u8)) !usize {
    var content_length: ?usize = null;
    while (true) {
        frame_buf.clearRetainingCapacity();
        try reader.streamUntilDelimiter(frame_buf.writer(), '\n', null);
        const line = std.mem.trim(u8, frame_buf.items, "\r\n");
        if (line.len == 0) {
            break;              // reach the empty line \r\n
        }
        var parts       = std.mem.splitScalar(u8, line, ':');
        const str_key   = parts.next() orelse "";
        const str_val   = parts.next() orelse "";
        const trim_val  = std.mem.trim(u8, str_val, " ");
        if (std.mem.eql(u8, str_key, "Content-Length"))
            content_length = try std.fmt.parseInt(usize, trim_val, 10);
    }

    return if (content_length)|len| len else JrErrors.MissingContentLengthHeader;
}

/// Read a data frame, that has a Content-Length header, into frame_buf.
/// The headers and the content data are kept in the frame_buf.
pub fn readContentLengthFrame(reader: anytype, frame_buf: *FrameBuf) !bool {
    readHttpHeaders(reader, frame_buf) catch |err| {
        if (err == error.EndOfStream) return false;
        return err;     // unrecoverable error while reading from reader.
    };
    const content_length = try frame_buf.getContentLength() orelse {
        return JrErrors.MissingContentLengthHeader;
    };

    try frame_buf.prepareContentBuf(content_length);
    var read_total: usize = 0;
    while (read_total < content_length) {
        const remaining = content_length - read_total;
        const read_buf  = frame_buf.nextReadBuf(read_total, remaining);
        const read_len  = try reader.read(read_buf);
        if (read_len == 0) return error.UnexpectedEof;
        read_total += read_len;
    }

    return true;        // has more data.
}

/// Write a data frame to a writer, with a header section containing
/// the Content-Length header for the data.
pub fn writeContentLengthFrame(writer: anytype, content: []const u8) !void {
    try writer.print("Content-Length: {d}\r\n", .{content.len});
    try writer.print("\r\n", .{});
    try writer.writeAll(content);
}

/// Build a sequence of data frames into a byte buffer, with a header section
/// containing the Content-Length header for each frame.
pub fn writeContentLengthFrames(alloc: Allocator, data_frames: []const []const u8) !ArrayList(u8) {
    var buffer = ArrayList(u8).init(alloc);
    const writer = buffer.writer();
    for (data_frames)|data| try writeContentLengthFrame(writer, data);
    return buffer;
}


