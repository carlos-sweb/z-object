# Z-Object

High-performance ECMAScript-compatible object implementation in Zig 0.16

[![Zig](https://img.shields.io/badge/zig-0.16.0-orange.svg)](https://ziglang.org/download/)
[![Tests](https://img.shields.io/badge/tests-125%20passing-brightgreen.svg)](https://github.com/yourusername/z-object)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Features

- ✅ **Practical `Object.*` API coverage** for the homogeneous, statically-typed generic case — see [Design Limitations](#design-limitations) for what's out of scope (accessor properties/getters-setters are declared in `PropertyDescriptor` but not wired into any real getter/setter behavior; prototype objects are not reference-counted, their lifetime is the caller's responsibility)
- ⚡ **High Performance** - Built on Zig's efficient HashMap implementation
- 🔒 **Memory Safe** - Proper allocator management and RAII patterns
- 🎯 **Type Generic** - Compile-time generics for any value type
- 🧪 **Comprehensive Test Suite** - 125+ tests covering all functionality
- 🎨 **Elegant Control Flow** - Labeled blocks for clear intent
- 📦 **Property Descriptors Support** - Full support for writable, enumerable, configurable
- 🔗 **Prototype Chain Implementation** - Complete prototype inheritance
- 🛡️ **Elegant Error Handling** - Custom error types with context
- 🔥 **Freeze/Seal/Extensible** - Object integrity levels fully implemented

## Quick Start

```zig
const std = @import("std");
const ZObject = @import("zobject").ZObject;

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create object
    var obj = ZObject(i32).init(allocator);
    defer obj.deinit();

    // Set properties
    try obj.set("age", 25);
    try obj.set("score", 100);
	
    // Get properties
	
    _ = obj.get("age") orelse {
        std.debug.print("Dont exists age field\n", .{});
        return;
    };

    if (obj.get("age")) |age| {
        std.debug.print("{}\n", .{age});
    } else {
        std.debug.print("Not found\n", .{});
    }

    // Object.keys()
    const keys_list = try obj.keys(allocator);
    defer allocator.free(keys_list);

    // Object.freeze()
    obj.freeze();

    // This will fail (object is frozen)
    obj.set("newProp", 42) catch |err| {
        std.debug.print("Error: {}\n", .{err});
    };
}
```

## Installation

### Using Zig Package Manager

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .zobject = .{
        .url = "https://github.com/yourusername/z-object/archive/main.tar.gz",
        .hash = "...", // Run zig build to get the hash
    },
},
```

Then in your `build.zig`:

```zig
const zobject_dep = b.dependency("zobject", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zobject", zobject_dep.module("zobject"));
```

## API Reference

### Static Methods (ECMAScript Object.*)

| Method | ECMAScript Equivalent | Description |
|--------|----------------------|-------------|
| `keys()` | `Object.keys()` | Get array of enumerable keys |
| `values()` | `Object.values()` | Get array of enumerable values |
| `entries()` | `Object.entries()` | Get array of [key, value] pairs |
| `assign()` | `Object.assign()` | Copy enumerable properties |
| `create()` | `Object.create()` | Create with specific prototype |
| `freeze()` | `Object.freeze()` | Freeze object (immutable) |
| `seal()` | `Object.seal()` | Seal object (no add/delete) |
| `preventExtensions()` | `Object.preventExtensions()` | Prevent new properties |
| `fromEntries()` | `Object.fromEntries()` | Create from entries |
| `getOwnPropertyNames()` | `Object.getOwnPropertyNames()` | Get all property names |
| `isFrozen()` | `Object.isFrozen()` | Check if frozen |
| `isSealed()` | `Object.isSealed()` | Check if sealed |
| `isExtensible()` | `Object.isExtensible()` | Check if extensible |
| `hasOwn(key)` | `Object.hasOwn()` (ES2022) | Alias of `hasOwnProperty(key)` |
| `is(FT, a, b)` | `Object.is()` | SameValue algorithm — differs from `==` only for float `+0`/`-0` and `NaN` |
| `createWithProperties(allocator, proto, props)` | `Object.create(proto, propertiesObject)` | Like `create()`, but also defines properties in the same call |

### Instance Methods

| Method | Description |
|--------|-------------|
| `set(key, value)` | Set property value |
| `get(key)` | Get property value — own properties, then the prototype chain (ECMA-262 `[[Get]]`); not gated by enumerability |
| `getOwn(key)` | Get property value, own properties only, no prototype chain walk |
| `delete(key)` | Delete property |
| `has(key)` | Check if property exists (includes prototype) |
| `hasOwnProperty(key)` | Check if own property exists |
| `size()` | Get number of own properties |
| `clear()` | Remove all properties |
| `propertyIsEnumerable(key)` | Check if property is enumerable |
| `toString()` | Get string representation |
| `toLocaleString()` | Alias of `toString()` (no real locale database, same as z-array/z-number) |
| `valueOf()` | Get primitive value |
| `isPrototypeOf(other)` | Check prototype relationship |

### Property Descriptors

| Method | Description |
|--------|-------------|
| `defineProperty(key, value, descriptor)` | Define property with descriptor |
| `defineProperties(props)` | Define multiple properties |
| `getOwnPropertyDescriptor(key)` | Get property descriptor |
| `getOwnPropertyDescriptors()` | Get all descriptors |
| `updateDescriptor(key, descriptor)` | Update property descriptor |

### Prototype Chain

| Method | Description |
|--------|-------------|
| `setPrototype(proto)` | Set prototype (Object.setPrototypeOf) |
| `getPrototype()` | Get prototype (Object.getPrototypeOf) |
| `lookupInChain(key)` | Lookup property in chain |
| `hasInChain(key)` | Check if property exists in chain |
| `getAllPropertiesInChain()` | Get all properties including inherited |

### Iteration Methods

| Method | Description |
|--------|-------------|
| `forEach(context, callback)` | Iterate over enumerable properties |
| `map(U, context, callback)` | Map to new object (can change type) |
| `filter(context, predicate)` | Filter properties |
| `reduce(U, initial, context, callback)` | Reduce properties to single value |
| `some(context, predicate)` | Check if any property matches |
| `every(context, predicate)` | Check if all properties match |
| `find(context, predicate)` | Find first matching property |

## Examples

### Property Descriptors

```zig
const PropertyDescriptor = @import("zobject").PropertyDescriptor;

var obj = ZObject(i32).init(allocator);
defer obj.deinit();

// Define non-writable property
try obj.defineProperty("constant", 42, .{
    .writable = false,
    .enumerable = true,
    .configurable = false,
});

// This will fail
obj.set("constant", 100) catch |err| {
    // Error: PropertyNotWritable
};
```

### Prototype Chain

```zig
// Create prototype
var proto = ZObject(i32).init(allocator);
defer proto.deinit();
try proto.set("inherited", 100);

// Create object with prototype
var obj = try ZObject(i32).create(allocator, &proto);
defer obj.deinit();

// Lookup in chain
const value = obj.lookupInChain("inherited"); // returns 100

// Check prototype relationship
const is_proto = proto.isPrototypeOf(&obj); // returns true
```

### Iteration

```zig
var obj = ZObject(i32).init(allocator);
defer obj.deinit();

try obj.set("a", 1);
try obj.set("b", 2);
try obj.set("c", 3);

// forEach
const Context = struct { sum: i32 = 0 };
var ctx = Context{};

obj.forEach(&ctx, struct {
    fn callback(context: *Context, key: []const u8, value: i32) void {
        _ = key;
        context.sum += value;
    }
}.callback);

// ctx.sum is now 6

// map to different type
var doubled = try obj.map(i32, {}, struct {
    fn callback(_: void, key: []const u8, value: i32) i32 {
        _ = key;
        return value * 2;
    }
}.callback);
defer doubled.deinit();

// filter
var filtered = try obj.filter({}, struct {
    fn predicate(_: void, key: []const u8, value: i32) bool {
        _ = key;
        return value > 1;
    }
}.predicate);
defer filtered.deinit();
```

### Freeze, Seal, and Extensible

```zig
var obj = ZObject(i32).init(allocator);
defer obj.deinit();

try obj.set("existing", 100);

// Freeze: completely immutable
obj.freeze();
obj.set("new", 200) catch {}; // Error: ObjectIsFrozen
obj.set("existing", 200) catch {}; // Error: ObjectIsFrozen
obj.delete("existing") catch {}; // Error: ObjectIsFrozen

// Seal: can modify but not add/delete
obj2.seal();
try obj2.set("existing", 200); // OK
obj2.set("new", 300) catch {}; // Error: ObjectNotExtensible
obj2.delete("existing") catch {}; // Error: PropertyNotConfigurable

// Prevent extensions: can only add properties
obj3.preventExtensions();
try obj3.set("existing", 200); // OK
obj3.set("new", 300) catch {}; // Error: ObjectNotExtensible
try obj3.delete("existing"); // OK (still configurable)
```

## Design Limitations

- **Accessor properties (getters/setters) are not implemented.** `PropertyDescriptor` declares `get`/`set`/`value` fields, but nothing in `ZObject` ever wires them into real getter/setter behavior — every property here is a data property. `defineProperty`'s validation of "data vs. accessor descriptor" is effectively a no-op today given that.
- **`prototype: ?*Self` is not reference-counted or otherwise lifetime-managed.** Setting an object as another's prototype does not extend its lifetime; the caller must ensure the prototype outlives every object that points to it. (If you're consuming `ZObject` through [z-value](https://github.com/carlos-sweb/z-value)'s `JSValue`, this is documented there too as a known gap.)
- **`get(key)`/`getOwn(key)`/iteration methods never filter by `writable`/`configurable`** — only `enumerable` gates iteration (`keys`/`values`/`entries`/`forEach`/`map`/`filter`/`reduce`/`some`/`every`/`find`), matching ECMA-262; `get`/`getOwn` never filter by any descriptor flag, also matching spec.
- **`forEach`/`reduce`/`some`/`every`/`find` don't return an error union**, but now need a small scratch allocation to compute enumeration order. An allocation failure there is silently treated as "nothing to iterate" (`forEach` returns without calling the callback, `reduce` returns the untouched initial accumulator, `some`/`find` report no match, `every` reports true) rather than propagated — acceptable for the tiny, bounded allocation involved (proportional to the object's own property count), but worth knowing if you're auditing OOM-handling paths.

### Enumeration order (ECMA-262 OrdinaryOwnPropertyKeys)

`keys()`, `values()`, `entries()`, `getOwnPropertyNames()`, `getOwnPropertyDescriptors()`, `forEach`, `map`, `filter`, `reduce`, `some`, `every`, `find`, and `assign()`'s source traversal now enumerate properties in the order the spec requires: array-index keys (canonical non-negative integer strings, no leading zeros, ≤ 2^32-2) first in ascending numeric order, then the rest of the string keys in insertion order. This used to follow `std.StringHashMap`'s internal bucket order (neither insertion order nor spec order, and not stable across builds) — fixed by switching the internal storage to an array-backed map (`std.array_hash_map.String`). `getAllPropertiesInChain()` is a non-spec convenience utility and still doesn't guarantee a specific order.

### Breaking change note

`get(key)` now walks the prototype chain (previously it only checked own properties, despite its doc comment already claiming otherwise) — this matches real ECMAScript `[[Get]]` semantics (`obj.prop` always includes inherited properties). Code that relied on the old own-properties-only behavior should switch to the new `getOwn(key)`.

## Building and Testing

```bash
# Run all tests
zig build test

# Run with summary
zig build test --summary all

# Build in release mode
zig build -Doptimize=ReleaseFast
```

## Implementation Details

### Labeled Blocks

Z-Object uses labeled blocks extensively for elegant control flow. Examples:

```zig
// Property setter with validation
setter: {
    if (self.is_frozen) return error.ObjectIsFrozen;
    if (!property.writable) return error.PropertyNotWritable;
    if (!self.is_extensible and !exists) return error.ObjectNotExtensible;
    break :setter;
}
// Proceed with set operation

// Prototype chain traversal
chain_walker: {
    while (current) |obj| {
        if (obj.properties.get(key)) |prop| {
            return prop.value;
        }
        current = obj.prototype;
    }
    break :chain_walker;
}
```

### Memory Management

Z-Object properly manages memory for all string keys:

```zig
// Keys are duplicated on insertion
const key_copy = try allocator.dupe(u8, key);
errdefer allocator.free(key_copy);
try map.put(key_copy, value);

// Keys are freed on deletion
if (map.fetchRemove(key)) |entry| {
    allocator.free(entry.key);
}

// All keys freed on deinit
var it = map.iterator();
while (it.next()) |entry| {
    allocator.free(entry.key_ptr.*);
}
map.deinit();
```

### Error Handling

Custom error types with descriptive names:

```zig
pub const ZObjectError = error{
    OutOfMemory,
    PropertyNotFound,
    PropertyNotWritable,
    PropertyNotConfigurable,
    ObjectIsFrozen,
    ObjectIsSealed,
    ObjectNotExtensible,
    InvalidDescriptor,
    InvalidState,
    PrototypeCycle,
    KeyAlreadyExists,
};
```

## License

MIT License - see [LICENSE](LICENSE) file for details

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Credits

Built with ❤️ using [Zig](https://ziglang.org/) 0.16.0
