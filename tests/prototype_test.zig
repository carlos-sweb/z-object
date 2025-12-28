const std = @import("std");
const testing = std.testing;
const ZObject = @import("zobject").ZObject;

test "setPrototype sets the prototype" {
    var proto = ZObject(i32).init(testing.allocator);
    defer proto.deinit();

    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.setPrototype(&proto);

    try testing.expectEqual(&proto, obj.getPrototype().?);
}

test "setPrototype with null clears prototype" {
    var proto = ZObject(i32).init(testing.allocator);
    defer proto.deinit();

    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.setPrototype(&proto);
    try testing.expect(obj.getPrototype() != null);

    try obj.setPrototype(null);
    try testing.expect(obj.getPrototype() == null);
}

test "getPrototype returns null by default" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try testing.expect(obj.getPrototype() == null);
}

test "lookupInChain finds property in prototype" {
    var proto = ZObject(i32).init(testing.allocator);
    defer proto.deinit();
    try proto.set("inherited", 100);

    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();
    try obj.setPrototype(&proto);

    const value = obj.lookupInChain("inherited");
    try testing.expectEqual(@as(?i32, 100), value);
}

test "lookupInChain prefers own property over prototype" {
    var proto = ZObject(i32).init(testing.allocator);
    defer proto.deinit();
    try proto.set("shared", 100);

    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();
    try obj.setPrototype(&proto);
    try obj.set("shared", 200);

    // Own property takes precedence
    const value = obj.get("shared");
    try testing.expectEqual(@as(?i32, 200), value);
}

test "lookupInChain returns null for non-existent property" {
    var proto = ZObject(i32).init(testing.allocator);
    defer proto.deinit();

    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();
    try obj.setPrototype(&proto);

    const value = obj.lookupInChain("notexists");
    try testing.expectEqual(@as(?i32, null), value);
}

test "lookupInChain traverses multiple levels" {
    var proto1 = ZObject(i32).init(testing.allocator);
    defer proto1.deinit();
    try proto1.set("level1", 1);

    var proto2 = ZObject(i32).init(testing.allocator);
    defer proto2.deinit();
    try proto2.setPrototype(&proto1);
    try proto2.set("level2", 2);

    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();
    try obj.setPrototype(&proto2);
    try obj.set("level3", 3);

    // Can find properties at all levels
    try testing.expectEqual(@as(?i32, 3), obj.lookupInChain("level3"));
    try testing.expectEqual(@as(?i32, 2), obj.lookupInChain("level2"));
    try testing.expectEqual(@as(?i32, 1), obj.lookupInChain("level1"));
}

test "hasOwnProperty vs has with prototype" {
    var proto = ZObject(i32).init(testing.allocator);
    defer proto.deinit();
    try proto.set("inherited", 100);

    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();
    try obj.setPrototype(&proto);
    try obj.set("own", 200);

    // hasOwnProperty only checks own properties
    try testing.expect(obj.hasOwnProperty("own"));
    try testing.expect(!obj.hasOwnProperty("inherited"));

    // has checks prototype chain
    try testing.expect(obj.has("own"));
    try testing.expect(obj.has("inherited"));
}

test "isPrototypeOf checks prototype relationship" {
    var proto = ZObject(i32).init(testing.allocator);
    defer proto.deinit();

    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();
    try obj.setPrototype(&proto);

    try testing.expect(proto.isPrototypeOf(&obj));
}

test "isPrototypeOf returns false for non-prototype" {
    var obj1 = ZObject(i32).init(testing.allocator);
    defer obj1.deinit();

    var obj2 = ZObject(i32).init(testing.allocator);
    defer obj2.deinit();

    try testing.expect(!obj1.isPrototypeOf(&obj2));
}

test "isPrototypeOf checks entire chain" {
    var proto1 = ZObject(i32).init(testing.allocator);
    defer proto1.deinit();

    var proto2 = ZObject(i32).init(testing.allocator);
    defer proto2.deinit();
    try proto2.setPrototype(&proto1);

    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();
    try obj.setPrototype(&proto2);

    // proto1 is in the chain
    try testing.expect(proto1.isPrototypeOf(&obj));
    try testing.expect(proto2.isPrototypeOf(&obj));
}

test "Object.create with prototype" {
    var proto = ZObject(i32).init(testing.allocator);
    defer proto.deinit();
    try proto.set("inherited", 999);

    var obj = try ZObject(i32).create(testing.allocator, &proto);
    defer obj.deinit();

    try testing.expectEqual(&proto, obj.getPrototype().?);
    try testing.expectEqual(@as(?i32, 999), obj.lookupInChain("inherited"));
}

test "Object.create with null prototype" {
    var obj = try ZObject(i32).create(testing.allocator, null);
    defer obj.deinit();

    try testing.expect(obj.getPrototype() == null);
}

test "setPrototype detects direct cycle" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    // Cannot set self as prototype
    const result = obj.setPrototype(&obj);
    try testing.expectError(error.PrototypeCycle, result);
}

test "setPrototype detects indirect cycle" {
    var obj1 = ZObject(i32).init(testing.allocator);
    defer obj1.deinit();

    var obj2 = ZObject(i32).init(testing.allocator);
    defer obj2.deinit();

    // obj1 -> obj2
    try obj1.setPrototype(&obj2);

    // obj2 -> obj1 would create a cycle
    const result = obj2.setPrototype(&obj1);
    try testing.expectError(error.PrototypeCycle, result);
}

test "setPrototype detects multi-level cycle" {
    var obj1 = ZObject(i32).init(testing.allocator);
    defer obj1.deinit();

    var obj2 = ZObject(i32).init(testing.allocator);
    defer obj2.deinit();

    var obj3 = ZObject(i32).init(testing.allocator);
    defer obj3.deinit();

    // obj1 -> obj2 -> obj3
    try obj1.setPrototype(&obj2);
    try obj2.setPrototype(&obj3);

    // obj3 -> obj1 would create a cycle
    const result = obj3.setPrototype(&obj1);
    try testing.expectError(error.PrototypeCycle, result);
}

test "setPrototype on non-extensible object fails if changing prototype" {
    var proto1 = ZObject(i32).init(testing.allocator);
    defer proto1.deinit();

    var proto2 = ZObject(i32).init(testing.allocator);
    defer proto2.deinit();

    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();
    try obj.setPrototype(&proto1);

    obj.preventExtensions();

    // Cannot change prototype when not extensible
    const result = obj.setPrototype(&proto2);
    try testing.expectError(error.ObjectNotExtensible, result);
}

test "setPrototype on non-extensible object succeeds if same prototype" {
    var proto = ZObject(i32).init(testing.allocator);
    defer proto.deinit();

    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();
    try obj.setPrototype(&proto);

    obj.preventExtensions();

    // Can set same prototype
    try obj.setPrototype(&proto);
    try testing.expectEqual(&proto, obj.getPrototype().?);
}

test "hasInChain checks prototype chain" {
    var proto = ZObject(i32).init(testing.allocator);
    defer proto.deinit();
    try proto.set("inherited", 100);

    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();
    try obj.setPrototype(&proto);

    try testing.expect(obj.hasInChain("inherited"));
    try testing.expect(!obj.hasInChain("notexists"));
}

test "getAllPropertiesInChain returns all properties" {
    var proto = ZObject(i32).init(testing.allocator);
    defer proto.deinit();
    try proto.set("a", 1);
    try proto.set("b", 2);

    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();
    try obj.setPrototype(&proto);
    try obj.set("c", 3);
    try obj.set("d", 4);

    const all_props = try obj.getAllPropertiesInChain(testing.allocator);
    defer testing.allocator.free(all_props);

    try testing.expectEqual(@as(usize, 4), all_props.len);
}

test "getAllPropertiesInChain deduplicates properties" {
    var proto = ZObject(i32).init(testing.allocator);
    defer proto.deinit();
    try proto.set("shared", 1);
    try proto.set("proto_only", 2);

    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();
    try obj.setPrototype(&proto);
    try obj.set("shared", 10); // Shadows prototype property
    try obj.set("own_only", 3);

    const all_props = try obj.getAllPropertiesInChain(testing.allocator);
    defer testing.allocator.free(all_props);

    // Should have 3 unique properties: shared, proto_only, own_only
    try testing.expectEqual(@as(usize, 3), all_props.len);
}

test "prototype chain with non-enumerable properties" {
    const PropertyDescriptor = @import("zobject").PropertyDescriptor;

    var proto = ZObject(i32).init(testing.allocator);
    defer proto.deinit();

    // Add non-enumerable property to prototype
    const hidden_desc = PropertyDescriptor{
        .writable = true,
        .enumerable = false,
        .configurable = true,
    };
    try proto.defineProperty("hidden", 99, hidden_desc);

    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();
    try obj.setPrototype(&proto);

    // lookupInChain only finds enumerable properties
    const value = obj.lookupInChain("hidden");
    try testing.expectEqual(@as(?i32, null), value);
}

test "Object.getPrototypeOf" {
    var proto = ZObject(i32).init(testing.allocator);
    defer proto.deinit();

    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();
    try obj.setPrototype(&proto);

    // getPrototype is the same as Object.getPrototypeOf
    try testing.expectEqual(&proto, obj.getPrototype().?);
}

test "complex prototype chain navigation" {
    // Create a 4-level prototype chain
    var level0 = ZObject(i32).init(testing.allocator);
    defer level0.deinit();
    try level0.set("l0", 0);

    var level1 = ZObject(i32).init(testing.allocator);
    defer level1.deinit();
    try level1.setPrototype(&level0);
    try level1.set("l1", 1);

    var level2 = ZObject(i32).init(testing.allocator);
    defer level2.deinit();
    try level2.setPrototype(&level1);
    try level2.set("l2", 2);

    var level3 = ZObject(i32).init(testing.allocator);
    defer level3.deinit();
    try level3.setPrototype(&level2);
    try level3.set("l3", 3);

    // Verify chain navigation
    try testing.expectEqual(@as(?i32, 3), level3.lookupInChain("l3"));
    try testing.expectEqual(@as(?i32, 2), level3.lookupInChain("l2"));
    try testing.expectEqual(@as(?i32, 1), level3.lookupInChain("l1"));
    try testing.expectEqual(@as(?i32, 0), level3.lookupInChain("l0"));

    // Verify isPrototypeOf
    try testing.expect(level0.isPrototypeOf(&level3));
    try testing.expect(level1.isPrototypeOf(&level3));
    try testing.expect(level2.isPrototypeOf(&level3));
    try testing.expect(!level3.isPrototypeOf(&level0));
}
