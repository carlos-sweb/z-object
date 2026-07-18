const std = @import("std");
const Allocator = std.mem.Allocator;
const property_mod = @import("property.zig");
const errors_mod = @import("errors.zig");

/// Generic ECMAScript-compatible Object implementation
pub fn ZObject(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Map of properties (string -> Property). Array-backed (not a plain
        /// hashmap) so that iteration order is insertion order, matching
        /// ECMA-262 OrdinaryOwnPropertyKeys — see enumerationOrder() for the
        /// additional array-index-keys-first partitioning applied on top.
        properties: std.array_hash_map.String(property_mod.Property(T)),

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
                .properties = .empty,
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
            self.properties.deinit(self.allocator);
        }

        /// ECMA-262 CanonicalNumericIndexString / array-index test: no sign,
        /// no leading zeros (except "0" itself), value <= 2^32-2 (2^32-1 is
        /// reserved by spec as an "invalid index" sentinel).
        fn arrayIndexValue(key: []const u8) ?u32 {
            if (key.len == 0) return null;
            if (key.len > 1 and key[0] == '0') return null;
            var value: u32 = 0;
            for (key) |c| {
                if (c < '0' or c > '9') return null;
                const digit: u32 = c - '0';
                if (value > (std.math.maxInt(u32) - digit) / 10) return null;
                value = value * 10 + digit;
            }
            if (value == std.math.maxInt(u32)) return null;
            return value;
        }

        /// Indices into self.properties.keys()/.values() in the enumeration
        /// order required by OrdinaryOwnPropertyKeys: array-index keys
        /// ascending numerically first, then the rest in their relative
        /// (insertion) order. Caller owns the returned slice.
        fn enumerationOrder(self: *const Self, allocator: Allocator) ![]usize {
            const ks = self.properties.keys();
            const idx = try allocator.alloc(usize, ks.len);
            for (idx, 0..) |*v, i| v.* = i;

            const Ctx = struct {
                keys: [][]const u8,
                pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
                    const ai = arrayIndexValue(ctx.keys[a]);
                    const bi = arrayIndexValue(ctx.keys[b]);
                    if (ai != null and bi != null) return ai.? < bi.?;
                    if (ai != null) return true;
                    if (bi != null) return false;
                    return false; // neither is an index: preserve order (stable sort)
                }
            };
            std.mem.sort(usize, idx, Ctx{ .keys = ks }, Ctx.lessThan);
            return idx;
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
                // Update existing property value. A plain set over an
                // accessor property replaces it wholesale with a data
                // property (raw storage semantics -- [[Set]]'s
                // call-the-setter behavior is the interpreter's dispatch,
                // which runs *before* ever reaching this).
                entry.value_ptr.value = value;
                entry.value_ptr.getter = null;
                entry.value_ptr.setter = null;
            } else {
                // Create new property with duplicated key
                const key_copy = try self.allocator.dupe(u8, key);
                errdefer self.allocator.free(key_copy);

                try self.properties.put(self.allocator, key_copy, property_mod.Property(T).init(value));
            }
        }

        /// Defines (or extends) a JS accessor property. Called once per
        /// `get x()` / `set x(v)` clause: when the key already holds an
        /// accessor, non-null slots merge into it -- `{ get x() {},
        /// set x(v) {} }` yields ONE property with both slots, matching
        /// real object-literal semantics. Defining over a *data* property
        /// replaces it. `empty_value` is what data-only consumers (keys/
        /// values/entries/JSON) see as the property's value; this type is
        /// generic so the caller supplies it (e.g. JSValue.UNDEFINED).
        pub fn defineAccessor(self: *Self, key: []const u8, getter: ?T, setter: ?T, empty_value: T) !void {
            if (self.is_frozen) return errors_mod.ZObjectError.ObjectIsFrozen;
            if (self.properties.getEntry(key)) |entry| {
                if (!entry.value_ptr.isAccessor()) entry.value_ptr.value = empty_value;
                if (getter) |g| entry.value_ptr.getter = g;
                if (setter) |s| entry.value_ptr.setter = s;
                return;
            }
            if (!self.is_extensible) return errors_mod.ZObjectError.ObjectNotExtensible;
            const key_copy = try self.allocator.dupe(u8, key);
            errdefer self.allocator.free(key_copy);
            var prop = property_mod.Property(T).init(empty_value);
            prop.getter = getter;
            prop.setter = setter;
            try self.properties.put(self.allocator, key_copy, prop);
        }

        /// Own-property record, exposing accessor slots -- for callers
        /// (the interpreter) that need to distinguish data from accessor
        /// properties and walk the prototype chain themselves.
        pub fn getOwnRecord(self: *const Self, key: []const u8) ?*const property_mod.Property(T) {
            if (self.properties.getPtr(key)) |prop| return prop;
            return null;
        }

        /// Object [[Get]] - own properties first, then walks the prototype
        /// chain. Matches real ECMAScript property access (obj.prop):
        /// enumerability never gates this, only iteration methods
        /// (keys/values/entries/forEach) do.
        pub fn get(self: *const Self, key: []const u8) ?T {
            return self.lookupInChain(key);
        }

        /// Own-property-only lookup, no prototype chain walk. Use this when
        /// you explicitly need "does *this* object (not its prototype) have
        /// the value", e.g. implementing hasOwnProperty-adjacent logic.
        pub fn getOwn(self: *const Self, key: []const u8) ?T {
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

            // Remove and free key (ordered: preserves the relative order of
            // surviving properties, per OrdinaryOwnPropertyKeys).
            if (self.properties.fetchOrderedRemove(key)) |removed| {
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

        /// Object.prototype.toLocaleString() - no real locale database
        /// exists here (same as z-array/z-number), so this is an alias of
        /// toString().
        pub fn toLocaleString(self: *const Self, allocator: Allocator) ![]u8 {
            return self.toString(allocator);
        }

        /// Get primitive value
        pub fn valueOf(self: *const Self) *const Self {
            return self;
        }

        /// Object.hasOwn() (ES2022) - alias of hasOwnProperty.
        pub fn hasOwn(self: *const Self, key: []const u8) bool {
            return self.hasOwnProperty(key);
        }

        /// Object.is() - SameValue algorithm. Differs from SameValueZero
        /// only in that +0 is -0 is false (SameValueZero treats them equal).
        /// Only observable for float T; for every other type this matches
        /// plain ==/eql.
        pub fn is(comptime FT: type, a: FT, b: FT) bool {
            if (@typeInfo(FT) != .float) return a == b;
            if (std.math.isNan(a) and std.math.isNan(b)) return true;
            if (a == 0 and b == 0) return std.math.signbit(a) == std.math.signbit(b);
            return a == b;
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
            const order = try self.enumerationOrder(allocator);
            defer allocator.free(order);

            const ks = self.properties.keys();
            const vs = self.properties.values();
            var key_list: std.ArrayList([]const u8) = .empty;
            errdefer key_list.deinit(allocator);

            for (order) |i| {
                if (vs[i].descriptor.enumerable) {
                    try key_list.append(allocator, ks[i]);
                }
            }

            return try key_list.toOwnedSlice(allocator);
        }

        /// Object.values() - Get array of enumerable property values, in
        /// ECMA-262 OrdinaryOwnPropertyKeys order.
        pub fn values(self: *const Self, allocator: Allocator) ![]T {
            const order = try self.enumerationOrder(allocator);
            defer allocator.free(order);

            const vs = self.properties.values();
            var value_list: std.ArrayList(T) = .empty;
            errdefer value_list.deinit(allocator);

            for (order) |i| {
                if (vs[i].descriptor.enumerable) {
                    try value_list.append(allocator, vs[i].value);
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

        /// Object.entries() - Get array of [key, value] pairs, in ECMA-262
        /// OrdinaryOwnPropertyKeys order.
        pub fn entries(self: *const Self, allocator: Allocator) ![]Entry {
            const order = try self.enumerationOrder(allocator);
            defer allocator.free(order);

            const ks = self.properties.keys();
            const vs = self.properties.values();
            var entry_list: std.ArrayList(Entry) = .empty;
            errdefer entry_list.deinit(allocator);

            for (order) |i| {
                if (vs[i].descriptor.enumerable) {
                    try entry_list.append(allocator, .{
                        .key = ks[i],
                        .value = vs[i].value,
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

                    const order = try source.enumerationOrder(target.allocator);
                    defer target.allocator.free(order);

                    const ks = source.properties.keys();
                    const vs = source.properties.values();
                    for (order) |i| {
                        if (!vs[i].descriptor.enumerable) continue;

                        // Set property on target
                        try target.set(ks[i], vs[i].value);
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

        /// Object.create(proto, propertiesObject) - like create(), but also
        /// defines properties in the same call, without changing create()'s
        /// existing signature.
        pub fn createWithProperties(allocator: Allocator, proto: ?*Self, props: []const PropertyDefinition) !Self {
            var obj = try Self.create(allocator, proto);
            errdefer obj.deinit();
            try obj.defineProperties(props);
            return obj;
        }

        /// Object.freeze() - Freeze object (labeled block example 5)
        pub fn freeze(self: *Self) void {
            freezer: {
                self.is_frozen = true;
                self.is_sealed = true;
                self.is_extensible = false;

                for (self.properties.values()) |*prop| {
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

            for (self.properties.values()) |*prop| {
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
            for (self.properties.values()) |prop| {
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
            for (self.properties.values()) |prop| {
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

        /// Object.getOwnPropertyNames() - Get all property names (including
        /// non-enumerable), in ECMA-262 OrdinaryOwnPropertyKeys order.
        pub fn getOwnPropertyNames(self: *const Self, allocator: Allocator) ![][]const u8 {
            const order = try self.enumerationOrder(allocator);
            defer allocator.free(order);

            const ks = self.properties.keys();
            const name_list = try allocator.alloc([]const u8, order.len);
            errdefer allocator.free(name_list);
            for (order, 0..) |i, out_i| name_list[out_i] = ks[i];

            return name_list;
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

                try self.properties.put(self.allocator, key_copy, property_mod.Property(T).initWithDescriptor(value, descriptor));
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

        /// Object.getOwnPropertyDescriptors() - result preserves ECMA-262
        /// OrdinaryOwnPropertyKeys order, like the object itself.
        pub fn getOwnPropertyDescriptors(
            self: *const Self,
            allocator: Allocator,
        ) !std.array_hash_map.String(property_mod.PropertyDescriptor) {
            const order = try self.enumerationOrder(allocator);
            defer allocator.free(order);

            const ks = self.properties.keys();
            const vs = self.properties.values();
            var desc_map: std.array_hash_map.String(property_mod.PropertyDescriptor) = .empty;
            errdefer desc_map.deinit(allocator);

            for (order) |i| {
                try desc_map.put(allocator, ks[i], vs[i].descriptor);
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

        /// Lookup property in own properties or the prototype chain
        /// (labeled block example 7). Per ECMA-262 [[Get]], enumerability
        /// never gates this — only iteration (keys/values/entries/forEach)
        /// filters by it.
        pub fn lookupInChain(self: *const Self, key: []const u8) ?T {
            var current: ?*const Self = self;

            chain_walker: {
                while (current) |obj| {
                    if (obj.properties.get(key)) |prop| {
                        return prop.value;
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
            for (self.properties.keys()) |key| {
                try prop_set.put(key, {});
            }

            // Add prototype chain properties
            var current = self.prototype;
            while (current) |proto| {
                for (proto.properties.keys()) |key| {
                    try prop_set.put(key, {});
                }
                current = proto.prototype;
            }

            // Convert to array
            var prop_list: std.ArrayList([]const u8) = .empty;
            errdefer prop_list.deinit(allocator);

            var set_it = prop_set.keyIterator();
            while (set_it.next()) |key| {
                try prop_list.append(allocator, key.*);
            }

            return try prop_list.toOwnedSlice(allocator);
        }

        // ===== Iteration Methods =====

        /// forEach over enumerable properties, in ECMA-262
        /// OrdinaryOwnPropertyKeys order.
        pub fn forEach(
            self: *const Self,
            context: anytype,
            comptime callback: fn (@TypeOf(context), []const u8, T) void,
        ) void {
            // forEach has no error return; an OOM on this tiny scratch
            // allocation is treated as "nothing to iterate" rather than propagated.
            const order = self.enumerationOrder(self.allocator) catch return;
            defer self.allocator.free(order);

            const ks = self.properties.keys();
            const vs = self.properties.values();
            for (order) |i| {
                if (vs[i].descriptor.enumerable) {
                    callback(context, ks[i], vs[i].value);
                }
            }
        }

        /// map over properties (returns new object), in ECMA-262
        /// OrdinaryOwnPropertyKeys order.
        pub fn map(
            self: *const Self,
            comptime U: type,
            context: anytype,
            comptime callback: fn (@TypeOf(context), []const u8, T) U,
        ) !ZObject(U) {
            var result = ZObject(U).init(self.allocator);
            errdefer result.deinit();

            const order = try self.enumerationOrder(self.allocator);
            defer self.allocator.free(order);

            const ks = self.properties.keys();
            const vs = self.properties.values();
            for (order) |i| {
                if (vs[i].descriptor.enumerable) {
                    const new_value = callback(context, ks[i], vs[i].value);
                    try result.set(ks[i], new_value);
                }
            }

            return result;
        }

        /// filter properties, in ECMA-262 OrdinaryOwnPropertyKeys order.
        pub fn filter(
            self: *const Self,
            context: anytype,
            comptime predicate: fn (@TypeOf(context), []const u8, T) bool,
        ) !Self {
            var result = Self.init(self.allocator);
            errdefer result.deinit();

            const order = try self.enumerationOrder(self.allocator);
            defer self.allocator.free(order);

            const ks = self.properties.keys();
            const vs = self.properties.values();
            for (order) |i| {
                if (vs[i].descriptor.enumerable) {
                    if (predicate(context, ks[i], vs[i].value)) {
                        try result.set(ks[i], vs[i].value);
                    }
                }
            }

            return result;
        }

        /// reduce over properties, in ECMA-262 OrdinaryOwnPropertyKeys order.
        pub fn reduce(
            self: *const Self,
            comptime U: type,
            initial: U,
            context: anytype,
            comptime callback: fn (@TypeOf(context), U, []const u8, T) U,
        ) U {
            var accumulator = initial;

            // reduce has no error return; OOM on the scratch allocation falls back
            // to the untouched initial accumulator rather than propagating.
            const order = self.enumerationOrder(self.allocator) catch return accumulator;
            defer self.allocator.free(order);

            const ks = self.properties.keys();
            const vs = self.properties.values();
            for (order) |i| {
                if (vs[i].descriptor.enumerable) {
                    accumulator = callback(context, accumulator, ks[i], vs[i].value);
                }
            }

            return accumulator;
        }

        /// some - at least one property satisfies predicate, checked in
        /// ECMA-262 OrdinaryOwnPropertyKeys order.
        pub fn some(
            self: *const Self,
            context: anytype,
            comptime predicate: fn (@TypeOf(context), []const u8, T) bool,
        ) bool {
            // some has no error return; OOM on the scratch allocation is treated
            // as "no match" rather than propagated.
            const order = self.enumerationOrder(self.allocator) catch return false;
            defer self.allocator.free(order);

            const ks = self.properties.keys();
            const vs = self.properties.values();
            for (order) |i| {
                if (vs[i].descriptor.enumerable) {
                    if (predicate(context, ks[i], vs[i].value)) {
                        return true;
                    }
                }
            }
            return false;
        }

        /// every - all properties satisfy predicate, checked in ECMA-262
        /// OrdinaryOwnPropertyKeys order.
        pub fn every(
            self: *const Self,
            context: anytype,
            comptime predicate: fn (@TypeOf(context), []const u8, T) bool,
        ) bool {
            // every has no error return; OOM on the scratch allocation is treated
            // as vacuously true rather than propagated (matches every()'s own
            // empty-collection convention).
            const order = self.enumerationOrder(self.allocator) catch return true;
            defer self.allocator.free(order);

            const ks = self.properties.keys();
            const vs = self.properties.values();
            for (order) |i| {
                if (vs[i].descriptor.enumerable) {
                    if (!predicate(context, ks[i], vs[i].value)) {
                        return false;
                    }
                }
            }
            return true;
        }

        /// find property, in ECMA-262 OrdinaryOwnPropertyKeys order.
        pub fn find(
            self: *const Self,
            context: anytype,
            comptime predicate: fn (@TypeOf(context), []const u8, T) bool,
        ) ?struct { key: []const u8, value: T } {
            // find has no error return; OOM on the scratch allocation is treated
            // as "not found" rather than propagated.
            const order = self.enumerationOrder(self.allocator) catch return null;
            defer self.allocator.free(order);

            const ks = self.properties.keys();
            const vs = self.properties.values();
            for (order) |i| {
                if (vs[i].descriptor.enumerable) {
                    if (predicate(context, ks[i], vs[i].value)) {
                        return .{
                            .key = ks[i],
                            .value = vs[i].value,
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
pub const ErrorContext = @import("errors.zig").ErrorContext;

test "basic ZObject usage" {
    const testing = std.testing;

    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("age", 25);
    try testing.expectEqual(@as(?i32, 25), obj.get("age"));
}
