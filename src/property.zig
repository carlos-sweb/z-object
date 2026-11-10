const std = @import("std");
const errors = @import("errors.zig");

/// ECMAScript Property Descriptor
/// Compacted to 4 bytes (eliminating legacy unused function/value pointers).
pub const PropertyDescriptor = struct {
    writable: bool = true,
    enumerable: bool = true,
    configurable: bool = true,
    is_accessor: bool = false,

    /// Check if this is a data descriptor
    pub fn isDataDescriptor(self: *const PropertyDescriptor) bool {
        return !self.is_accessor;
    }

    /// Check if this is an accessor descriptor
    pub fn isAccessorDescriptor(self: *const PropertyDescriptor) bool {
        return self.is_accessor;
    }

    /// Validate descriptor consistency
    pub fn validate(self: *const PropertyDescriptor) errors.ZObjectError!void {
        // Data and accessor descriptors are mutually exclusive
        if (self.is_accessor and self.writable) {
            return errors.ZObjectError.InvalidDescriptor;
        }
    }

    /// Create a default data descriptor
    pub fn dataDescriptor() PropertyDescriptor {
        return .{
            .writable = true,
            .enumerable = true,
            .configurable = true,
            .is_accessor = false,
        };
    }

    /// Create a default accessor descriptor
    pub fn accessorDescriptor() PropertyDescriptor {
        return .{
            .writable = false,
            .enumerable = true,
            .configurable = true,
            .is_accessor = true,
        };
    }
};

/// Property with generic type and compact descriptor
pub fn Property(comptime T: type) type {
    return struct {
        value: T,
        /// JS accessor property slots (`{ get x() {}, set x(v) {} }`),
        /// typed in T so they can hold real function values with captured
        /// context. A property with either slot non-null is an accessor;
        /// `value` then holds a caller-supplied placeholder for data-only
        /// consumers (JSON writers, Object.assign) that can't invoke functions.
        getter: ?T = null,
        setter: ?T = null,
        descriptor: PropertyDescriptor = PropertyDescriptor.dataDescriptor(),

        const Self = @This();

        /// True when this property is a JS accessor (has a getter and/or
        /// setter) rather than an ordinary data property.
        pub fn isAccessor(self: *const Self) bool {
            return self.getter != null or self.setter != null or self.descriptor.is_accessor;
        }

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

        /// Clone property (shallow copy of value and accessors)
        pub fn clone(self: *const Self) Self {
            return .{
                .value = self.value,
                .getter = self.getter,
                .setter = self.setter,
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
