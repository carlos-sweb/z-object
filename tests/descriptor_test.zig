const std = @import("std");
const testing = std.testing;
const ZObject = @import("zobject").ZObject;
const PropertyDescriptor = @import("zobject").PropertyDescriptor;

test "defineProperty with custom descriptor" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    const desc = PropertyDescriptor{
        .writable = false,
        .enumerable = true,
        .configurable = false,
    };

    try obj.defineProperty("constant", 42, desc);

    try testing.expectEqual(@as(?i32, 42), obj.get("constant"));
}

test "defineProperty with non-writable property" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    const desc = PropertyDescriptor{
        .writable = false,
        .enumerable = true,
        .configurable = true,
    };

    try obj.defineProperty("readonly", 100, desc);

    // Cannot modify non-writable property
    const result = obj.set("readonly", 200);
    try testing.expectError(error.PropertyNotWritable, result);

    // Value should remain unchanged
    try testing.expectEqual(@as(?i32, 100), obj.get("readonly"));
}

test "defineProperty with non-enumerable property" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    const desc = PropertyDescriptor{
        .writable = true,
        .enumerable = false,
        .configurable = true,
    };

    try obj.defineProperty("hidden", 99, desc);

    // Property exists
    try testing.expect(obj.hasOwnProperty("hidden"));
    try testing.expectEqual(@as(?i32, 99), obj.get("hidden"));

    // But is not enumerable
    try testing.expect(!obj.propertyIsEnumerable("hidden"));

    // Should not appear in keys()
    const key_list = try obj.keys(testing.allocator);
    defer testing.allocator.free(key_list);
    try testing.expectEqual(@as(usize, 0), key_list.len);
}

test "defineProperty with non-configurable property" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    const desc = PropertyDescriptor{
        .writable = true,
        .enumerable = true,
        .configurable = false,
    };

    try obj.defineProperty("permanent", 123, desc);

    // Cannot delete non-configurable property
    const result = obj.delete("permanent");
    try testing.expectError(error.PropertyNotConfigurable, result);

    // Property still exists
    try testing.expect(obj.hasOwnProperty("permanent"));
}

test "defineProperty on non-extensible object fails for new property" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    obj.preventExtensions();

    const desc = PropertyDescriptor{};
    const result = obj.defineProperty("new", 42, desc);
    try testing.expectError(error.ObjectNotExtensible, result);
}

test "defineProperty can update existing configurable property" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    // Create with default descriptor (configurable=true)
    try obj.set("updatable", 10);

    // Update with new descriptor
    const new_desc = PropertyDescriptor{
        .writable = false,
        .enumerable = false,
        .configurable = false,
    };

    try obj.defineProperty("updatable", 20, new_desc);

    const retrieved_desc = obj.getOwnPropertyDescriptor("updatable");
    try testing.expect(retrieved_desc != null);
    try testing.expect(!retrieved_desc.?.writable);
    try testing.expect(!retrieved_desc.?.enumerable);
    try testing.expect(!retrieved_desc.?.configurable);
}

test "defineProperty fails on non-configurable property" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    const desc1 = PropertyDescriptor{
        .writable = true,
        .enumerable = true,
        .configurable = false,
    };

    try obj.defineProperty("locked", 10, desc1);

    const desc2 = PropertyDescriptor{
        .writable = false,
        .enumerable = false,
        .configurable = true,
    };

    const result = obj.defineProperty("locked", 20, desc2);
    try testing.expectError(error.PropertyNotConfigurable, result);
}

test "defineProperties defines multiple properties" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    const desc1 = PropertyDescriptor{
        .writable = false,
        .enumerable = true,
        .configurable = false,
    };

    const desc2 = PropertyDescriptor{
        .writable = true,
        .enumerable = false,
        .configurable = true,
    };

    const props = [_]ZObject(i32).PropertyDefinition{
        .{ .key = "a", .value = 1, .descriptor = desc1 },
        .{ .key = "b", .value = 2, .descriptor = desc2 },
    };

    try obj.defineProperties(&props);

    try testing.expectEqual(@as(?i32, 1), obj.get("a"));
    try testing.expectEqual(@as(?i32, 2), obj.get("b"));

    // Check descriptors
    const desc_a = obj.getOwnPropertyDescriptor("a");
    try testing.expect(!desc_a.?.writable);
    try testing.expect(desc_a.?.enumerable);

    const desc_b = obj.getOwnPropertyDescriptor("b");
    try testing.expect(desc_b.?.writable);
    try testing.expect(!desc_b.?.enumerable);
}

test "getOwnPropertyDescriptor returns descriptor" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    const desc = PropertyDescriptor{
        .writable = false,
        .enumerable = true,
        .configurable = false,
    };

    try obj.defineProperty("test", 42, desc);

    const retrieved = obj.getOwnPropertyDescriptor("test");
    try testing.expect(retrieved != null);
    try testing.expect(!retrieved.?.writable);
    try testing.expect(retrieved.?.enumerable);
    try testing.expect(!retrieved.?.configurable);
}

test "getOwnPropertyDescriptor returns null for non-existent property" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    const retrieved = obj.getOwnPropertyDescriptor("notexists");
    try testing.expect(retrieved == null);
}

test "getOwnPropertyDescriptors returns all descriptors" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("a", 1);
    try obj.set("b", 2);

    var descriptors = try obj.getOwnPropertyDescriptors(testing.allocator);
    defer descriptors.deinit();

    try testing.expectEqual(@as(u32, 2), descriptors.count());
    try testing.expect(descriptors.contains("a"));
    try testing.expect(descriptors.contains("b"));
}

test "updateDescriptor updates property descriptor" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("test", 42);

    // Update descriptor
    const new_desc = PropertyDescriptor{
        .writable = false,
        .enumerable = false,
        .configurable = true,
    };

    try obj.updateDescriptor("test", new_desc);

    const retrieved = obj.getOwnPropertyDescriptor("test");
    try testing.expect(!retrieved.?.writable);
    try testing.expect(!retrieved.?.enumerable);
    try testing.expect(retrieved.?.configurable);
}

test "updateDescriptor fails for non-existent property" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    const desc = PropertyDescriptor{};
    const result = obj.updateDescriptor("notexists", desc);
    try testing.expectError(error.PropertyNotFound, result);
}

test "updateDescriptor fails for non-configurable property" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    const desc1 = PropertyDescriptor{
        .writable = true,
        .enumerable = true,
        .configurable = false,
    };

    try obj.defineProperty("locked", 42, desc1);

    const desc2 = PropertyDescriptor{
        .writable = false,
        .enumerable = true,
        .configurable = false,
    };

    const result = obj.updateDescriptor("locked", desc2);
    try testing.expectError(error.PropertyNotConfigurable, result);
}

test "PropertyDescriptor.isDataDescriptor" {
    const desc1 = PropertyDescriptor{
        .value = null,
        .writable = true,
    };
    try testing.expect(desc1.isDataDescriptor());

    const desc2 = PropertyDescriptor{
        .writable = false,
        .get = null,
        .set = null,
    };
    try testing.expect(!desc2.isAccessorDescriptor());
}

test "PropertyDescriptor default values" {
    const desc = PropertyDescriptor{};
    try testing.expect(desc.value == null);
    try testing.expect(desc.writable);
    try testing.expect(desc.enumerable);
    try testing.expect(desc.configurable);
    try testing.expect(desc.get == null);
    try testing.expect(desc.set == null);
}

test "Property with custom descriptor" {
    const Property = @import("zobject").Property;

    const desc = PropertyDescriptor{
        .writable = false,
        .enumerable = true,
        .configurable = false,
    };

    const prop = Property(i32).initWithDescriptor(42, desc);

    try testing.expectEqual(@as(i32, 42), prop.value);
    try testing.expect(!prop.descriptor.writable);
    try testing.expect(prop.descriptor.enumerable);
    try testing.expect(!prop.descriptor.configurable);
}

test "Property helper methods" {
    const Property = @import("zobject").Property;

    const desc = PropertyDescriptor{
        .writable = false,
        .enumerable = true,
        .configurable = false,
    };

    const prop = Property(i32).initWithDescriptor(42, desc);

    try testing.expect(!prop.isWritable());
    try testing.expect(prop.isEnumerable());
    try testing.expect(!prop.isConfigurable());
}

test "Property clone" {
    const Property = @import("zobject").Property;

    const prop1 = Property(i32).init(42);
    const prop2 = prop1.clone();

    try testing.expectEqual(prop1.value, prop2.value);
    try testing.expectEqual(prop1.descriptor.writable, prop2.descriptor.writable);
}

test "default property is writable, enumerable, configurable" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("test", 42);

    const desc = obj.getOwnPropertyDescriptor("test");
    try testing.expect(desc.?.writable);
    try testing.expect(desc.?.enumerable);
    try testing.expect(desc.?.configurable);
}

test "keys only returns enumerable properties" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    // Add enumerable property
    try obj.set("visible", 1);

    // Add non-enumerable property
    const hidden_desc = PropertyDescriptor{
        .writable = true,
        .enumerable = false,
        .configurable = true,
    };
    try obj.defineProperty("hidden", 2, hidden_desc);

    const key_list = try obj.keys(testing.allocator);
    defer testing.allocator.free(key_list);

    // Should only contain "visible"
    try testing.expectEqual(@as(usize, 1), key_list.len);
    try testing.expectEqualStrings("visible", key_list[0]);
}

test "values only returns enumerable property values" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    // Add enumerable property
    try obj.set("visible", 100);

    // Add non-enumerable property
    const hidden_desc = PropertyDescriptor{
        .writable = true,
        .enumerable = false,
        .configurable = true,
    };
    try obj.defineProperty("hidden", 200, hidden_desc);

    const value_list = try obj.values(testing.allocator);
    defer testing.allocator.free(value_list);

    // Should only contain 100
    try testing.expectEqual(@as(usize, 1), value_list.len);
    try testing.expectEqual(@as(i32, 100), value_list[0]);
}
