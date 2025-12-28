const std = @import("std");

/// Error types for ZObject operations
pub const ZObjectError = error{
    OutOfMemory,
    PropertyNotFound,
    PropertyNotWritable,
    PropertyNotConfigurable,
    ObjectIsFrozen,
    ObjectIsSealed,
    ObjectNotExtensible,
    InvalidDescriptor,
    InvalidState,
    PrototypeCycle,
    KeyAlreadyExists,
};

/// Context for error reporting
pub const ErrorContext = struct {
    message: []const u8,
    property: ?[]const u8 = null,

    pub fn format(
        self: ErrorContext,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("ZObjectError: {s}", .{self.message});
        if (self.property) |prop| {
            try writer.print(" (property: {s})", .{prop});
        }
    }
};
