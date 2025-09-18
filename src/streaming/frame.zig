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
const RpcId = @import("../jsonrpc/request.zig").RpcId;
const makeRequestJson = @import("../jsonrpc/composer.zig").makeRequestJson;
const makeResponseJson = @import("../jsonrpc/composer.zig").makeResponseJson;
const JrErrors = @import("../zigjr.zig").JrErrors;
const BufReader = @import("BufReader.zig");


// Trim header key and value by these characters.
const TRIM_SET = " \t\r\n";

// Header key and value positions in the FrameData.buf.
const Pos = [4]usize;

/// The header the content data of a request frame.
pub const FrameData = struct {
    alloc:          Allocator,
    buf:            std.Io.Writer.Allocating,   // The header and content data of the whole frame.
    header_pos:     ArrayList(Pos),
    content_start:  usize,
    content_length: ?usize = null,

    pub fn init(alloc: Allocator) @This() {
        return .{
            .alloc      = alloc,
            .header_pos = .empty,
            .buf        = .init(alloc),
            .content_start = 0,
        };
    }

    pub fn deinit(self: *FrameData) void {
        self.header_pos.deinit(self.alloc);
        self.buf.deinit();
    }

    pub fn reset(self: *FrameData) void {
        self.header_pos.clearRetainingCapacity();
        self.buf.clearRetainingCapacity();
        self.content_start = 0;
    }

    fn bufWriter(self: *FrameData) *std.Io.Writer {
        return &self.buf.writer;
    }

    fn bufData(self: *FrameData) []const u8 {
        return self.buf.written();
    }

    fn currentPos(self: *FrameData) usize {
        return self.bufData().len;
    }

    fn addHeader(self: *FrameData, key_start: usize, key_end: usize,
                 value_start: usize, value_end: usize) !void {
        try self.header_pos.append(self.alloc, .{ key_start, key_end, value_start, value_end });
    }

    pub fn headerCount(self: *const FrameData) usize {
        return self.header_pos.items.len;
    }

    /// Get the header key at 'idx'.
    /// Slice might get invalidated if buf is grown while the frame is being read.
    pub fn headerKey(self: *FrameData, idx: usize) []const u8 {
        const start = self.header_pos.items[idx][0];
        const end   = self.header_pos.items[idx][1];
        return std.mem.trim(u8, self.bufData()[start..end], TRIM_SET);
    }

    /// Get the header key at 'idx'.
    /// Slice might get invalidated if buf is grown while the frame is being read.
    pub fn headerValue(self: *FrameData, idx: usize) []const u8 {
        const start = self.header_pos.items[idx][2];
        const end   = self.header_pos.items[idx][3];
        return std.mem.trim(u8, self.bufData()[start..end], TRIM_SET);
    }

    /// Get the header key at 'idx'.
    /// Slice might get invalidated if buf is grown while the frame is being read.
    pub fn findHeader(self: *FrameData, key: []const u8) ?[]const u8 {
        for (0..self.headerCount())|idx| {
            if (std.mem.eql(u8, key, self.headerKey(idx))) {
                return self.headerValue(idx);
            }
        }
        return null;
    }

    fn setupContent(self: *FrameData) !void {
        self.content_start  = self.currentPos();
        self.content_length = if (self.findHeader("Content-Length")) |value| 
            try std.fmt.parseInt(usize, value, 10)
        else null;
    }

    pub fn getContent(self: *FrameData) []const u8 {
        return self.bufData()[self.content_start..];
    }

};


/// Read the HTTP-style headers of a data frame.
/// Content not read yet after this call. Use `readContentLengthFrame()` instead.
/// The data frame has the format of:
///     Content-Length: DATA_LENGTH\r\n
///     Other-Header: VALUE\r\n
///     ...
///     \r\n
///     CONTENT DATA
/// Caller checks frame_data.headerCount() for headers read.
pub fn readHttpHeaders(reader: *std.Io.Reader, frame_data: *FrameData) !void {
    while (true) {
        const start_pos = frame_data.currentPos();
        const read_len  = try reader.streamDelimiter(frame_data.bufWriter(), '\n');
        const end_pos   = frame_data.currentPos();
        reader.toss(1);             // skip the '\n' char in reader.
        if (read_len == 0)
            break;                  // reach an empty line '\n'; end of headers.
        const line      = frame_data.bufData()[start_pos..end_pos];
        const trimmed   = std.mem.trim(u8, line, "\r\n");
        if (trimmed.len == 0) {     // reach an empty line "\r\n"; end of headers.
            break;                  // caller checks frame_data.headerCount() for headers.
        }
        const colon_pos = if (std.mem.indexOfScalar(u8, line, ':')) |pos| pos else 0;
        if (colon_pos == 0)
            continue;               // missing ':" or empty key.
        const key_start = start_pos;
        const key_end   = start_pos + colon_pos;
        const val_start = start_pos + colon_pos + 1;
        const val_end   = end_pos;  // empty value is acceptable.
        try frame_data.addHeader(key_start, key_end, val_start, val_end);
    }
    try frame_data.setupContent();
}

/// Read a data frame, that has a Content-Length header, into frame_data.
/// The headers and the content data are kept in the frame_data.
pub fn readContentLengthFrame(reader: *std.Io.Reader, frame_data: *FrameData) !bool {
    readHttpHeaders(reader, frame_data) catch |err| {
        if (err == error.EndOfStream)
            return false;   // no more data.
        return err;         // unrecoverable error while reading from reader.
    };
    if (frame_data.content_length) |len| {
        _ = try reader.stream(frame_data.bufWriter(), .limited(len));
        return true;            // has content data.
    } else {
        return JrErrors.MissingContentLengthHeader;
    }
}


/// Write a data frame to a writer, with a header section containing
/// the Content-Length header for the data.
pub fn writeContentLengthFrame(writer: *std.Io.Writer, content: []const u8) !void {
    try writer.print("Content-Length: {d}\r\n\r\n", .{content.len});
    try writer.writeAll(content);
}

/// Write a sequence of data frames into a writer,
/// where each frame with a header section containing the Content-Length header.
pub fn writeContentLengthFrames(writer: *std.Io.Writer, frame_contents: []const []const u8) !void {
    for (frame_contents)|content|
        try writeContentLengthFrame(writer, content);
}

/// Write a sequence of data frames into a writer,
/// where each frame with a header section containing the Content-Length header.
pub fn allocContentLengthFrames(alloc: Allocator, frame_contents: []const []const u8) !std.Io.Writer.Allocating {
    var alloc_writer = std.Io.Writer.Allocating.init(alloc);
    try writeContentLengthFrames(&alloc_writer.writer, frame_contents);
    return alloc_writer;
}


/// Write a request data frame to a writer, with a header section containing
/// the Content-Length header for the data.
pub fn writeContentLengthRequest(alloc: Allocator, writer: *std.Io.Writer,
                                 method: []const u8, params: anytype, id: RpcId) !void {
    const json = try makeRequestJson(alloc, method, params, id);
    defer alloc.free(json);
    try writeContentLengthFrame(writer, json);
}

/// Write a request data frame to a writer, with a header section containing
/// the Content-Length header for the data.
pub fn writeContentLengthResponse(alloc: Allocator, writer: *std.Io.Writer,
                                  result_json: []const u8, id: RpcId) !void {
    const json = try makeResponseJson(alloc, id, result_json);
    defer alloc.free(json);
    try writeContentLengthFrame(writer, json);
}


