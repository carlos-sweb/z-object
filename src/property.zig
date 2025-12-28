const std = @import("std");

/// ECMAScript Property Descriptor
/// Defines the characteristics of an object property
pub const PropertyDescriptor = struct {
    value: ?*anyopaque = null,
    writable: bool = true,
    enumerable: bool = true,
    configurable: bool = true,

    // For getters/setters (optional in v1)
    get: ?*const fn () anyerror!*anyopaque = null,
    set: ?*const fn (*anyopaque) anyerror!void = null,

    /// Check if this is a data descriptor
    pub fn isDataDescriptor(self: *const PropertyDescriptor) bool {
        return self.value != null or self.writable;
    }

    /// Check if this is an accessor descriptor
    pub fn isAccessorDescriptor(self: *const PropertyDescriptor) bool {
        return self.get != null or self.set != null;
    }

    /// Validate descriptor consistency
    pub fn validate(self: *const PropertyDescriptor) !void {
        // Data and accessor descriptors are mutually exclusive
        if (self.isDataDescriptor() and self.isAccessorDescriptor()) {
            return error.InvalidDescriptor;
        }
    }

    /// Create a default data descriptor
    pub fn dataDescriptor() PropertyDescriptor {
        return .{
            .value = null,
            .writable = true,
            .enumerable = true,
            .configurable = true,
            .get = null,
            .set = null,
        };
    }

    /// Create a default accessor descriptor
    pub fn accessorDescriptor() PropertyDescriptor {
        return .{
            .value = null,
            .writable = false,
            .enumerable = true,
            .configurable = true,
            .get = null,
            .set = null,
        };
    }
};

/// Property with generic type and descriptor
pub fn Property(comptime T: type) type {
    return struct {
        value: T,
        descriptor: PropertyDescriptor,

        const Self = @This();

        /// Initialize property with default descriptor
        pub fn init(value: T) Self {
            return .{
                .value = value,
                .descriptor = PropertyDescriptor.dataDescriptor(),
            };
        }

        /// Initialize property with custom descriptor
        pub fn initWithDescriptor(value: T, desc: PropertyDescriptor) Self {
            return .{
                .value = value,
                .descriptor = desc,
            };
        }

        /// Clone property (shallow copy of value)
        pub fn clone(self: *const Self) Self {
            return .{
                .value = self.value,
                .descriptor = self.descriptor,
            };
        }

        /// Check if property is writable
        pub fn isWritable(self: *const Self) bool {
            return self.descriptor.writable;
        }

        /// Check if property is enumerable
        pub fn isEnumerable(self: *const Self) bool {
            return self.descriptor.enumerable;
        }

        /// Check if property is configurable
        pub fn isConfigurable(self: *const Self) bool {
            return self.descriptor.configurable;
        }
    };
}
