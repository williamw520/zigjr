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
const bufferedWriter = std.io.bufferedWriter;

const zigjr = @import("../zigjr.zig");
const RequestDispatcher = zigjr.RequestDispatcher;
const ResponseDispatcher = zigjr.ResponseDispatcher;
const JrErrors = zigjr.JrErrors;
const frame = @import("frame.zig");



/// Runs a loop to read a stream of JSON request messages (frames) from the reader,
/// handle each one with the dispatcher, and write the JSON responses to the writer.
/// The writer is buffered internally.  The reader is not buffered.
/// Caller might want to wrap a buffered reader around it.
pub fn requestsByDelimiter(alloc: Allocator, reader: anytype, writer: anytype,
                           dispatcher: RequestDispatcher, options: DelimiterOptions) !void {
    var frame_buf = std.ArrayList(u8).init(alloc); // Each JSON request is a frame.
    defer frame_buf.deinit();
    const frame_writer = frame_buf.writer();
    var response_buf = std.ArrayList(u8).init(alloc);
    defer response_buf.deinit();
    var buffered_writer = std.io.bufferedWriter(writer);
    const output_writer = buffered_writer.writer();
    var pipeline = zigjr.RequestPipeline.init(alloc, dispatcher, null);
    defer pipeline.deinit();

    options.logger.start("[requestsByDelimiter] Logging starts");
    defer { options.logger.stop("[requestsByDelimiter] Logging stops"); }

    while (true) {
        frame_buf.clearRetainingCapacity();
        reader.streamUntilDelimiter(frame_writer, options.request_delimiter, null) catch |e| {
            switch (e) {
                error.EndOfStream => break,
                else => return e,   // unrecoverable error while reading from reader.
            }
        };

        const request_json = std.mem.trim(u8, frame_buf.items, " \t\r\n");
        if (options.skip_blank_message and request_json.len == 0) continue;

        options.logger.log("requestsByDelimiter", "receive request", request_json);
        response_buf.clearRetainingCapacity();  // reset the output buffer for every request.
        if (try pipeline.runRequest(request_json, &response_buf, null)) {
            try output_writer.writeAll(response_buf.items);
            try output_writer.writeByte(options.response_delimiter);
            try buffered_writer.flush();
            options.logger.log("requestsByDelimiter", "return response", response_buf.items);
        }
    }
}


/// Runs a loop to read a stream of JSON response messages (frames) from the reader,
/// and handle each one with the dispatcher.
pub fn responsesByDelimiter(alloc: Allocator, reader: anytype,
                            dispatcher: ResponseDispatcher, options: DelimiterOptions) !void {
    var frame_buf = std.ArrayList(u8).init(alloc);  // Each JSON response is one frame.
    defer frame_buf.deinit();
    const frame_writer = frame_buf.writer();
    const pipeline = zigjr.ResponsePipeline.init(alloc, dispatcher);

    options.logger.start("[streamResponses] Logging starts");
    defer { options.logger.stop("[streamResponses] Logging stops"); }

    while (true) {
        frame_buf.clearRetainingCapacity();
        reader.streamUntilDelimiter(frame_writer, options.response_delimiter, null) catch |e| {
            switch (e) {
                error.EndOfStream => break,
                else => return e,   // unrecoverable error while reading from reader.
            }
        };

        const response_json = std.mem.trim(u8, frame_buf.items, " \t\r\n");
        if (options.skip_blank_message and response_json.len == 0) continue;

        options.logger.log("streamResponses", "receive response", response_json);
        pipeline.runResponse(response_json, null) catch |err| {
            const stderr = std.io.getStdErr().writer();
            stderr.print("Error in runResponse(). {any}", .{err}) catch {};
        };
    }
}

pub const DelimiterOptions = struct {
    request_delimiter: u8 = '\n',
    response_delimiter: u8 = '\n',
    skip_blank_message: bool = true,
    logger: zigjr.Logger = zigjr.Logger.implBy(&nopLogger),
};


/// Runs a loop to read a stream of JSON request messages (frames) from the reader,
/// handle each one with the dispatcher, and write the JSON responses to the buffered_writer.
pub fn requestsByContentLength(alloc: Allocator, reader: anytype, writer: anytype,
                               dispatcher: RequestDispatcher, options: ContentLengthOptions) !void {
    var frame_buf = frame.FrameBuf.init(alloc);
    defer frame_buf.deinit();
    var response_buf = std.ArrayList(u8).init(alloc);
    defer response_buf.deinit();
    var buffered_writer = std.io.bufferedWriter(writer);
    const output_writer = buffered_writer.writer();
    var pipeline = zigjr.RequestPipeline.init(alloc, dispatcher, null);
    defer pipeline.deinit();

    options.logger.start("[requestsByContentLength] Logging starts");
    defer { options.logger.stop("[requestsByContentLength] Logging stops"); }

    while (true) {
        frame_buf.reset();
        const has_more = frame.readContentLengthFrame(reader, &frame_buf) catch |err| {
            if (err == JrErrors.MissingContentLengthHeader and options.recover_on_missing_header) {
                continue;
            }
            return err;     // unrecoverable error while reading from reader.
        };
        if (!has_more)
            break;

        const request_json = std.mem.trim(u8, frame_buf.getContent(), " \t");
        if (options.skip_blank_message and request_json.len == 0) continue;

        response_buf.clearRetainingCapacity();  // reset the output buffer for every request.
        if (try pipeline.runRequest(request_json, &response_buf, frame_buf.headers)) {
            try frame.writeContentLengthFrame(output_writer, response_buf.items);
            try buffered_writer.flush();
            options.logger.log("requestsByContentLength", "return response", response_buf.items);
        }
    }
}

/// Runs a loop to read a stream of JSON response messages (frames) from the reader,
/// and handle each one with the dispatcher.
pub fn responsesByContentLength(alloc: Allocator, reader: anytype,
                                dispatcher: ResponseDispatcher, options: ContentLengthOptions) !void {
    var frame_buf = frame.FrameBuf.init(alloc);
    defer frame_buf.deinit();
    const pipeline = zigjr.ResponsePipeline.init(alloc, dispatcher);

    options.logger.start("[streamResponses] Logging starts");
    defer { options.logger.stop("[streamResponses] Logging stops"); }

    while (true) {
        frame_buf.reset();
        if (!try frame.readContentLengthFrame(reader, &frame_buf))
            break;

        const response_json = std.mem.trim(u8, frame_buf.getContent(), " \t");
        if (options.skip_blank_message and response_json.len == 0) continue;

        options.logger.log("streamResponses", "receive response", response_json);
        pipeline.runResponse(response_json, null) catch |err| {
            const stderr = std.io.getStdErr().writer();
            stderr.print("Error in runResponse(). {any}", .{err}) catch {};
        };
    }
}

pub const ContentLengthOptions = struct {
    recover_on_missing_header: bool = true,
    skip_blank_message: bool = true,
    logger: zigjr.Logger = zigjr.Logger.implBy(&nopLogger),
};

var nopLogger = zigjr.NopLogger{};


/// Runs a loop to read a stream of JSON request and/or response messages (frames) from the reader,
/// and handle each one with the RequestDispatcher or the ResponseDispatcher.
pub fn messagesByContentLength(alloc: Allocator, reader: anytype, req_writer: anytype,
                               req_dispatcher: RequestDispatcher, res_dispatcher: ResponseDispatcher,
                               options: ContentLengthOptions) !void {
    var frame_buf = frame.FrameBuf.init(alloc);
    defer frame_buf.deinit();
    var req_response_buf = std.ArrayList(u8).init(alloc);
    defer req_response_buf.deinit();
    var req_buffered_writer = std.io.bufferedWriter(req_writer);
    const req_output_writer = req_buffered_writer.writer();
    var pipeline = zigjr.MessagePipeline.init(alloc, req_dispatcher, res_dispatcher, options.logger);
    defer pipeline.deinit();

    options.logger.start("[messagesByContentLength] Logging starts");
    defer { options.logger.stop("[messagesByContentLength] Logging stops"); }

    while (true) {
        frame_buf.reset();
        if (!try frame.readContentLengthFrame(reader, &frame_buf))
            break;

        const message_json = std.mem.trim(u8, frame_buf.getContent(), " \t");
        if (options.skip_blank_message and message_json.len == 0) continue;

        req_response_buf.clearRetainingCapacity();  // reset the output buffer for every request.
        const run_result = try pipeline.runMessage(message_json, &req_response_buf, null);
        switch (run_result) {
            .request_has_response => {
                try frame.writeContentLengthFrame(req_output_writer, req_response_buf.items);
                try req_buffered_writer.flush();
                options.logger.log("messagesByContentLength", "request_has_response", req_response_buf.items);
            },
            .request_no_response => {
                options.logger.log("messagesByContentLength", "request_no_response", "");
            },
            .response_processed => {
                options.logger.log("messagesByContentLength", "response_processed", "");
            },
        }
    }
}

