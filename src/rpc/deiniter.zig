// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William W. Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");


/// Capture the calling of an object's deinit() in the uniform Deiniter object.
pub const Deiniter = struct {
    impl_ptr:   *anyopaque,
    deinit_fn:  *const fn(impl_ptr: *anyopaque) void,

    pub fn implBy(impl_obj: anytype) @This() {
        const Thunk = struct {
            fn deinit(impl_ptr: *anyopaque) void {
                const impl: @TypeOf(impl_obj) = @ptrCast(@alignCast(impl_ptr));
                impl.deinit();
            }
        };

        return .{
            .impl_ptr = impl_obj,
            .deinit_fn = Thunk.deinit,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.deinit_fn(self.impl_ptr);
    }
};

/// Capture the allocator and memory to free later.
pub fn FreeFor(T: type) type {
    return struct {
        alloc:  std.mem.Allocator = undefined,
        memory: ?T = null,

        pub fn init(alloc: std.mem.Allocator, memory: ?T) @This() {
            return .{
                .alloc = alloc,
                .memory = memory,
            };
        }

        pub fn deinit(self: *@This()) void {
            if (self.memory) |mem_ptr| self.alloc.free(mem_ptr);
        }
    };
}


