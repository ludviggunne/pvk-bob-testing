const std = @import("std");
const builtin = @import("builtin");
const Client = @import("Client.zig");
const rt_api = @import("rt_api.zig");
const imgui = @import("imgui");
const gui = @import("graphics/gui.zig");
const glfw = gui.glfw;
const gl = gui.gl;
const Context = @import("Context.zig");
const signals = @import("signals.zig");

const lib_suffix = switch (builtin.os.tag) {
    .windows => ".dll",
    .linux => ".so",
    .macos => ".dylib",
    else => @compileError("unsupported platform"),
};

const lib_path = "zig-out/lib/";

const os_tag = @import("builtin").os.tag;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var args = try std.process.argsWithAllocator(gpa.allocator());
    defer args.deinit();

    var context = Context.init(gpa.allocator());
    defer context.deinit();

    var visualizers = std.ArrayList([*c]const u8).init(gpa.allocator());
    defer {
        clearVisualizers(&visualizers);
        visualizers.deinit();
    }

    try getVisualizers(&visualizers);

    try mainGui(&context, &visualizers);
}

/// Print error and code on GLFW errors.
fn errorCallback(err: c_int, msg: [*c]const u8) callconv(.C) void {
    std.log.err("Error code: {} message: {s}", .{ err, msg });
}

fn getVisualizers(list: *std.ArrayList([*c]const u8)) !void {
    std.log.info("looking for visualizers in {s}", .{lib_path});

    clearVisualizers(list);

    try list.append(try list.allocator.dupeZ(u8, "<none>"));

    const dir = try std.fs.cwd().openDir(lib_path, .{ .iterate = true });

    var iter = dir.iterate();

    while (try iter.next()) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, lib_suffix))
            continue;
        const name = std.mem.sliceTo(entry.name, '.');
        std.log.info("found visualizer {s}", .{name});
        const nameZ = try list.allocator.dupeZ(u8, name);
        try list.append(nameZ);
    }
}

fn clearVisualizers(list: *std.ArrayList([*c]const u8)) void {
    for (list.items) |name| {
        var slice: [:0]const u8 = undefined;
        slice.ptr = @ptrCast(name);
        slice.len = std.mem.len(name);
        list.allocator.free(slice);
    }
    list.clearRetainingCapacity();
}

fn mainGui(context: *Context, visualizers: *std.ArrayList([*c]const u8)) !void {
    _ = glfw.glfwSetErrorCallback(errorCallback);
    if (glfw.glfwInit() == glfw.GLFW_FALSE) {
        std.log.err("Failed to init GLFW", .{});
        return;
    }
    defer glfw.glfwTerminate();

    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MINOR, 3);
    glfw.glfwWindowHint(glfw.GLFW_OPENGL_PROFILE, glfw.GLFW_OPENGL_CORE_PROFILE);
    if (os_tag == .macos) {
        glfw.glfwWindowHint(glfw.GLFW_OPENGL_FORWARD_COMPAT, glfw.GLFW_TRUE);
    }

    const window = glfw.glfwCreateWindow(
        800,
        600,
        "project_name",
        null,
        null,
    ) orelse {
        std.log.err("Failed to create window", .{});
        return;
    };
    defer glfw.glfwDestroyWindow(window);
    glfw.glfwMakeContextCurrent(window);
    if (gl.gladLoadGLLoader(@ptrCast(&glfw.glfwGetProcAddress)) == 0) {
        std.log.err("Failed to load gl", .{});
        return;
    }
    gl.glViewport(0, 0, 800, 600);
    glfw.glfwSwapInterval(1);

    const gui_context = imgui.CreateContext();
    imgui.SetCurrentContext(gui_context);
    {
        const im_io = imgui.GetIO();
        im_io.IniFilename = null;
        im_io.ConfigFlags = imgui.ConfigFlags.with(
            im_io.ConfigFlags,
            .{
                .NavEnableKeyboard = true,
                .NavEnableGamepad = true,
                .DockingEnable = true,
                .ViewportsEnable = true,
            },
        );
    }

    imgui.StyleColorsLight();

    _ = gui.ImGui_ImplGlfw_InitForOpenGL(window, true);
    switch (gui.populate_dear_imgui_opengl_symbol_table(@ptrCast(&gui.get_proc_address))) {
        .ok => {},
        .init_error, .open_library => {
            std.log.err("Load OpenGL failed", .{});
            return;
        },
        .opengl_version_unsupported => {
            std.log.warn("Tried to run on unsupported OpenGL version", .{});
            return;
        },
    }
    _ = gui.ImGui_ImplOpenGL3_Init("#version 330 core");

    var running = true;

    while (running) {
        glfw.glfwPollEvents();
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);
        gl.glClearColor(0.0, 0.0, 0.0, 1.0);

        gui.ImGui_ImplOpenGL3_NewFrame();
        gui.ImGui_ImplGlfw_NewFrame();
        imgui.NewFrame();
        _ = imgui.Begin("bob");

        var selection: c_int = 0;
        // imgui.SeparatorText("Select visualizer");
        if (imgui.Combo_Str_arr("Select visualizer", &selection, @ptrCast(visualizers.items.ptr), @intCast(visualizers.items.len))) {
            if (context.client) |*client| {
                std.log.info("unloading visualizer", .{});
                signals.segfaultGuard();
                client.destroy();
                if (signals.didSegfault()) {
                    std.log.err("visualizer received SIGSEGV in destroy()", .{});
                }
                client.unload();
                context.client = null;
                context.gui_state.clear();
            }

            if (selection > 0) {
                var buf = std.ArrayList(u8).init(visualizers.allocator);
                defer buf.deinit();
                try buf.writer().writeAll(lib_path);
                try buf.writer().writeAll(std.mem.span(visualizers.items[@intCast(selection)]));
                try buf.writer().writeAll(lib_suffix);

                std.log.info("loading visualizer {s}", .{buf.items});
                context.client = Client.load(buf.items) catch |e| blk: {
                    std.log.err("failed to load {s}: {s}", .{ buf.items, @errorName(e) });
                    break :blk null;
                };
                if (context.client) |*client| {
                    rt_api.fill(@ptrCast(context), client.api.api);
                    client.create();
                }
            }
        }

        imgui.SameLine();
        if (imgui.Button("Refresh")) {
            try getVisualizers(visualizers);
        }

        if (context.client) |*client| {
            signals.segfaultGuard();
            const info = client.api.get_info()[0];
            if (signals.didSegfault()) {
                std.log.err("visualizer received SIGSEGV in get_info()", .{});
                client.unload();
                context.client = null;
            } else {
                imgui.SeparatorText(info.name);
                // imgui.SameLine();
                if (imgui.Button("Unload")) {
                    std.log.info("unloading visualizer", .{});
                    signals.segfaultGuard();
                    client.destroy();
                    if (signals.didSegfault()) {
                        std.log.err("visualizer received SIGSEGV in destroy()", .{});
                    }
                    client.unload();
                    context.client = null;
                    context.gui_state.clear();
                } else {
                    context.gui_state.update();
                    imgui.SeparatorText("Description");
                    imgui.Text(info.description);
                }
            }
        }

        imgui.End();
        imgui.EndFrame();

        imgui.Render();
        if (context.client) |*client| {
            signals.segfaultGuard();
            client.update();
            if (signals.didSegfault()) {
                std.log.err("visualizer received SIGSEGV in update()", .{});
                client.unload();
                context.client = null;
            }
        }

        gui.ImGui_ImplOpenGL3_RenderDrawData(imgui.GetDrawData());

        const saved_context = glfw.glfwGetCurrentContext();
        imgui.UpdatePlatformWindows();
        imgui.RenderPlatformWindowsDefault();
        glfw.glfwMakeContextCurrent(saved_context);

        running = glfw.glfwWindowShouldClose(window) == glfw.GLFW_FALSE;
        glfw.glfwSwapBuffers(window);
    }
}
