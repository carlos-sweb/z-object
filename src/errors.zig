const std = @import("std");

/// Error types for ZObject operations
pub const ZObjectError = error{
    OutOfMemory,
    PropertyNotFound,
    PropertyNotWritable,
    PropertyNotConfigurable,
    ObjectIsFrozen,
    ObjectNotExtensible,
    InvalidDescriptor,
    InvalidState,
    PrototypeCycle,
};

/// Context for error reporting
pub const ErrorContext = struct {
    message: []const u8,
    property: ?[]const u8 = null,

    pub fn format(self: ErrorContext, writer: *std.Io.Writer) !void {
        try writer.print("ZObjectError: {s}", .{self.message});
        if (self.property) |prop| {
            try writer.print(" (property: {s})", .{prop});
        }
    }
};
