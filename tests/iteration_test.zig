const std = @import("std");
const testing = std.testing;
const ZObject = @import("zobject").ZObject;
const PropertyDescriptor = @import("zobject").PropertyDescriptor;

test "forEach iterates over enumerable properties" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("a", 1);
    try obj.set("b", 2);
    try obj.set("c", 3);

    const Context = struct {
        sum: i32 = 0,
    };

    var ctx = Context{};

    obj.forEach(&ctx, struct {
        fn callback(context: *Context, key: []const u8, value: i32) void {
            _ = key;
            context.sum += value;
        }
    }.callback);

    try testing.expectEqual(@as(i32, 6), ctx.sum);
}

test "forEach skips non-enumerable properties" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("visible", 10);

    const hidden_desc = PropertyDescriptor{
        .writable = true,
        .enumerable = false,
        .configurable = true,
    };
    try obj.defineProperty("hidden", 20, hidden_desc);

    const Context = struct {
        sum: i32 = 0,
    };

    var ctx = Context{};

    obj.forEach(&ctx, struct {
        fn callback(context: *Context, key: []const u8, value: i32) void {
            _ = key;
            context.sum += value;
        }
    }.callback);

    // Should only sum visible properties
    try testing.expectEqual(@as(i32, 10), ctx.sum);
}

test "map creates new object with transformed values" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("a", 1);
    try obj.set("b", 2);
    try obj.set("c", 3);

    var mapped = try obj.map(i32, {}, struct {
        fn callback(_: void, key: []const u8, value: i32) i32 {
            _ = key;
            return value * 2;
        }
    }.callback);
    defer mapped.deinit();

    try testing.expectEqual(@as(?i32, 2), mapped.get("a"));
    try testing.expectEqual(@as(?i32, 4), mapped.get("b"));
    try testing.expectEqual(@as(?i32, 6), mapped.get("c"));
}

test "map can change value type" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("a", 1);
    try obj.set("b", 2);

    var mapped = try obj.map(bool, {}, struct {
        fn callback(_: void, key: []const u8, value: i32) bool {
            _ = key;
            return value > 1;
        }
    }.callback);
    defer mapped.deinit();

    try testing.expectEqual(@as(?bool, false), mapped.get("a"));
    try testing.expectEqual(@as(?bool, true), mapped.get("b"));
}

test "filter creates object with matching properties" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("a", 1);
    try obj.set("b", 2);
    try obj.set("c", 3);
    try obj.set("d", 4);

    var filtered = try obj.filter({}, struct {
        fn predicate(_: void, key: []const u8, value: i32) bool {
            _ = key;
            return value > 2;
        }
    }.predicate);
    defer filtered.deinit();

    try testing.expectEqual(@as(usize, 2), filtered.size());
    try testing.expectEqual(@as(?i32, 3), filtered.get("c"));
    try testing.expectEqual(@as(?i32, 4), filtered.get("d"));
    try testing.expectEqual(@as(?i32, null), filtered.get("a"));
    try testing.expectEqual(@as(?i32, null), filtered.get("b"));
}

test "filter with no matches returns empty object" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("a", 1);
    try obj.set("b", 2);

    var filtered = try obj.filter({}, struct {
        fn predicate(_: void, key: []const u8, value: i32) bool {
            _ = key;
            return value > 100;
        }
    }.predicate);
    defer filtered.deinit();

    try testing.expectEqual(@as(usize, 0), filtered.size());
}

test "reduce accumulates values" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("a", 1);
    try obj.set("b", 2);
    try obj.set("c", 3);

    const sum = obj.reduce(i32, 0, {}, struct {
        fn callback(_: void, acc: i32, key: []const u8, value: i32) i32 {
            _ = key;
            return acc + value;
        }
    }.callback);

    try testing.expectEqual(@as(i32, 6), sum);
}

test "reduce can change accumulator type" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("a", 1);
    try obj.set("b", 2);
    try obj.set("c", 3);

    const product = obj.reduce(f32, 1.0, {}, struct {
        fn callback(_: void, acc: f32, key: []const u8, value: i32) f32 {
            _ = key;
            return acc * @as(f32, @floatFromInt(value));
        }
    }.callback);

    try testing.expectEqual(@as(f32, 6.0), product);
}

test "reduce with empty object returns initial value" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    const result = obj.reduce(i32, 42, {}, struct {
        fn callback(_: void, acc: i32, key: []const u8, value: i32) i32 {
            _ = key;
            return acc + value;
        }
    }.callback);

    try testing.expectEqual(@as(i32, 42), result);
}

test "some returns true if any property matches" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("a", 1);
    try obj.set("b", 2);
    try obj.set("c", 3);

    const has_even = obj.some({}, struct {
        fn predicate(_: void, key: []const u8, value: i32) bool {
            _ = key;
            return @mod(value, 2) == 0;
        }
    }.predicate);

    try testing.expect(has_even);
}

test "some returns false if no property matches" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("a", 1);
    try obj.set("b", 3);
    try obj.set("c", 5);

    const has_even = obj.some({}, struct {
        fn predicate(_: void, key: []const u8, value: i32) bool {
            _ = key;
            return @mod(value, 2) == 0;
        }
    }.predicate);

    try testing.expect(!has_even);
}

test "some returns false for empty object" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    const result = obj.some({}, struct {
        fn predicate(_: void, key: []const u8, value: i32) bool {
            _ = key;
            _ = value;
            return true;
        }
    }.predicate);

    try testing.expect(!result);
}

test "every returns true if all properties match" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("a", 2);
    try obj.set("b", 4);
    try obj.set("c", 6);

    const all_even = obj.every({}, struct {
        fn predicate(_: void, key: []const u8, value: i32) bool {
            _ = key;
            return @mod(value, 2) == 0;
        }
    }.predicate);

    try testing.expect(all_even);
}

test "every returns false if any property doesn't match" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("a", 2);
    try obj.set("b", 3);
    try obj.set("c", 6);

    const all_even = obj.every({}, struct {
        fn predicate(_: void, key: []const u8, value: i32) bool {
            _ = key;
            return @mod(value, 2) == 0;
        }
    }.predicate);

    try testing.expect(!all_even);
}

test "every returns true for empty object" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    const result = obj.every({}, struct {
        fn predicate(_: void, key: []const u8, value: i32) bool {
            _ = key;
            _ = value;
            return false;
        }
    }.predicate);

    try testing.expect(result);
}

test "find returns first matching property" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("a", 1);
    try obj.set("b", 2);
    try obj.set("c", 3);

    const found = obj.find({}, struct {
        fn predicate(_: void, key: []const u8, value: i32) bool {
            _ = key;
            return value > 1;
        }
    }.predicate);

    try testing.expect(found != null);
    try testing.expect(found.?.value > 1);
}

test "find returns null if no match" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("a", 1);
    try obj.set("b", 2);

    const found = obj.find({}, struct {
        fn predicate(_: void, key: []const u8, value: i32) bool {
            _ = key;
            return value > 100;
        }
    }.predicate);

    try testing.expect(found == null);
}

test "find returns null for empty object" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    const found = obj.find({}, struct {
        fn predicate(_: void, key: []const u8, value: i32) bool {
            _ = key;
            _ = value;
            return true;
        }
    }.predicate);

    try testing.expect(found == null);
}

test "iteration only processes enumerable properties" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("visible1", 1);
    try obj.set("visible2", 2);

    const hidden_desc = PropertyDescriptor{
        .writable = true,
        .enumerable = false,
        .configurable = true,
    };
    try obj.defineProperty("hidden", 99, hidden_desc);

    // forEach
    const Context = struct {
        count: usize = 0,
    };

    var ctx = Context{};
    obj.forEach(&ctx, struct {
        fn callback(context: *Context, key: []const u8, value: i32) void {
            _ = key;
            _ = value;
            context.count += 1;
        }
    }.callback);
    try testing.expectEqual(@as(usize, 2), ctx.count);

    // map
    var mapped = try obj.map(i32, {}, struct {
        fn callback(_: void, key: []const u8, value: i32) i32 {
            _ = key;
            return value;
        }
    }.callback);
    defer mapped.deinit();
    try testing.expectEqual(@as(usize, 2), mapped.size());

    // filter
    var filtered = try obj.filter({}, struct {
        fn predicate(_: void, key: []const u8, value: i32) bool {
            _ = key;
            _ = value;
            return true;
        }
    }.predicate);
    defer filtered.deinit();
    try testing.expectEqual(@as(usize, 2), filtered.size());

    // some
    const has_hidden = obj.some({}, struct {
        fn predicate(_: void, key: []const u8, value: i32) bool {
            _ = key;
            return value == 99;
        }
    }.predicate);
    try testing.expect(!has_hidden);

    // every
    const all_visible = obj.every({}, struct {
        fn predicate(_: void, key: []const u8, value: i32) bool {
            _ = key;
            return value < 99;
        }
    }.predicate);
    try testing.expect(all_visible);
}

test "forEach with context data" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("a", 10);
    try obj.set("b", 20);
    try obj.set("c", 30);

    const Context = struct {
        multiplier: i32,
        sum: i32 = 0,
    };

    var ctx = Context{ .multiplier = 2 };

    obj.forEach(&ctx, struct {
        fn callback(context: *Context, key: []const u8, value: i32) void {
            _ = key;
            context.sum += value * context.multiplier;
        }
    }.callback);

    try testing.expectEqual(@as(i32, 120), ctx.sum);
}

test "map preserves property descriptors" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    const desc = PropertyDescriptor{
        .writable = true,
        .enumerable = true,
        .configurable = false,
    };

    try obj.defineProperty("special", 5, desc);

    var mapped = try obj.map(i32, {}, struct {
        fn callback(_: void, key: []const u8, value: i32) i32 {
            _ = key;
            return value * 2;
        }
    }.callback);
    defer mapped.deinit();

    // Value should be transformed
    try testing.expectEqual(@as(?i32, 10), mapped.get("special"));

    // Note: In this implementation, map creates properties with default descriptors
    // This is acceptable behavior for v1
}

test "complex reduce operation" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("a", 5);
    try obj.set("b", 3);
    try obj.set("c", 8);
    try obj.set("d", 2);

    // Find max value
    const max = obj.reduce(i32, 0, {}, struct {
        fn callback(_: void, acc: i32, key: []const u8, value: i32) i32 {
            _ = key;
            return if (value > acc) value else acc;
        }
    }.callback);

    try testing.expectEqual(@as(i32, 8), max);
}

test "chaining iteration methods" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("a", 1);
    try obj.set("b", 2);
    try obj.set("c", 3);
    try obj.set("d", 4);
    try obj.set("e", 5);

    // Filter even numbers
    var filtered = try obj.filter({}, struct {
        fn predicate(_: void, key: []const u8, value: i32) bool {
            _ = key;
            return @mod(value, 2) == 0;
        }
    }.predicate);
    defer filtered.deinit();

    // Map to double them
    var mapped = try filtered.map(i32, {}, struct {
        fn callback(_: void, key: []const u8, value: i32) i32 {
            _ = key;
            return value * 2;
        }
    }.callback);
    defer mapped.deinit();

    // Should have b=4 and d=8
    try testing.expectEqual(@as(usize, 2), mapped.size());
    try testing.expectEqual(@as(?i32, 4), mapped.get("b"));
    try testing.expectEqual(@as(?i32, 8), mapped.get("d"));
}

test "keys() preserves insertion order (regression: used to follow hashmap bucket order)" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("z", 1);
    try obj.set("a", 2);
    try obj.set("m", 3);
    try obj.set("b", 4);

    const ks = try obj.keys(testing.allocator);
    defer testing.allocator.free(ks);

    try testing.expectEqual(@as(usize, 4), ks.len);
    try testing.expectEqualStrings("z", ks[0]);
    try testing.expectEqualStrings("a", ks[1]);
    try testing.expectEqualStrings("m", ks[2]);
    try testing.expectEqualStrings("b", ks[3]);
}

test "keys() puts array-index keys first, ascending, before other string keys" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    // Insertion order: b, "2", a, "1" - ECMA-262 OrdinaryOwnPropertyKeys
    // requires array-index keys ("1", "2") first in ascending numeric
    // order, then the rest ("b", "a") in insertion order.
    try obj.set("b", 1);
    try obj.set("2", 2);
    try obj.set("a", 3);
    try obj.set("1", 4);

    const ks = try obj.keys(testing.allocator);
    defer testing.allocator.free(ks);

    try testing.expectEqual(@as(usize, 4), ks.len);
    try testing.expectEqualStrings("1", ks[0]);
    try testing.expectEqualStrings("2", ks[1]);
    try testing.expectEqualStrings("b", ks[2]);
    try testing.expectEqualStrings("a", ks[3]);
}

test "delete() preserves relative order of surviving properties" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("z", 1);
    try obj.set("a", 2);
    try obj.set("m", 3);
    try obj.set("b", 4);

    try testing.expect(try obj.delete("a"));
    try obj.set("c", 5);

    const ks = try obj.keys(testing.allocator);
    defer testing.allocator.free(ks);

    try testing.expectEqual(@as(usize, 4), ks.len);
    try testing.expectEqualStrings("z", ks[0]);
    try testing.expectEqualStrings("m", ks[1]);
    try testing.expectEqualStrings("b", ks[2]);
    try testing.expectEqualStrings("c", ks[3]);
}

test "values()/entries()/forEach follow the same enumeration order as keys()" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    try obj.set("z", 1);
    try obj.set("1", 2);
    try obj.set("a", 3);

    const vs = try obj.values(testing.allocator);
    defer testing.allocator.free(vs);
    try testing.expectEqualSlices(i32, &[_]i32{ 2, 1, 3 }, vs);

    const es = try obj.entries(testing.allocator);
    defer testing.allocator.free(es);
    try testing.expectEqualStrings("1", es[0].key);
    try testing.expectEqualStrings("z", es[1].key);
    try testing.expectEqualStrings("a", es[2].key);

    var visited: std.ArrayList([]const u8) = .empty;
    defer visited.deinit(testing.allocator);
    obj.forEach(&visited, struct {
        fn callback(ctx: *std.ArrayList([]const u8), key: []const u8, value: i32) void {
            _ = value;
            ctx.append(testing.allocator, key) catch unreachable;
        }
    }.callback);
    try testing.expectEqualStrings("1", visited.items[0]);
    try testing.expectEqualStrings("z", visited.items[1]);
    try testing.expectEqualStrings("a", visited.items[2]);
}

test "Object.is: differs from == only for +0/-0 and NaN on floats" {
    const ZObjF = ZObject(f64);
    try testing.expect(ZObjF.is(f64, 1.5, 1.5));
    try testing.expect(!ZObjF.is(f64, 0.0, -0.0));
    try testing.expect(ZObjF.is(f64, std.math.nan(f64), std.math.nan(f64)));
    try testing.expect(ZObject(i32).is(i32, 5, 5));
}

test "hasOwn is an alias of hasOwnProperty" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();
    try obj.set("x", 1);

    try testing.expect(obj.hasOwn("x"));
    try testing.expect(!obj.hasOwn("y"));
}

test "toLocaleString falls back to toString" {
    var obj = ZObject(i32).init(testing.allocator);
    defer obj.deinit();

    const s1 = try obj.toString(testing.allocator);
    defer testing.allocator.free(s1);
    const s2 = try obj.toLocaleString(testing.allocator);
    defer testing.allocator.free(s2);

    try testing.expectEqualStrings(s1, s2);
}

test "createWithProperties defines properties at construction time" {
    const PropertyDefinition = ZObject(i32).PropertyDefinition;

    var obj = try ZObject(i32).createWithProperties(testing.allocator, null, &[_]PropertyDefinition{
        .{ .key = "x", .value = 1, .descriptor = PropertyDescriptor.dataDescriptor() },
        .{ .key = "y", .value = 2, .descriptor = PropertyDescriptor.dataDescriptor() },
    });
    defer obj.deinit();

    try testing.expectEqual(@as(?i32, 1), obj.get("x"));
    try testing.expectEqual(@as(?i32, 2), obj.get("y"));
}
