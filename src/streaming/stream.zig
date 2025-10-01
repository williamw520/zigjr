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
// const bufferedWriter = std.io.bufferedWriter;

const zigjr = @import("../zigjr.zig");
const RequestDispatcher = zigjr.RequestDispatcher;
const ResponseDispatcher = zigjr.ResponseDispatcher;
const JrErrors = zigjr.JrErrors;
const frame = @import("frame.zig");


const TRIM_SET = " \t\r\n";


/// Runs a loop to read a stream of JSON request messages (frames) from the reader,
/// handle each one with the dispatcher, and write the JSON responses to the writer.
/// The writer is buffered internally.  The reader is not buffered.
/// Caller might want to wrap a buffered reader around it.
pub fn requestsByDelimiter(alloc: Allocator, reader: *std.Io.Reader, writer: *std.Io.Writer,
                           dispatcher: RequestDispatcher, options: DelimiterOptions) !void {
    var frame_buf = std.Io.Writer.Allocating.init(alloc);
    defer frame_buf.deinit();

    var pipeline = zigjr.RequestPipeline.init(alloc, dispatcher, options.logger);
    defer pipeline.deinit();

    options.logger.start("[stream.requestsByDelimiter] Logging starts");
    defer { options.logger.stop("[stream.requestsByDelimiter] Logging stops"); }

    while (true) {
        frame_buf.clearRetainingCapacity();
        _ = reader.streamDelimiter(&frame_buf.writer, options.request_delimiter) catch |e| {
            switch (e) {
                error.EndOfStream => break,
                else => return e,   // unrecoverable error while reading from reader.
            }
        };
        reader.toss(1);             // skip the delimiter char in reader.

        const request_json = std.mem.trim(u8, frame_buf.written(), TRIM_SET);
        if (options.skip_blank_message and request_json.len == 0) continue;

        if (try pipeline.runRequest(alloc, request_json, writer, .{})) {
            try writer.writeByte(options.response_delimiter);
            try writer.flush();
        }
    }
}


/// Runs a loop to read a stream of JSON response messages (frames) from the reader,
/// and handle each one with the dispatcher.
pub fn responsesByDelimiter(alloc: Allocator, reader: *std.Io.Reader,
                            dispatcher: ResponseDispatcher, options: DelimiterOptions) !void {
    var frame_buf = std.Io.Writer.Allocating.init(alloc);
    defer frame_buf.deinit();

    const pipeline = zigjr.ResponsePipeline.init(alloc, dispatcher);

    options.logger.start("[stream.responsesByDelimiter] Logging starts");
    defer { options.logger.stop("[stream.responsesByDelimiter] Logging stops"); }

    while (true) {
        frame_buf.clearRetainingCapacity();
        _ = reader.streamDelimiter(&frame_buf.writer, options.request_delimiter) catch |e| {
            switch (e) {
                error.EndOfStream => break,
                else => return e,   // unrecoverable error while reading from reader.
            }
        };
        reader.toss(1);             // skip the delimiter char in reader.

        const response_json = std.mem.trim(u8, frame_buf.written(), TRIM_SET);
        if (options.skip_blank_message and response_json.len == 0) continue;

        options.logger.log("stream.responsesByDelimiter", "receive response", response_json);
        pipeline.runResponse(response_json, null) catch |err| {
            var stderr_writer = std.fs.File.stderr().writer(&.{});
            const stderr = &stderr_writer.interface;
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
pub fn requestsByContentLength(alloc: Allocator, reader: *std.Io.Reader, writer: *std.Io.Writer,
                               dispatcher: RequestDispatcher, options: ContentLengthOptions) !void {
    options.logger.start("[stream.requestsByContentLength] Logging starts");
    defer { options.logger.stop("[stream.requestsByContentLength] Logging stops"); }

    var frame_data = frame.FrameData.init(alloc);
    defer frame_data.deinit();
    var response_buf = std.Io.Writer.Allocating.init(alloc);
    defer response_buf.deinit();
    const output_writer = writer;
    var pipeline = zigjr.RequestPipeline.init(alloc, dispatcher, null);
    defer pipeline.deinit();

    while (true) {
        frame_data.reset();
        const has_more = frame.readContentLengthFrame(reader, &frame_data) catch |err| {
            if (err == JrErrors.MissingContentLengthHeader and options.recover_on_missing_header) {
                continue;
            }
            return err;     // unrecoverable error while reading from reader.
        };
        if (!has_more)
            break;

        const request_json = std.mem.trim(u8, frame_data.getContent(), " \t");
        if (options.skip_blank_message and request_json.len == 0) continue;

        response_buf.clearRetainingCapacity();  // reset the output buffer for every request.
        options.logger.log("stream.requestsByContentLength", "request ", request_json);
        if (try pipeline.runRequest(alloc, request_json, &response_buf.writer, .{})) {
            try frame.writeContentLengthFrame(output_writer, response_buf.written());
            options.logger.log("stream.requestsByContentLength", "response", response_buf.written());
        } else {
            options.logger.log("stream.requestsByContentLength", "response", "");
        }
    }
}

/// Runs a loop to read a stream of JSON response messages (frames) from the reader,
/// and handle each one with the dispatcher.
pub fn responsesByContentLength(alloc: Allocator, reader: anytype,
                                dispatcher: ResponseDispatcher, options: ContentLengthOptions) !void {
    var frame_buf = frame.FrameData.init(alloc);
    defer frame_buf.deinit();
    const pipeline = zigjr.ResponsePipeline.init(alloc, dispatcher);

    options.logger.start("[stream.responsesByContentLength] Logging starts");
    defer { options.logger.stop("[stream.responsesByContentLength] Logging stops"); }

    while (true) {
        frame_buf.reset();
        if (!try frame.readContentLengthFrame(reader, &frame_buf))
            break;

        const response_json = std.mem.trim(u8, frame_buf.getContent(), " \t");
        if (options.skip_blank_message and response_json.len == 0) continue;

        options.logger.log("stream.responsesByContentLength", "receive response", response_json);
        pipeline.runResponse(response_json, null) catch |err| {
            var stderr_writer = std.fs.File.stderr().writer(&.{});
            const stderr = &stderr_writer.interface;
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
    var frame_buf = frame.FrameData.init(alloc);
    defer frame_buf.deinit();
    var req_response_buf = std.Io.Writer.Allocating.init(alloc);
    defer req_response_buf.deinit();
    const req_output_writer = req_writer;
    var pipeline = zigjr.MessagePipeline.init(alloc, req_dispatcher, res_dispatcher, options.logger);
    defer pipeline.deinit();

    options.logger.start("[stream.messagesByContentLength] Logging starts");
    defer { options.logger.stop("[stream.messagesByContentLength] Logging stops"); }

    while (true) {
        frame_buf.reset();
        if (!try frame.readContentLengthFrame(reader, &frame_buf))
            break;

        const message_json = std.mem.trim(u8, frame_buf.getContent(), " \t");
        if (options.skip_blank_message and message_json.len == 0) continue;

        req_response_buf.clearRetainingCapacity();  // reset the output buffer for every request.
        const run_result = try pipeline.runMessage(alloc, message_json, &req_response_buf.writer, .{});
        switch (run_result) {
            .request_has_response => {
                try frame.writeContentLengthFrame(req_output_writer, req_response_buf.written());
                try req_output_writer.flush();
                options.logger.log("stream.messagesByContentLength", "request_has_response", req_response_buf.written());
            },
            .request_no_response => {
                options.logger.log("stream.messagesByContentLength", "request_no_response", "");
            },
            .response_processed => {
                options.logger.log("stream.messagesByContentLength", "response_processed", "");
            },
        }
    }
}

