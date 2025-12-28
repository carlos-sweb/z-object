const std = @import("std");
const Allocator = std.mem.Allocator;
const property_mod = @import("property.zig");
const errors_mod = @import("errors.zig");

/// Generic ECMAScript-compatible Object implementation
pub fn ZObject(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Map of properties (string -> Property)
        properties: std.StringHashMap(property_mod.Property(T)),

        /// Prototype chain (can be null)
        prototype: ?*Self,

        /// Allocator for memory management
        allocator: Allocator,

        /// Object state flags
        is_frozen: bool,
        is_sealed: bool,
        is_extensible: bool,

        /// Initialize a new ZObject
        pub fn init(allocator: Allocator) Self {
            return .{
                .properties = std.StringHashMap(property_mod.Property(T)).init(allocator),
                .prototype = null,
                .allocator = allocator,
                .is_frozen = false,
                .is_sealed = false,
                .is_extensible = true,
            };
        }

        /// Deinitialize and free all resources
        pub fn deinit(self: *Self) void {
            // Free all keys (strings are duplicated)
            var it = self.properties.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            self.properties.deinit();
        }

        // ===== Instance Methods =====

        /// Set property with validations (labeled block example 1)
        pub fn set(self: *Self, key: []const u8, value: T) !void {
            setter: {
                // Check if frozen
                if (self.is_frozen) {
                    return errors_mod.ZObjectError.ObjectIsFrozen;
                }

                // Check if property exists and is writable
                if (self.properties.get(key)) |prop| {
                    if (!prop.descriptor.writable) {
                        return errors_mod.ZObjectError.PropertyNotWritable;
                    }
                    // Property exists and is writable, continue to update
                    break :setter;
                }

                // Check if extensible for new properties
                if (!self.is_extensible) {
                    return errors_mod.ZObjectError.ObjectNotExtensible;
                }
            }

            // Update or create property
            if (self.properties.getEntry(key)) |entry| {
                // Update existing property value
                entry.value_ptr.value = value;
            } else {
                // Create new property with duplicated key
                const key_copy = try self.allocator.dupe(u8, key);
                errdefer self.allocator.free(key_copy);

                try self.properties.put(key_copy, property_mod.Property(T).init(value));
            }
        }

        /// Get property with prototype chain lookup
        pub fn get(self: *const Self, key: []const u8) ?T {
            if (self.properties.get(key)) |prop| {
                return prop.value;
            }
            return null;
        }

        /// Delete property (labeled block example 2)
        pub fn delete(self: *Self, key: []const u8) !bool {
            deleter: {
                // Check if frozen
                if (self.is_frozen) {
                    return errors_mod.ZObjectError.ObjectIsFrozen;
                }

                // Check if property exists
                const entry = self.properties.getEntry(key) orelse {
                    return false; // Property doesn't exist
                };

                // Check if configurable
                if (!entry.value_ptr.descriptor.configurable) {
                    return errors_mod.ZObjectError.PropertyNotConfigurable;
                }

                break :deleter;
            }

            // Remove and free key
            if (self.properties.fetchRemove(key)) |removed| {
                self.allocator.free(removed.key);
                return true;
            }

            return false;
        }

        /// Check if property exists (own property only)
        pub fn hasOwnProperty(self: *const Self, key: []const u8) bool {
            return self.properties.contains(key);
        }

        /// Check if property exists (includes prototype chain)
        pub fn has(self: *const Self, key: []const u8) bool {
            if (self.hasOwnProperty(key)) {
                return true;
            }
            // Check in prototype chain
            return self.hasInChain(key);
        }

        /// Get number of own properties
        pub fn size(self: *const Self) usize {
            return self.properties.count();
        }

        /// Clear all properties (labeled block example 3)
        pub fn clear(self: *Self) !void {
            clearer: {
                if (self.is_frozen) {
                    return errors_mod.ZObjectError.ObjectIsFrozen;
                }

                // Check if any property is non-configurable
                var it = self.properties.iterator();
                while (it.next()) |entry| {
                    if (!entry.value_ptr.descriptor.configurable) {
                        return errors_mod.ZObjectError.PropertyNotConfigurable;
                    }
                }

                break :clearer;
            }

            // Free all keys
            var it = self.properties.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }

            // Clear the map
            self.properties.clearRetainingCapacity();
        }

        /// Check if property is enumerable
        pub fn propertyIsEnumerable(self: *const Self, key: []const u8) bool {
            if (self.properties.get(key)) |prop| {
                return prop.descriptor.enumerable;
            }
            return false;
        }

        /// Convert to string representation
        pub fn toString(self: *const Self, allocator: Allocator) ![]u8 {
            _ = self;
            return try allocator.dupe(u8, "[object Object]");
        }

        /// Get primitive value
        pub fn valueOf(self: *const Self) *const Self {
            return self;
        }

        /// Check if this object is prototype of another
        pub fn isPrototypeOf(self: *const Self, other: *const Self) bool {
            var current = other.prototype;
            while (current) |proto| {
                if (proto == self) {
                    return true;
                }
                current = proto.prototype;
            }
            return false;
        }

        // ===== Static Methods =====

        /// Object.keys() - Get array of enumerable property keys
        pub fn keys(self: *const Self, allocator: Allocator) ![][]const u8 {
            var key_list: std.ArrayList([]const u8) = .{};
            errdefer key_list.deinit(allocator);

            var it = self.properties.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.descriptor.enumerable) {
                    try key_list.append(allocator, entry.key_ptr.*);
                }
            }

            return try key_list.toOwnedSlice(allocator);
        }

        /// Object.values() - Get array of enumerable property values
        pub fn values(self: *const Self, allocator: Allocator) ![]T {
            var value_list: std.ArrayList(T) = .{};
            errdefer value_list.deinit(allocator);

            var it = self.properties.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.descriptor.enumerable) {
                    try value_list.append(allocator, entry.value_ptr.value);
                }
            }

            return try value_list.toOwnedSlice(allocator);
        }

        /// Entry type for Object.entries()
        pub const Entry = struct {
            key: []const u8,
            value: T,
        };

        /// PropertyDefinition for defineProperties()
        pub const PropertyDefinition = struct {
            key: []const u8,
            value: T,
            descriptor: property_mod.PropertyDescriptor,
        };

        /// Object.entries() - Get array of [key, value] pairs
        pub fn entries(self: *const Self, allocator: Allocator) ![]Entry {
            var entry_list: std.ArrayList(Entry) = .{};
            errdefer entry_list.deinit(allocator);

            var it = self.properties.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.descriptor.enumerable) {
                    try entry_list.append(allocator, .{
                        .key = entry.key_ptr.*,
                        .value = entry.value_ptr.value,
                    });
                }
            }

            return try entry_list.toOwnedSlice(allocator);
        }

        /// Object.assign() - Copy enumerable properties (labeled block example 4)
        pub fn assign(target: *Self, sources: []const *const Self) !void {
            for (sources) |source| {
                assigner: {
                    if (target.is_frozen) {
                        return errors_mod.ZObjectError.ObjectIsFrozen;
                    }

                    var it = source.properties.iterator();
                    while (it.next()) |entry| {
                        if (!entry.value_ptr.descriptor.enumerable) continue;

                        // Set property on target
                        try target.set(entry.key_ptr.*, entry.value_ptr.value);
                    }

                    break :assigner;
                }
            }
        }

        /// Object.create() - Create object with specific prototype
        pub fn create(allocator: Allocator, proto: ?*Self) !Self {
            var obj = Self.init(allocator);
            obj.prototype = proto;
            return obj;
        }

        /// Object.freeze() - Freeze object (labeled block example 5)
        pub fn freeze(self: *Self) void {
            freezer: {
                self.is_frozen = true;
                self.is_sealed = true;
                self.is_extensible = false;

                var it = self.properties.valueIterator();
                while (it.next()) |prop| {
                    prop.descriptor.writable = false;
                    prop.descriptor.configurable = false;
                }

                break :freezer;
            }
        }

        /// Object.seal() - Seal object
        pub fn seal(self: *Self) void {
            self.is_sealed = true;
            self.is_extensible = false;

            var it = self.properties.valueIterator();
            while (it.next()) |prop| {
                prop.descriptor.configurable = false;
            }
        }

        /// Object.preventExtensions() - Prevent adding new properties
        pub fn preventExtensions(self: *Self) void {
            self.is_extensible = false;
        }

        /// Object.isFrozen()
        pub fn isFrozen(self: *const Self) bool {
            if (!self.is_frozen) return false;

            // All properties must be non-writable and non-configurable
            var it = self.properties.valueIterator();
            while (it.next()) |prop| {
                if (prop.descriptor.writable or prop.descriptor.configurable) {
                    return false;
                }
            }

            return true;
        }

        /// Object.isSealed()
        pub fn isSealed(self: *const Self) bool {
            if (!self.is_sealed or self.is_extensible) return false;

            // All properties must be non-configurable
            var it = self.properties.valueIterator();
            while (it.next()) |prop| {
                if (prop.descriptor.configurable) {
                    return false;
                }
            }

            return true;
        }

        /// Object.isExtensible()
        pub fn isExtensible(self: *const Self) bool {
            return self.is_extensible;
        }

        /// Object.getOwnPropertyNames() - Get all property names (including non-enumerable)
        pub fn getOwnPropertyNames(self: *const Self, allocator: Allocator) ![][]const u8 {
            var name_list: std.ArrayList([]const u8) = .{};
            errdefer name_list.deinit(allocator);

            var it = self.properties.keyIterator();
            while (it.next()) |key| {
                try name_list.append(allocator, key.*);
            }

            return try name_list.toOwnedSlice(allocator);
        }

        /// Object.fromEntries() - Create object from entries
        pub fn fromEntries(allocator: Allocator, entry_list: []const Entry) !Self {
            var obj = Self.init(allocator);
            errdefer obj.deinit();

            for (entry_list) |entry| {
                try obj.set(entry.key, entry.value);
            }

            return obj;
        }

        // ===== Property Descriptor Methods =====

        /// Object.defineProperty() - Define property with descriptor (labeled block example 6)
        pub fn defineProperty(
            self: *Self,
            key: []const u8,
            value: T,
            descriptor: property_mod.PropertyDescriptor,
        ) !void {
            definer: {
                // Validate descriptor
                try descriptor.validate();

                // Check if object is extensible for new properties
                if (!self.hasOwnProperty(key) and !self.is_extensible) {
                    return errors_mod.ZObjectError.ObjectNotExtensible;
                }

                // Check if existing property is configurable
                if (self.properties.get(key)) |existing| {
                    if (!existing.descriptor.configurable) {
                        return errors_mod.ZObjectError.PropertyNotConfigurable;
                    }
                }

                break :definer;
            }

            // Create or update property
            if (self.properties.getEntry(key)) |entry| {
                entry.value_ptr.value = value;
                entry.value_ptr.descriptor = descriptor;
            } else {
                const key_copy = try self.allocator.dupe(u8, key);
                errdefer self.allocator.free(key_copy);

                try self.properties.put(key_copy, property_mod.Property(T).initWithDescriptor(value, descriptor));
            }
        }

        /// Object.defineProperties() - Define multiple properties
        pub fn defineProperties(
            self: *Self,
            props: []const PropertyDefinition,
        ) !void {
            for (props) |prop| {
                try self.defineProperty(prop.key, prop.value, prop.descriptor);
            }
        }

        /// Object.getOwnPropertyDescriptor()
        pub fn getOwnPropertyDescriptor(
            self: *const Self,
            key: []const u8,
        ) ?PropertyDescriptor {
            if (self.properties.get(key)) |prop| {
                return prop.descriptor;
            }
            return null;
        }

        /// Object.getOwnPropertyDescriptors()
        pub fn getOwnPropertyDescriptors(
            self: *const Self,
            allocator: Allocator,
        ) !std.StringHashMap(property_mod.PropertyDescriptor) {
            var desc_map = std.StringHashMap(property_mod.PropertyDescriptor).init(allocator);
            errdefer desc_map.deinit();

            var it = self.properties.iterator();
            while (it.next()) |entry| {
                try desc_map.put(entry.key_ptr.*, entry.value_ptr.descriptor);
            }

            return desc_map;
        }

        /// Update descriptor of existing property
        pub fn updateDescriptor(
            self: *Self,
            key: []const u8,
            descriptor: property_mod.PropertyDescriptor,
        ) !void {
            const entry = self.properties.getEntry(key) orelse {
                return errors_mod.ZObjectError.PropertyNotFound;
            };

            if (!entry.value_ptr.descriptor.configurable) {
                return errors_mod.ZObjectError.PropertyNotConfigurable;
            }

            try descriptor.validate();
            entry.value_ptr.descriptor = descriptor;
        }

        // ===== Prototype Chain Methods =====

        /// Object.setPrototypeOf()
        pub fn setPrototype(self: *Self, proto: ?*Self) !void {
            // Check for cycles
            if (proto) |p| {
                if (p == self) {
                    return errors_mod.ZObjectError.PrototypeCycle;
                }
                // Check if self is in proto's chain
                var current = p.prototype;
                while (current) |curr| {
                    if (curr == self) {
                        return errors_mod.ZObjectError.PrototypeCycle;
                    }
                    current = curr.prototype;
                }
            }

            if (!self.is_extensible and self.prototype != proto) {
                return errors_mod.ZObjectError.ObjectNotExtensible;
            }

            self.prototype = proto;
        }

        /// Object.getPrototypeOf()
        pub fn getPrototype(self: *const Self) ?*Self {
            return self.prototype;
        }

        /// Lookup property in prototype chain (labeled block example 7)
        pub fn lookupInChain(self: *const Self, key: []const u8) ?T {
            var current: ?*const Self = self;

            chain_walker: {
                while (current) |obj| {
                    if (obj.properties.get(key)) |prop| {
                        if (prop.descriptor.enumerable) {
                            return prop.value;
                        }
                    }
                    current = obj.prototype;
                }
                break :chain_walker;
            }

            return null;
        }

        /// Check if property exists in chain
        pub fn hasInChain(self: *const Self, key: []const u8) bool {
            var current = self.prototype;
            while (current) |proto| {
                if (proto.hasOwnProperty(key)) {
                    return true;
                }
                current = proto.prototype;
            }
            return false;
        }

        /// Get all properties in chain
        pub fn getAllPropertiesInChain(
            self: *const Self,
            allocator: Allocator,
        ) ![][]const u8 {
            var prop_set = std.StringHashMap(void).init(allocator);
            defer prop_set.deinit();

            // Add own properties
            var it = self.properties.keyIterator();
            while (it.next()) |key| {
                try prop_set.put(key.*, {});
            }

            // Add prototype chain properties
            var current = self.prototype;
            while (current) |proto| {
                var proto_it = proto.properties.keyIterator();
                while (proto_it.next()) |key| {
                    try prop_set.put(key.*, {});
                }
                current = proto.prototype;
            }

            // Convert to array
            var prop_list: std.ArrayList([]const u8) = .{};
            errdefer prop_list.deinit(allocator);

            var set_it = prop_set.keyIterator();
            while (set_it.next()) |key| {
                try prop_list.append(allocator, key.*);
            }

            return try prop_list.toOwnedSlice(allocator);
        }

        // ===== Iteration Methods =====

        /// forEach over enumerable properties
        pub fn forEach(
            self: *const Self,
            context: anytype,
            comptime callback: fn (@TypeOf(context), []const u8, T) void,
        ) void {
            var it = self.properties.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.descriptor.enumerable) {
                    callback(context, entry.key_ptr.*, entry.value_ptr.value);
                }
            }
        }

        /// map over properties (returns new object)
        pub fn map(
            self: *const Self,
            comptime U: type,
            context: anytype,
            comptime callback: fn (@TypeOf(context), []const u8, T) U,
        ) !ZObject(U) {
            var result = ZObject(U).init(self.allocator);
            errdefer result.deinit();

            var it = self.properties.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.descriptor.enumerable) {
                    const new_value = callback(context, entry.key_ptr.*, entry.value_ptr.value);
                    try result.set(entry.key_ptr.*, new_value);
                }
            }

            return result;
        }

        /// filter properties
        pub fn filter(
            self: *const Self,
            context: anytype,
            comptime predicate: fn (@TypeOf(context), []const u8, T) bool,
        ) !Self {
            var result = Self.init(self.allocator);
            errdefer result.deinit();

            var it = self.properties.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.descriptor.enumerable) {
                    if (predicate(context, entry.key_ptr.*, entry.value_ptr.value)) {
                        try result.set(entry.key_ptr.*, entry.value_ptr.value);
                    }
                }
            }

            return result;
        }

        /// reduce over properties
        pub fn reduce(
            self: *const Self,
            comptime U: type,
            initial: U,
            context: anytype,
            comptime callback: fn (@TypeOf(context), U, []const u8, T) U,
        ) U {
            var accumulator = initial;

            var it = self.properties.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.descriptor.enumerable) {
                    accumulator = callback(context, accumulator, entry.key_ptr.*, entry.value_ptr.value);
                }
            }

            return accumulator;
        }

        /// some - at least one property satisfies predicate
        pub fn some(
            self: *const Self,
            context: anytype,
            comptime predicate: fn (@TypeOf(context), []const u8, T) bool,
        ) bool {
            var it = self.properties.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.descriptor.enumerable) {
                    if (predicate(context, entry.key_ptr.*, entry.value_ptr.value)) {
                        return true;
                    }
                }
            }
            return false;
        }

        /// every - all properties satisfy predicate
        pub fn every(
            self: *const Self,
            context: anytype,
            comptime predicate: fn (@TypeOf(context), []const u8, T) bool,
        ) bool {
            var it = self.properties.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.descriptor.enumerable) {
                    if (!predicate(context, entry.key_ptr.*, entry.value_ptr.value)) {
                        return false;
                    }
                }
            }
            return true;
        }

        /// find property
        pub fn find(
            self: *const Self,
            context: anytype,
            comptime predicate: fn (@TypeOf(context), []const u8, T) bool,
        ) ?struct { key: []const u8, value: T } {
            var it = self.properties.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.descriptor.enumerable) {
                    if (predicate(context, entry.key_ptr.*, entry.value_ptr.value)) {
                        return .{
                            .key = entry.key_ptr.*,
                            .value = entry.value_ptr.value,
                        };
                    }
                }
            }
            return null;
        }

        // ===== Validation =====

        /// Validate object state (labeled block example 8)
        pub fn validate(self: *const Self) !void {
            validator: {
                // Validate state consistency
                if (self.is_frozen and !self.is_sealed) {
                    return errors_mod.ZObjectError.InvalidState;
                }

                if (self.is_sealed and self.is_extensible) {
                    return errors_mod.ZObjectError.InvalidState;
                }

                // Validate properties
                var it = self.properties.iterator();
                while (it.next()) |entry| {
                    try entry.value_ptr.descriptor.validate();
                }

                break :validator;
            }
        }
    };
}

// Re-export commonly used types for external use
pub const PropertyDescriptor = @import("property.zig").PropertyDescriptor;
pub const Property = @import("property.zig").Property;
pub const ZObjectError = @import("errors.zig").ZObjectError;

test "basic ZObject usage" {
    const testing = std.testing;

    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("age", 25);
    try testing.expectEqual(@as(?i32, 25), obj.get("age"));
}
