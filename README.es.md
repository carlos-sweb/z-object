# Z-Object

Implementación de objetos compatible con ECMAScript de alto rendimiento en Zig 0.16

[![Zig](https://img.shields.io/badge/zig-0.16.0-orange.svg)](https://ziglang.org/download/)
[![Tests](https://img.shields.io/badge/tests-125%20passing-brightgreen.svg)](https://github.com/yourusername/z-object)
[![Licencia](https://img.shields.io/badge/licencia-MIT-blue.svg)](LICENSE)

## Características

- ✅ **Cobertura práctica de la API `Object.*`** para el caso genérico homogéneo de tipado estático — ver [Limitaciones de Diseño](#limitaciones-de-diseño) para lo que queda fuera de alcance (las accessor properties/getters-setters están declaradas en `PropertyDescriptor` pero no conectadas a ninguna lógica real de getter/setter; los objetos prototipo no tienen conteo de referencias, su lifetime es responsabilidad del caller)
- ⚡ **Alto Rendimiento** - Construido sobre la eficiente implementación HashMap de Zig
- 🔒 **Seguro en Memoria** - Gestión adecuada de allocators y patrones RAII
- 🎯 **Genérico en Tipos** - Genéricos en tiempo de compilación para cualquier tipo de valor
- 🧪 **Suite de Pruebas Comprehensiva** - 117+ pruebas cubriendo toda la funcionalidad
- 🎨 **Flujo de Control Elegante** - Bloques etiquetados para intención clara
- 📦 **Soporte de Property Descriptors** - Soporte completo para writable, enumerable, configurable
- 🔗 **Implementación de Cadena de Prototipos** - Herencia de prototipos completa
- 🛡️ **Manejo de Errores Elegante** - Tipos de error personalizados con contexto
- 🔥 **Freeze/Seal/Extensible** - Niveles de integridad de objetos completamente implementados

## Inicio Rápido

```zig
const std = @import("std");
const ZObject = @import("zobject").ZObject;

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Crear objeto
    var obj = ZObject(i32).init(allocator);
    defer obj.deinit();

    // Estabecer propiedades
    try obj.set("age", 25);
    try obj.set("score", 100);
        
    // Obtener propiedades

    _ = obj.get("age") orelse {
        std.debug.print("Dont exists age field\n", .{});
        return;
    };

    if (obj.get("age")) |age| {
        std.debug.print("{}\n", .{age});
    } else {
        std.debug.print("No encontrado\n", .{});
    }

    // Object.keys()
    const keys_list = try obj.keys(allocator);
    defer allocator.free(keys_list);

    // Object.freeze()
    obj.freeze();

    // Esto fallará (objecto congelado)
    obj.set("newProp", 42) catch |err| {
        std.debug.print("Error: {}\n", .{err});
    };
}  
```

## Instalación

### Usando el Gestor de Paquetes de Zig

Agregar a tu `build.zig.zon`:

```zig
.dependencies = .{
    .zobject = .{
        .url = "https://github.com/yourusername/z-object/archive/main.tar.gz",
        .hash = "...", // Ejecutar zig build para obtener el hash
    },
},
```

Luego en tu `build.zig`:

```zig
const zobject_dep = b.dependency("zobject", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zobject", zobject_dep.module("zobject"));
```

## Referencia de API

### Métodos Estáticos (ECMAScript Object.*)

| Método | Equivalente ECMAScript | Descripción |
|--------|----------------------|-------------|
| `keys()` | `Object.keys()` | Obtener array de claves enumerables |
| `values()` | `Object.values()` | Obtener array de valores enumerables |
| `entries()` | `Object.entries()` | Obtener array de pares [clave, valor] |
| `assign()` | `Object.assign()` | Copiar propiedades enumerables |
| `create()` | `Object.create()` | Crear con prototipo específico |
| `freeze()` | `Object.freeze()` | Congelar objeto (immutable) |
| `seal()` | `Object.seal()` | Sellar objeto (sin agregar/eliminar) |
| `preventExtensions()` | `Object.preventExtensions()` | Prevenir nuevas propiedades |
| `fromEntries()` | `Object.fromEntries()` | Crear desde entradas |
| `getOwnPropertyNames()` | `Object.getOwnPropertyNames()` | Obtener todos los nombres de propiedades |
| `isFrozen()` | `Object.isFrozen()` | Verificar si está congelado |
| `isSealed()` | `Object.isSealed()` | Verificar si está sellado |
| `isExtensible()` | `Object.isExtensible()` | Verificar si es extensible |
| `hasOwn(key)` | `Object.hasOwn()` (ES2022) | Alias de `hasOwnProperty(key)` |
| `is(FT, a, b)` | `Object.is()` | Algoritmo SameValue — difiere de `==` solo para `+0`/`-0` y `NaN` en floats |
| `createWithProperties(allocator, proto, props)` | `Object.create(proto, propertiesObject)` | Como `create()`, pero además define propiedades en la misma llamada |

### Métodos de Instancia

| Método | Descripción |
|--------|-------------|
| `set(key, value)` | Establecer valor de propiedad |
| `get(key)` | Obtener valor de propiedad — propiedades propias, luego la cadena de prototipos (`[[Get]]` de ECMA-262); no se filtra por enumerabilidad |
| `getOwn(key)` | Obtener valor de propiedad, solo propiedades propias, sin recorrer la cadena de prototipos |
| `delete(key)` | Eliminar propiedad |
| `has(key)` | Verificar si existe propiedad (incluye prototipo) |
| `hasOwnProperty(key)` | Verificar si existe propiedad propia |
| `size()` | Obtener número de propiedades propias |
| `clear()` | Remover todas las propiedades |
| `propertyIsEnumerable(key)` | Verificar si propiedad es enumerable |
| `toString()` | Obtener representación en string |
| `toLocaleString()` | Alias de `toString()` (sin base de datos de locales real, igual que z-array/z-number) |
| `valueOf()` | Obtener valor primitivo |
| `isPrototypeOf(other)` | Verificar relación de prototipo |

### Property Descriptors

| Método | Descripción |
|--------|-------------|
| `defineProperty(key, value, descriptor)` | Definir propiedad con descriptor |
| `defineProperties(props)` | Definir múltiples propiedades |
| `getOwnPropertyDescriptor(key)` | Obtener descriptor de propiedad |
| `getOwnPropertyDescriptors()` | Obtener todos los descriptores |
| `updateDescriptor(key, descriptor)` | Actualizar descriptor de propiedad |

### Cadena de Prototipos

| Método | Descripción |
|--------|-------------|
| `setPrototype(proto)` | Establecer prototipo (Object.setPrototypeOf) |
| `getPrototype()` | Obtener prototipo (Object.getPrototypeOf) |
| `lookupInChain(key)` | Buscar propiedad en cadena |
| `hasInChain(key)` | Verificar si existe propiedad en cadena |
| `getAllPropertiesInChain()` | Obtener todas las propiedades incluyendo heredadas |

### Métodos de Iteración

| Método | Descripción |
|--------|-------------|
| `forEach(context, callback)` | Iterar sobre propiedades enumerables |
| `map(U, context, callback)` | Mapear a nuevo objeto (puede cambiar tipo) |
| `filter(context, predicate)` | Filtrar propiedades |
| `reduce(U, initial, context, callback)` | Reducir propiedades a un solo valor |
| `some(context, predicate)` | Verificar si alguna propiedad coincide |
| `every(context, predicate)` | Verificar si todas las propiedades coinciden |
| `find(context, predicate)` | Encontrar primera propiedad coincidente |

## Ejemplos

### Property Descriptors

```zig
const PropertyDescriptor = @import("zobject").PropertyDescriptor;

var obj = ZObject(i32).init(allocator);
defer obj.deinit();

// Definir propiedad no-escribible
try obj.defineProperty("constant", 42, .{
    .writable = false,
    .enumerable = true,
    .configurable = false,
});

// Esto fallará
obj.set("constant", 100) catch |err| {
    // Error: PropertyNotWritable
};
```

### Cadena de Prototipos

```zig
// Crear prototipo
var proto = ZObject(i32).init(allocator);
defer proto.deinit();
try proto.set("inherited", 100);

// Crear objeto con prototipo
var obj = try ZObject(i32).create(allocator, &proto);
defer obj.deinit();

// Buscar en cadena
const value = obj.lookupInChain("inherited"); // retorna 100

// Verificar relación de prototipo
const is_proto = proto.isPrototypeOf(&obj); // retorna true
```

### Iteración

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

// ctx.sum es ahora 6

// map a tipo diferente
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

### Freeze, Seal y Extensible

```zig
var obj = ZObject(i32).init(allocator);
defer obj.deinit();

try obj.set("existing", 100);

// Freeze: completamente immutable
obj.freeze();
obj.set("new", 200) catch {}; // Error: ObjectIsFrozen
obj.set("existing", 200) catch {}; // Error: ObjectIsFrozen
obj.delete("existing") catch {}; // Error: ObjectIsFrozen

// Seal: puede modificar pero no agregar/eliminar
obj2.seal();
try obj2.set("existing", 200); // OK
obj2.set("new", 300) catch {}; // Error: ObjectNotExtensible
obj2.delete("existing") catch {}; // Error: PropertyNotConfigurable

// Prevent extensions: solo puede agregar propiedades
obj3.preventExtensions();
try obj3.set("existing", 200); // OK
obj3.set("new", 300) catch {}; // Error: ObjectNotExtensible
try obj3.delete("existing"); // OK (aún configurable)
```

## Limitaciones de Diseño

- **Las accessor properties (getters/setters) no están implementadas.** `PropertyDescriptor` declara los campos `get`/`set`/`value`, pero nada en `ZObject` los conecta a un comportamiento real de getter/setter — toda propiedad acá es una data property. La validación de "data vs. accessor descriptor" de `defineProperty` es efectivamente un no-op dado esto.
- **`prototype: ?*Self` no tiene conteo de referencias ni gestión de lifetime.** Establecer un objeto como prototipo de otro no extiende su lifetime; el caller debe asegurarse de que el prototipo sobreviva a cada objeto que lo referencia. (Si consumís `ZObject` a través de `JSValue` de [z-value](https://github.com/carlos-sweb/z-value), este gap también está documentado ahí.)
- **`get(key)`/`getOwn(key)`/los métodos de iteración nunca filtran por `writable`/`configurable`** — solo `enumerable` filtra la iteración (`keys`/`values`/`entries`/`forEach`/`map`/`filter`/`reduce`/`some`/`every`/`find`), igualando a ECMA-262; `get`/`getOwn` no filtran por ningún flag de descriptor, también igualando al spec.
- **`forEach`/`reduce`/`some`/`every`/`find` no retornan union de error**, pero ahora necesitan una asignación chica de scratch para calcular el orden de enumeración. Un fallo de asignación ahí se trata silenciosamente como "nada que iterar" (`forEach` retorna sin llamar al callback, `reduce` retorna el acumulador inicial sin tocar, `some`/`find` reportan sin coincidencia, `every` reporta true) en vez de propagarse — aceptable para la asignación chica y acotada involucrada (proporcional a la cantidad de propiedades propias del objeto), pero vale saberlo si estás auditando rutas de manejo de OOM.

### Orden de enumeración (OrdinaryOwnPropertyKeys de ECMA-262)

`keys()`, `values()`, `entries()`, `getOwnPropertyNames()`, `getOwnPropertyDescriptors()`, `forEach`, `map`, `filter`, `reduce`, `some`, `every`, `find`, y el recorrido de la fuente en `assign()` ahora enumeran propiedades en el orden que exige el spec: claves array-index (strings de enteros no negativos canónicos, sin ceros a la izquierda, ≤ 2^32-2) primero en orden numérico ascendente, después el resto de las claves string en orden de inserción. Antes seguía el orden de buckets internos de `std.StringHashMap` (ni orden de inserción ni el del spec, y no estable entre builds) — arreglado cambiando el storage interno a un mapa array-backed (`std.array_hash_map.String`). `getAllPropertiesInChain()` es una utilidad de conveniencia que no corresponde a ningún método real del spec y todavía no garantiza un orden específico.

### Nota de breaking change

`get(key)` ahora camina la cadena de prototipos (antes solo verificaba propiedades propias, pese a que su propio doc-comment ya afirmaba lo contrario) — esto iguala la semántica real de `[[Get]]` de ECMAScript (`obj.prop` siempre incluye propiedades heredadas). El código que dependía del comportamiento viejo (solo propiedades propias) debe cambiar a usar el nuevo `getOwn(key)`.

## Compilación y Pruebas

```bash
# Ejecutar todas las pruebas
zig build test

# Ejecutar con resumen
zig build test --summary all

# Compilar en modo release
zig build -Doptimize=ReleaseFast
```

## Detalles de Implementación

### Bloques Etiquetados

Z-Object usa bloques etiquetados extensivamente para un flujo de control elegante. Ejemplos:

```zig
// Setter de propiedad con validación
setter: {
    if (self.is_frozen) return error.ObjectIsFrozen;
    if (!property.writable) return error.PropertyNotWritable;
    if (!self.is_extensible and !exists) return error.ObjectNotExtensible;
    break :setter;
}
// Proceder con la operación set

// Recorrido de cadena de prototipos
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

### Gestión de Memoria

Z-Object gestiona apropiadamente la memoria para todas las claves string:

```zig
// Las claves se duplican en la inserción
const key_copy = try allocator.dupe(u8, key);
errdefer allocator.free(key_copy);
try map.put(key_copy, value);

// Las claves se liberan en la eliminación
if (map.fetchRemove(key)) |entry| {
    allocator.free(entry.key);
}

// Todas las claves se liberan en deinit
var it = map.iterator();
while (it.next()) |entry| {
    allocator.free(entry.key_ptr.*);
}
map.deinit();
```

### Manejo de Errores

Tipos de error personalizados con nombres descriptivos:

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

## Licencia

Licencia MIT - ver archivo [LICENSE](LICENSE) para detalles

## Contribución

¡Las contribuciones son bienvenidas! Por favor, siéntete libre de enviar un Pull Request.

## Créditos

Construido con ❤️ usando [Zig](https://ziglang.org/) 0.16.0
