// Toposort
// A Zig library for performing topological sort.
// Copyright (C) 2025 William Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const zigjr = @import("zigjr");
const Allocator = std.mem.Allocator;
const ParseOptions = std.json.ParseOptions;
const innerParse = std.json.innerParse;

const ArgIterator = std.process.ArgIterator;
const ArrayList = std.ArrayList;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const g_allocator = gpa.allocator();


const U1 = union(enum) {
    s2:     S2,
    arr:    []S2,

    pub fn jsonParse(alloc: Allocator, source: anytype, options: ParseOptions) !U1 {
        return switch (try source.peekNextTokenType()) {
            .object_begin => .{ .s2  = try innerParse(S2, alloc, source, options) },
            .array_begin =>  .{ .arr = try innerParse([]S2, alloc, source, options) },
            else => error.UnexpectedToken,
        };
    }    
};

// This is the struct returned with the error if any.
const S2 = struct {
    id:  u32 = 0,
    err: []const u8 = "",

    pub fn jsonParse(alloc: std.mem.Allocator, source: anytype, options: ParseOptions) !S2 {
        const s2a = std.json.innerParse(S2a, alloc, source, options) catch |err| {
            return .{ .err = @errorName(err) };
        };
        return .{ .id = s2a.id };
    }    
};

// This is the struct for parsing into.
const S2a = struct {
    id:  u32,
};


test "test1" {
    const str1 = \\{ "id": 123 }
    ;
    var res1 = std.json.parseFromSlice(U1, std.testing.allocator, str1, .{}) catch |err| {
        std.debug.print("Parse error: {}\n", .{err});
        return;
    };
    res1.deinit();

    // This triggers an assert in std.json.parseFromTokenSourceLeaky() at line 151.
    // const str2 = \\{ "idx": "123" }
    // ;
    // var res2 = std.json.parseFromSlice(U1, std.testing.allocator, str2, .{}) catch |err| {
    //     std.debug.print("parseFromSlice error: {}\n", .{err});
    //     return;
    // };
    // res2.deinit();

}

const IdType = union(enum) {
    num: i64,
    str: []const u8,

    // Custom JSON parsing when the parser encounters a field of the IdType type.
    pub fn jsonParse(allocator: Allocator, source: *std.json.Scanner, options: std.json.ParseOptions) !IdType {
        switch (try source.peekNextTokenType()) {
            .number => {
                const num = try std.json.innerParse(i64, allocator, source, options);
                return .{ .num = num };
            },
            .string => {
                const str = try std.json.innerParse([]const u8, allocator, source, options);
                return .{ .str = str };
            },
            else => return error.InvalidCharacter
        }

        // const token: std.json.Token = try source.next();
        // // scanner already parsed the value body into Token.
        // if (token == .number) {
        //     return IdType{ .num = try std.fmt.parseInt(i64, token.number, 10) };
        // } else if (token == .string) {
        //     const str = try std.json.innerParse([]const u8, allocator, source, options);
        //     return IdType{ .str = str };
        //     // return IdType{ .str = token.string };
        // }
        // return error.InvalidCharacter;
    }    
};

const Foo = struct {
    // id: std.json.Value,
    id: IdType,
    // id: i64,
    // id: []const u8,
};


/// A command line tool that reads dependency data from file and
/// does topological sort using the Toposort library.
/// This serves as an example to exercise the Toposort library API.
pub fn main() !void {
    {
        var args = try CmdArgs.init(g_allocator);
        defer args.deinit();
        args.parse() catch |err| {
            std.debug.print("Error in parsing command arguments. {}\n", .{err});
            usage(args);
            return;
        };

        const data = read_file(args.msg_file) catch |err| {
            std.debug.print("Error in reading the message file. {}\n", .{err});
            usage(args);
            return;
        };
        defer g_allocator.free(data);
        const req = try zigjr.Request.init(g_allocator, data);
        std.debug.print("req: {any}\n", .{req.body});
        defer req.deinit();

        const res0 = try req.response(g_allocator, "10");
        std.debug.print("res: {s}\n", .{res0});
        g_allocator.free(res0);

        if (req.has_error()) {
            const res = try req.response_error(g_allocator);
            std.debug.print("res: {s}\n", .{res});
            g_allocator.free(res);
        } else {
            const res = try req.response(g_allocator, "15");
            std.debug.print("res: {s}\n", .{res});
            g_allocator.free(res);
        }

    }

    if (gpa.detectLeaks()) {
        std.debug.print("Memory leak detected!\n", .{});
    }    
}

fn read_file(data_file: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(data_file, .{ .mode = .read_only });
    defer file.close();
    const file_size = (try file.stat()).size;
    const file_data = file.readToEndAlloc(g_allocator, file_size);
    return file_data;
}

fn usage(args: CmdArgs) void {
    const program_name = std.fs.path.basename(args.program);
    std.debug.print(
        \\
        \\Usage:
        \\  {s} --msg data.json [--verbose]
        \\
        \\      --msg data.json  - read in the JSON-RPC 2.0 message file.
        \\      --verbose  - prints processing messages.
        \\
        , .{program_name});
}

// Poorman's quick and dirty command line argument parsing.
const CmdArgs = struct {
    const Self = @This();

    arg_itr:        ArgIterator,
    program:        []const u8,
    msg_file:       []const u8,

    fn init(allocator: Allocator) !CmdArgs {
        var args = CmdArgs {
            .arg_itr = try std.process.argsWithAllocator(allocator),
            .program = "",
            .msg_file = "data.json",   // default to data.json in the working dir.
        };
        var argv = args.arg_itr;
        args.program = argv.next() orelse "";
        return args;
    }

    fn parse(self: *Self) !void {
        var argv = self.arg_itr;
        while (argv.next())|argz| {
            const arg = std.mem.sliceTo(argz, 0);
            if (std.mem.eql(u8, arg, "--msg")) {
                self.msg_file = std.mem.sliceTo(argv.next(), 0) orelse "data.json";
            }
        }
    }

    fn deinit(self: *CmdArgs) void {
        self.arg_itr.deinit();
    }

};


