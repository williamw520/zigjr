// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William W. Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const Allocator = std.mem.Allocator;


inline fn TPtr(T: type, opaque_ptr: *anyopaque) T {
    return @as(T, @ptrCast(@alignCast(opaque_ptr)));
}

/// Logger interface
pub const Logger = struct {
    impl:       *anyopaque,
    i_start:    *const fn(impl: *anyopaque, message: []const u8) void,
    i_log:      *const fn(impl: *anyopaque, source: [] const u8, operation: []const u8, message: []const u8) void,
    i_stop:     *const fn(impl: *anyopaque, message: []const u8) void,

    // The implementation must have these methods.
    pub fn start(self: @This(), message: []const u8) void {
        self.i_start(self.impl, message);
    }

    pub fn log(self: @This(), source: [] const u8, operation: []const u8, message: []const u8) void {
        self.i_log(self.impl, source, operation, message);
    }

    pub fn stop(self: @This(), message: []const u8) void {
        self.i_stop(self.impl, message);
    }

    // Interface is implemented by the 'impl_obj' object.
    pub fn implBy(impl_obj: anytype) Logger {
        const IT = @TypeOf(impl_obj);

        const Delegate = struct {
            fn start(impl: *anyopaque, message: []const u8) void {
                TPtr(IT, impl).start(message);
            }

            fn log(impl: *anyopaque, source: [] const u8, operation: []const u8, message: []const u8) void {
                TPtr(IT, impl).log(source, operation, message);
            }

            fn stop(impl: *anyopaque, message: []const u8) void {
                TPtr(IT, impl).stop(message);
            }
        };

        return .{
            .impl = impl_obj,
            .i_start = Delegate.start,
            .i_log = Delegate.log,
            .i_stop = Delegate.stop,
        };
    }

};


/// A nop logger that implements the Logger interface; can be passed to the stream options.logger.
pub const NopLogger = struct {
    pub fn start(_: @This(), _: []const u8) void {}
    pub fn log(_: @This(), _: []const u8, _: []const u8, _: []const u8) void {}
    pub fn stop(_: @This(), _: []const u8) void {}
};

var nopLogger = NopLogger{};


/// A logger that prints to std.dbg, implemented the Logger interface.
pub const DbgLogger = struct {
    pub fn start(_: *@This(), message: []const u8) void {
        std.debug.print("{s}\n", .{message});
    }

    pub fn log(_: *@This(), source: []const u8, operation: []const u8, message: []const u8) void {
        std.debug.print("[{s}] {s} - {s}\n", .{source, operation, message});
    }

    pub fn stop(_: *@This(), message: []const u8) void {
        std.debug.print("{s}\n", .{message});
    }
};


/// A logger that logs to file, implemented the Logger interface.
pub const FileLogger = struct {
    alloc: Allocator,
    count: usize = 0,
    file: std.fs.File,
    fwriter: std.fs.File.Writer,
    write_buf: []const u8,

    /// Create a FileLogger to log to the file at 'file_path',
    pub fn init(alloc: Allocator, file_path: []const u8) !FileLogger {
        const file = try fileOpenIf(file_path);
        try file.seekFromEnd(0);                        // seek to end for appending to file.
        const write_buf = try alloc.alloc(u8, 4096);    // buffer with the usual disk page size.
        return .{
            .alloc = alloc,
            .file = file,
            .fwriter = file.writer(write_buf),
            .write_buf = write_buf,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.file.close();
        self.alloc.free(self.write_buf);
    }

    pub fn start(self: *@This(), message: []const u8) void {
        const ts_sec = std.time.timestamp();
        self.fwriter.interface.print("Timestamp {d} - {s}\n", .{ts_sec, message})
            catch |err| std.debug.print("Error while printing in start(). {any}\n", .{err});
        self.fwriter.interface.flush() 
            catch |err| std.debug.print("Error while flushing in log(). {any}\n", .{err});
    }

    pub fn log(self: *@This(), source: []const u8, operation: []const u8, message: []const u8) void {
        self.count += 1;
        self.fwriter.interface.print("{}: [{s}] {s} - {s}\n", .{self.count, source, operation, message})
            catch |err| std.debug.print("Error while printing in log(). {any}\n", .{err});
        self.fwriter.interface.flush() 
            catch |err| std.debug.print("Error while flushing in log(). {any}\n", .{err});
    }
    
    pub fn stop(self: *@This(), message: []const u8) void {
        const ts_sec = std.time.timestamp();
        self.fwriter.interface.print("Timestamp {d} - {s}\n\n", .{ts_sec, message})
            catch |err| std.debug.print("Error while printing in stop(). {any}\n", .{err});
        self.fwriter.interface.flush()
            catch |err| std.debug.print("Error while flushing in stop(). {any}\n", .{err});
    }

    fn fileOpenIf(file_path: []const u8) !std.fs.File {
        return std.fs.cwd().openFile(file_path, .{ .mode = .write_only }) catch |err| {
            if (err == error.FileNotFound) {
                return try std.fs.cwd().createFile(file_path, .{ .read = false });
            } else {
                return err;
            }
        };
    }
    
};


