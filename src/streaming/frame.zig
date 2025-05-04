// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const Allocator = std.mem.Allocator;
const allocPrint = std.fmt.allocPrint;
const ArrayList = std.ArrayList;

const zigjr = @import("../zigjr.zig");
const JrErrors = zigjr.JrErrors;


/// Write a data frame to a writer, with a header section containing
/// the Content-Length header for the data.
pub fn writeContentLengthFrame(writer: anytype, data: []const u8) !void {
    try writer.print("Content-Length: {d}\r\n", .{data.len});
    try writer.print("\r\n\r\n", .{});
    _ = try writer.writeAll(data);
}

/// Build a sequence of data frames into a byte buffer, with a header section
/// containing the Content-Length header for each frame.
pub fn writeContentLengthFrames(alloc: Allocator, data_frames: []const []const u8) !ArrayList(u8) {
    var buffer = ArrayList(u8).init(alloc);
    const writer = buffer.writer();
    for (data_frames)|data| try writeContentLengthFrame(writer, data);
    return buffer;
}

/// Read the headers of a data frame and return the Content-Length value.
/// The data frame has the format of:
///     Content-Length: DATA_LENGTH\r\n
///     Other-Header: VALUE\r\n
///     ...
///     \r\n
///     \r\n
///     DATA
fn readContentLengthHeader(reader: anytype, buf: *ArrayList(u8)) !usize {
    var empty_line_count: usize = 0;
    var content_length: ?usize = null;
    while (true) {
        buf.clearRetainingCapacity();
        _ = try reader.streamUntilDelimiter(buf.writer(), '\n', null);
        const line = std.mem.trim(u8, buf.items, "\r\n");
        if (line.len == 0) {
            empty_line_count += 1;
            if (empty_line_count == 2) break;               // reached \r\n\r\n
            continue;
        } else {
            empty_line_count = 0;                           // reset whenever line has data.
        }
        var parts   = std.mem.splitScalar(u8, line, ':');   // Key: Value
        const s_key = parts.next() orelse "";
        const s_val = parts.next() orelse "";
        const t_val = std.mem.trim(u8, s_val, " ");
        if (std.mem.eql(u8, s_key, "Content-Length"))       // found the header
            content_length = try std.fmt.parseInt(usize, t_val, 10);
    }

    return if (content_length)|len| len else JrErrors.MissingContentLengthHeader;
}

/// Read a data frame, that has a Content-Length header, into data_buffer.
/// The content data is written to the output data_buffer, which is expanded as needed.
/// The content length is returned. If Content-Length header is not found, return null.
pub fn readContentLengthFrame(reader: anytype, data_buffer: *ArrayList(u8)) !usize {
    // Use data_buffer as a temp buffer to read the headers.
    const content_length = try readContentLengthHeader(reader, data_buffer);
    data_buffer.clearRetainingCapacity();
    try data_buffer.ensureTotalCapacity(content_length);
    var read_total: usize = 0;
    while (read_total < content_length) {
        const to_read = content_length - read_total;
        const chunk = try data_buffer.addManyAsSlice(@min(to_read, 4096));
        const read_len = try reader.read(chunk);
        if (read_len == 0) return error.UnexpectedEof;
        read_total += read_len;
    }
    return content_length;
}


