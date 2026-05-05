const std = @import("std");

const Allocator = std.mem.Allocator;
const Config = @import("config.zig").Config;
const internal_os = @import("os/main.zig");

var cursor_mutex: std.Thread.Mutex = .{};
var cursor_key: ?[]u8 = null;
var cursor_next: usize = 0;

pub fn enabled(config: *const Config) bool {
    return config.@"session-backend" == .drift and config.@"drift-restore";
}

pub fn claimTabId(alloc: Allocator, config: *const Config, drift_host: ?[]const u8) ![]const u8 {
    cursor_mutex.lock();
    defer cursor_mutex.unlock();

    const key = try manifestKey(std.heap.page_allocator, config, drift_host);
    if (cursor_key) |current| {
        if (!std.mem.eql(u8, current, key)) {
            std.heap.page_allocator.free(current);
            cursor_key = key;
            cursor_next = 0;
        } else {
            std.heap.page_allocator.free(key);
        }
    } else {
        cursor_key = key;
        cursor_next = 0;
    }

    var manifest = try Manifest.load(alloc, config, drift_host);
    defer manifest.deinit(alloc);

    const index = cursor_next;
    cursor_next += 1;

    if (index < manifest.ids.items.len) {
        return try alloc.dupe(u8, manifest.ids.items[index]);
    }

    const id = try manifest.nextTabId(alloc);
    errdefer alloc.free(id);
    try manifest.ids.append(alloc, try alloc.dupe(u8, id));
    try manifest.save(alloc, config, drift_host);

    return id;
}

pub fn claimSplitId(alloc: Allocator, config: *const Config, tab_id: []const u8, drift_host: ?[]const u8) ![]const u8 {
    cursor_mutex.lock();
    defer cursor_mutex.unlock();

    var manifest = try Manifest.load(alloc, config, drift_host);
    defer manifest.deinit(alloc);

    const id = try manifest.nextSplitId(alloc, tab_id);
    errdefer alloc.free(id);
    try manifest.save(alloc, config, drift_host);

    return id;
}

pub fn restoreTabCount(alloc: Allocator, config: *const Config) !usize {
    if (!enabled(config)) return 1;

    var manifest = try Manifest.load(alloc, config, null);
    defer manifest.deinit(alloc);

    return @max(manifest.ids.items.len, 1);
}

pub fn removeTabId(alloc: Allocator, config: *const Config, id: []const u8, drift_host: ?[]const u8) !void {
    if (!enabled(config)) return;

    cursor_mutex.lock();
    defer cursor_mutex.unlock();

    var manifest = try Manifest.load(alloc, config, drift_host);
    defer manifest.deinit(alloc);

    for (manifest.ids.items, 0..) |candidate, index| {
        if (!std.mem.eql(u8, candidate, id)) continue;

        alloc.free(manifest.ids.orderedRemove(index));
        if (cursor_next > index) cursor_next -= 1;
        try manifest.save(alloc, config, drift_host);
        return;
    }
}

const Manifest = struct {
    ids: std.ArrayListUnmanaged([]const u8) = .empty,
    next_id: usize = 1,
    next_split_id: usize = 1,

    fn load(alloc: Allocator, config: *const Config, drift_host: ?[]const u8) !Manifest {
        const path = try manifestPath(alloc, config, drift_host);
        defer alloc.free(path);

        const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
            error.FileNotFound => return .{},
            else => return err,
        };
        defer file.close();

        const contents = try file.readToEndAlloc(alloc, 1024 * 64);
        defer alloc.free(contents);

        var result: Manifest = .{};
        errdefer result.deinit(alloc);

        var it = std.mem.splitScalar(u8, contents, '\n');
        while (it.next()) |line_raw| {
            const line = std.mem.trim(u8, line_raw, " \t\r");
            if (line.len == 0) continue;
            if (std.mem.startsWith(u8, line, "# next=")) {
                result.next_id = std.fmt.parseInt(usize, line["# next=".len..], 10) catch result.next_id;
                continue;
            }
            if (std.mem.startsWith(u8, line, "# next-split=")) {
                result.next_split_id = std.fmt.parseInt(usize, line["# next-split=".len..], 10) catch result.next_split_id;
                continue;
            }
            if (line[0] == '#') continue;

            try result.ids.append(alloc, try alloc.dupe(u8, line));
            result.noteId(line);
        }

        return result;
    }

    fn save(self: *const Manifest, alloc: Allocator, config: *const Config, drift_host: ?[]const u8) !void {
        const dir = try manifestDir(alloc);
        defer alloc.free(dir);
        try std.fs.cwd().makePath(dir);

        const path = try manifestPath(alloc, config, drift_host);
        defer alloc.free(path);

        var data: std.ArrayListUnmanaged(u8) = .empty;
        defer data.deinit(alloc);

        const writer = data.writer(alloc);
        try writer.print("# ghostty drift restore manifest v1\n", .{});
        const host = try effectiveHost(alloc, config, drift_host);
        defer alloc.free(host);

        try writer.print("# host={s}\n", .{host});
        try writer.print("# prefix={s}\n", .{config.@"drift-session-prefix"});
        try writer.print("# next={d}\n", .{self.next_id});
        try writer.print("# next-split={d}\n", .{self.next_split_id});
        for (self.ids.items) |id| {
            try writer.print("{s}\n", .{id});
        }

        try std.fs.cwd().writeFile(.{
            .sub_path = path,
            .data = data.items,
        });
    }

    fn deinit(self: *Manifest, alloc: Allocator) void {
        for (self.ids.items) |id| alloc.free(id);
        self.ids.deinit(alloc);
        self.* = .{};
    }

    fn nextTabId(self: *Manifest, alloc: Allocator) ![]const u8 {
        while (true) {
            const id = try std.fmt.allocPrint(alloc, "tab-{d}", .{self.next_id});
            self.next_id += 1;

            if (!self.contains(id)) return id;
            alloc.free(id);
        }
    }

    fn nextSplitId(self: *Manifest, alloc: Allocator, tab_id: []const u8) ![]const u8 {
        const id = try std.fmt.allocPrint(alloc, "{s}-split-{d}", .{
            tab_id,
            self.next_split_id,
        });
        self.next_split_id += 1;
        return id;
    }

    fn contains(self: *const Manifest, id: []const u8) bool {
        for (self.ids.items) |candidate| {
            if (std.mem.eql(u8, candidate, id)) return true;
        }
        return false;
    }

    fn noteId(self: *Manifest, id: []const u8) void {
        if (!std.mem.startsWith(u8, id, "tab-")) return;
        const n = std.fmt.parseInt(usize, id["tab-".len..], 10) catch return;
        self.next_id = @max(self.next_id, n + 1);
    }
};

fn manifestPath(alloc: Allocator, config: *const Config, drift_host: ?[]const u8) ![]u8 {
    const dir = try manifestDir(alloc);
    defer alloc.free(dir);

    const host_raw = try effectiveHost(alloc, config, drift_host);
    defer alloc.free(host_raw);

    const host = try sanitizeComponent(alloc, host_raw);
    defer alloc.free(host);

    const prefix = try sanitizeComponent(alloc, config.@"drift-session-prefix");
    defer alloc.free(prefix);

    const filename = try std.fmt.allocPrint(
        alloc,
        "{s}-{s}.manifest",
        .{ host, prefix },
    );
    defer alloc.free(filename);

    return std.fs.path.join(alloc, &.{ dir, filename });
}

fn manifestKey(alloc: Allocator, config: *const Config, drift_host: ?[]const u8) ![]u8 {
    const host = try effectiveHost(alloc, config, drift_host);
    defer alloc.free(host);

    return std.fmt.allocPrint(
        alloc,
        "{s}\n{s}",
        .{ host, config.@"drift-session-prefix" },
    );
}

fn effectiveHost(alloc: Allocator, config: *const Config, drift_host: ?[]const u8) ![]u8 {
    if (drift_host) |host| {
        if (host.len > 0) return try alloc.dupe(u8, host);
    }

    if (config.@"drift-host".len > 0) {
        return try alloc.dupe(u8, config.@"drift-host");
    }

    return try internal_os.hostname.get(alloc);
}

fn manifestDir(alloc: Allocator) ![]u8 {
    if (std.process.getEnvVarOwned(alloc, "XDG_STATE_HOME")) |state_home| {
        defer alloc.free(state_home);
        return try std.fs.path.join(alloc, &.{ state_home, "ghostty", "drift-restore" });
    } else |err| switch (err) {
        error.EnvironmentVariableNotFound => {},
        else => return err,
    }

    const home = try std.process.getEnvVarOwned(alloc, "HOME");
    defer alloc.free(home);
    return try std.fs.path.join(alloc, &.{ home, ".local", "state", "ghostty", "drift-restore" });
}

fn sanitizeComponent(alloc: Allocator, value: []const u8) ![]u8 {
    var result = try alloc.alloc(u8, value.len);
    errdefer alloc.free(result);

    for (value, 0..) |c, i| {
        result[i] = switch (c) {
            'a'...'z', 'A'...'Z', '0'...'9', '.', '_', '-' => c,
            else => '_',
        };
    }

    return result;
}

test "sanitize manifest path component" {
    const alloc = std.testing.allocator;
    const value = try sanitizeComponent(alloc, "ghostty/source drift");
    defer alloc.free(value);

    try std.testing.expectEqualStrings("ghostty_source_drift", value);
}

test "manifest tab IDs are monotonic" {
    const alloc = std.testing.allocator;

    var manifest: Manifest = .{};
    defer manifest.deinit(alloc);

    for (&[_][]const u8{ "tab-1", "tab-3" }) |id| {
        try manifest.ids.append(alloc, try alloc.dupe(u8, id));
        manifest.noteId(id);
    }

    const next = try manifest.nextTabId(alloc);
    defer alloc.free(next);

    try std.testing.expectEqualStrings("tab-4", next);
}

test "manifest split IDs are monotonic and not tab entries" {
    const alloc = std.testing.allocator;

    var manifest: Manifest = .{};
    defer manifest.deinit(alloc);

    const first = try manifest.nextSplitId(alloc, "tab-9");
    defer alloc.free(first);
    const second = try manifest.nextSplitId(alloc, "tab-9");
    defer alloc.free(second);

    try std.testing.expectEqualStrings("tab-9-split-1", first);
    try std.testing.expectEqualStrings("tab-9-split-2", second);
    try std.testing.expectEqual(@as(usize, 0), manifest.ids.items.len);
}
