const std = @import("std");
const testing = std.testing;
const ZObject = @import("zobject").ZObject;

test "create ZObject and set properties" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("age", 25);
    try obj.set("score", 100);

    try testing.expectEqual(@as(?i32, 25), obj.get("age"));
    try testing.expectEqual(@as(?i32, 100), obj.get("score"));
}

test "get property returns null for non-existent key" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try testing.expectEqual(@as(?i32, null), obj.get("nonexistent"));
}

test "delete property" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("temp", 42);
    try testing.expect(obj.hasOwnProperty("temp"));

    const deleted = try obj.delete("temp");
    try testing.expect(deleted);
    try testing.expect(!obj.hasOwnProperty("temp"));
}

test "delete non-existent property returns false" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    const deleted = try obj.delete("nonexistent");
    try testing.expect(!deleted);
}

test "hasOwnProperty" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("exists", 1);

    try testing.expect(obj.hasOwnProperty("exists"));
    try testing.expect(!obj.hasOwnProperty("notexists"));
}

test "has property (own property only, no prototype)" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("prop", 1);

    try testing.expect(obj.has("prop"));
    try testing.expect(!obj.has("notexists"));
}

test "size returns correct count" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try testing.expectEqual(@as(usize, 0), obj.size());

    try obj.set("a", 1);
    try testing.expectEqual(@as(usize, 1), obj.size());

    try obj.set("b", 2);
    try testing.expectEqual(@as(usize, 2), obj.size());

    _ = try obj.delete("a");
    try testing.expectEqual(@as(usize, 1), obj.size());
}

test "clear removes all properties" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("a", 1);
    try obj.set("b", 2);
    try obj.set("c", 3);

    try testing.expectEqual(@as(usize, 3), obj.size());

    try obj.clear();
    try testing.expectEqual(@as(usize, 0), obj.size());
}

test "set on frozen object fails" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("initial", 100);
    obj.freeze();

    const result = obj.set("new", 200);
    try testing.expectError(error.ObjectIsFrozen, result);
}

test "delete on frozen object fails" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("prop", 100);
    obj.freeze();

    const result = obj.delete("prop");
    try testing.expectError(error.ObjectIsFrozen, result);
}

test "set on sealed object with existing property succeeds" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("existing", 100);
    obj.seal();

    // Can modify existing writable property
    try obj.set("existing", 200);
    try testing.expectEqual(@as(?i32, 200), obj.get("existing"));
}

test "set new property on sealed object fails" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("existing", 100);
    obj.seal();

    // Cannot add new property
    const result = obj.set("new", 200);
    try testing.expectError(error.ObjectNotExtensible, result);
}

test "extensible flag prevents new properties" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("existing", 100);
    obj.preventExtensions();

    const result = obj.set("new", 200);
    try testing.expectError(error.ObjectNotExtensible, result);

    // Can still modify existing
    try obj.set("existing", 200);
    try testing.expectEqual(@as(?i32, 200), obj.get("existing"));
}

test "update existing property value" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("counter", 0);
    try obj.set("counter", 1);
    try obj.set("counter", 2);

    try testing.expectEqual(@as(?i32, 2), obj.get("counter"));
}

test "propertyIsEnumerable" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("visible", 100);

    try testing.expect(obj.propertyIsEnumerable("visible"));
    try testing.expect(!obj.propertyIsEnumerable("notexists"));
}

test "toString returns object representation" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    const str = try obj.toString(testing.allocator);
    defer testing.allocator.free(str);

    try testing.expectEqualStrings("[object Object]", str);
}

test "valueOf returns self" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    const value = obj.valueOf();
    try testing.expectEqual(&obj, value);
}

test "multiple properties with different types using comptime" {
    var obj_int = ZObject(i32).init(testing.allocator);
    defer obj_int.deinit();

    var obj_str = ZObject([]const u8).init(testing.allocator);
    defer obj_str.deinit();

    try obj_int.set("number", 42);
    try obj_str.set("text", "hello");

    try testing.expectEqual(@as(?i32, 42), obj_int.get("number"));
    try testing.expectEqualStrings("hello", obj_str.get("text").?);
}

test "clear on frozen object fails" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("a", 1);
    obj.freeze();

    const result = obj.clear();
    try testing.expectError(error.ObjectIsFrozen, result);
}

test "validate object with consistent state" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("test", 1);
    try obj.validate();
}

test "object starts as extensible" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try testing.expect(obj.isExtensible());
    try testing.expect(!obj.isSealed());
    try testing.expect(!obj.isFrozen());
}

test "ErrorContext.format produces the expected message (regression: used to fail to compile)" {
    const ErrorContext = @import("zobject").ErrorContext;

    const ctx = ErrorContext{ .message = "test error", .property = "age" };
    const s = try std.fmt.allocPrint(testing.allocator, "{f}", .{ctx});
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("ZObjectError: test error (property: age)", s);

    const ctx_no_prop = ErrorContext{ .message = "generic error" };
    const s2 = try std.fmt.allocPrint(testing.allocator, "{f}", .{ctx_no_prop});
    defer testing.allocator.free(s2);
    try testing.expectEqualStrings("ZObjectError: generic error", s2);
}
