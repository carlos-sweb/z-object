const std = @import("std");
const testing = std.testing;
const ZObject = @import("zobject").ZObject;

test "Object.keys() returns enumerable keys" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("name", 1);
    try obj.set("age", 2);
    try obj.set("city", 3);

    const key_list = try obj.keys(testing.allocator);
    defer testing.allocator.free(key_list);

    try testing.expectEqual(@as(usize, 3), key_list.len);
}

test "Object.values() returns enumerable values" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("a", 10);
    try obj.set("b", 20);
    try obj.set("c", 30);

    const value_list = try obj.values(testing.allocator);
    defer testing.allocator.free(value_list);

    try testing.expectEqual(@as(usize, 3), value_list.len);

    // Values should be present (order not guaranteed)
    var sum: i32 = 0;
    for (value_list) |val| {
        sum += val;
    }
    try testing.expectEqual(@as(i32, 60), sum);
}

test "Object.entries() returns key-value pairs" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("x", 100);
    try obj.set("y", 200);

    const entry_list = try obj.entries(testing.allocator);
    defer testing.allocator.free(entry_list);

    try testing.expectEqual(@as(usize, 2), entry_list.len);

    for (entry_list) |entry| {
        if (std.mem.eql(u8, entry.key, "x")) {
            try testing.expectEqual(@as(i32, 100), entry.value);
        } else if (std.mem.eql(u8, entry.key, "y")) {
            try testing.expectEqual(@as(i32, 200), entry.value);
        }
    }
}

test "Object.assign() copies properties from sources" {
    var target = ZObject(i32).init(testing.allocator);
    defer target.deinit();

    var source1 = ZObject(i32).init(testing.allocator);
    defer source1.deinit();
    try source1.set("a", 1);
    try source1.set("b", 2);

    var source2 = ZObject(i32).init(testing.allocator);
    defer source2.deinit();
    try source2.set("c", 3);
    try source2.set("d", 4);

    const sources = [_]*const ZObject(i32){ &source1, &source2 };
    try target.assign(&sources);

    try testing.expectEqual(@as(?i32, 1), target.get("a"));
    try testing.expectEqual(@as(?i32, 2), target.get("b"));
    try testing.expectEqual(@as(?i32, 3), target.get("c"));
    try testing.expectEqual(@as(?i32, 4), target.get("d"));
}

test "Object.assign() overwrites existing properties" {
    var target = ZObject(i32).init(testing.allocator);
    defer target.deinit();
    try target.set("x", 10);

    var source = ZObject(i32).init(testing.allocator);
    defer source.deinit();
    try source.set("x", 99);

    const sources = [_]*const ZObject(i32){&source};
    try target.assign(&sources);

    try testing.expectEqual(@as(?i32, 99), target.get("x"));
}

test "Object.assign() fails on frozen target" {
    var target = ZObject(i32).init(testing.allocator);
    defer target.deinit();
    target.freeze();

    var source = ZObject(i32).init(testing.allocator);
    defer source.deinit();
    try source.set("a", 1);

    const sources = [_]*const ZObject(i32){&source};
    const result = target.assign(&sources);
    try testing.expectError(error.ObjectIsFrozen, result);
}

test "Object.create() with null prototype" {
    var obj = try ZObject(i32).create(testing.allocator, null);
    defer obj.deinit();

    try obj.set("test", 42);
    try testing.expectEqual(@as(?*ZObject(i32), null), obj.getPrototype());
}

test "Object.create() with specific prototype" {
    var proto = ZObject(i32).init(testing.allocator);
    defer proto.deinit();
    try proto.set("inherited", 100);

    var obj = try ZObject(i32).create(testing.allocator, &proto);
    defer obj.deinit();

    try testing.expectEqual(&proto, obj.getPrototype().?);
}

test "Object.freeze() makes object immutable" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("value", 42);
    obj.freeze();

    try testing.expect(obj.isFrozen());
    try testing.expect(obj.isSealed());
    try testing.expect(!obj.isExtensible());

    // Cannot add new properties
    try testing.expectError(error.ObjectIsFrozen, obj.set("new", 100));

    // Cannot modify existing properties
    try testing.expectError(error.ObjectIsFrozen, obj.set("value", 99));

    // Cannot delete properties
    try testing.expectError(error.ObjectIsFrozen, obj.delete("value"));
}

test "Object.seal() prevents property addition/deletion" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("existing", 42);
    obj.seal();

    try testing.expect(obj.isSealed());
    try testing.expect(!obj.isExtensible());

    // Cannot add new properties
    try testing.expectError(error.ObjectNotExtensible, obj.set("new", 100));

    // Can modify existing properties (they're still writable)
    try obj.set("existing", 99);
    try testing.expectEqual(@as(?i32, 99), obj.get("existing"));

    // Cannot delete properties (they're non-configurable)
    try testing.expectError(error.PropertyNotConfigurable, obj.delete("existing"));
}

test "Object.preventExtensions() prevents new properties" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("existing", 42);
    obj.preventExtensions();

    try testing.expect(!obj.isExtensible());
    try testing.expect(!obj.isSealed()); // Not sealed, just not extensible
    try testing.expect(!obj.isFrozen()); // Not frozen

    // Cannot add new properties
    try testing.expectError(error.ObjectNotExtensible, obj.set("new", 100));

    // Can modify existing properties
    try obj.set("existing", 99);
    try testing.expectEqual(@as(?i32, 99), obj.get("existing"));

    // Can delete properties (they're still configurable)
    const deleted = try obj.delete("existing");
    try testing.expect(deleted);
}

test "Object.isFrozen() returns false for non-frozen object" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try testing.expect(!obj.isFrozen());

    obj.seal();
    try testing.expect(!obj.isFrozen()); // Sealed but not frozen

    obj.preventExtensions();
    try testing.expect(!obj.isFrozen()); // Not extensible but not frozen
}

test "Object.isSealed() returns false for non-sealed object" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try testing.expect(!obj.isSealed());

    obj.preventExtensions();
    try testing.expect(!obj.isSealed()); // Not extensible but not sealed (properties are still configurable)
}

test "Object.isExtensible() returns true by default" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try testing.expect(obj.isExtensible());
}

test "Object.isExtensible() returns false after preventExtensions" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    obj.preventExtensions();
    try testing.expect(!obj.isExtensible());
}

test "Object.getOwnPropertyNames() returns all property names" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("a", 1);
    try obj.set("b", 2);
    try obj.set("c", 3);

    const names = try obj.getOwnPropertyNames(testing.allocator);
    defer testing.allocator.free(names);

    try testing.expectEqual(@as(usize, 3), names.len);
}

test "Object.fromEntries() creates object from entries" {
    const Entry = ZObject(i32).Entry;

    const entries = [_]Entry{
        .{ .key = "x", .value = 10 },
        .{ .key = "y", .value = 20 },
        .{ .key = "z", .value = 30 },
    };

    var obj = try ZObject(i32).fromEntries(testing.allocator, &entries);
    defer obj.deinit();

    try testing.expectEqual(@as(?i32, 10), obj.get("x"));
    try testing.expectEqual(@as(?i32, 20), obj.get("y"));
    try testing.expectEqual(@as(?i32, 30), obj.get("z"));
}

test "Object.keys() on empty object returns empty array" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    const key_list = try obj.keys(testing.allocator);
    defer testing.allocator.free(key_list);

    try testing.expectEqual(@as(usize, 0), key_list.len);
}

test "Object.values() on empty object returns empty array" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    const value_list = try obj.values(testing.allocator);
    defer testing.allocator.free(value_list);

    try testing.expectEqual(@as(usize, 0), value_list.len);
}

test "Object.entries() on empty object returns empty array" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    const entry_list = try obj.entries(testing.allocator);
    defer testing.allocator.free(entry_list);

    try testing.expectEqual(@as(usize, 0), entry_list.len);
}

test "freeze makes properties non-writable" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("test", 1);

    // Get property before freeze
    const prop_before = obj.properties.get("test");
    try testing.expect(prop_before.?.descriptor.writable);

    obj.freeze();

    // Get property after freeze
    const prop_after = obj.properties.get("test");
    try testing.expect(!prop_after.?.descriptor.writable);
    try testing.expect(!prop_after.?.descriptor.configurable);
}

test "seal makes properties non-configurable" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("test", 1);

    // Get property before seal
    const prop_before = obj.properties.get("test");
    try testing.expect(prop_before.?.descriptor.configurable);

    obj.seal();

    // Get property after seal
    const prop_after = obj.properties.get("test");
    try testing.expect(!prop_after.?.descriptor.configurable);
    try testing.expect(prop_after.?.descriptor.writable); // Still writable
}
