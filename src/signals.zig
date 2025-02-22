const std = @import("std");
const builtin = @import("builtin");

pub usingnamespace switch (builtin.os.tag) {
    .linux => struct {
        const c = @cImport({
            @cInclude("setjmp.h");
        });

        var jmp: c.jmp_buf = undefined;
        var did_segfault: bool = false;

        fn handler(sig: c_int) callconv(.C) void {
            _ = sig;
            did_segfault = true;
            c.longjmp(&jmp, 1);
        }

        pub fn didSegfault() bool {
            return did_segfault;
        }

        pub fn segfaultGuard() void {
            if (c.setjmp(&jmp) == 1) return;

            did_segfault = false;

            var mask: std.os.linux.sigset_t = std.os.linux.empty_sigset;
            std.os.linux.sigaddset(&mask, std.os.linux.SIG.SEGV);
            const sigaction: std.os.linux.Sigaction = .{
                .handler = .{ .handler = handler },
                .mask = mask,
                .flags = std.os.linux.SA.RESETHAND,
            };
            _ = std.os.linux.sigaction(std.os.linux.SIG.SEGV, &sigaction, null);
        }
    },
    else => struct {
        pub fn didSegfault() bool {
            return false;
        }

        pub fn segfaultGuard() void {}
    },
};
