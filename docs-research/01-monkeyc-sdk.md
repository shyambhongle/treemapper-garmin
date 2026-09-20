# Garmin Connect IQ / Monkey C — Technical Briefing

> Sourced from developer.garmin.com. The doc site is a Gatsby SPA; article bodies live at
> `https://developer.garmin.com/connect-iq/articles/<section>/<File_Name>.html` (the nav URLs render empty to fetchers). Full URL list at the end.

---

## 1. Monkey C language essentials

### 1.1 Nature of the language
- Object-oriented, compiles to **bytecode run by a VM** (Java-like), but memory is managed by **reference counting**, not a tracing GC.
- **Duck typed** by default. No true primitives: Numbers, Floats, Chars are objects with methods.
- **Message-passed**: function/symbol lookup happens at *runtime* against a scope hierarchy (see 1.13).
- **Functions are not first class.** You cannot pass a function as a callback; you pass a `Lang.Method` object.
- Objects are compiled; you cannot add members at runtime (unlike Ruby/Python).
- All variables must be declared before use.
- You import **modules**, not classes.

```monkeyc
function add( a, b ) {
    return a + b;
}
function thisFunctionUsesAdd() {
    var a = add( 1, 3 );              // 4
    var b = add( "Hello ", "World" ); // "Hello World"
}
```

### 1.2 Full primitive / container type list

| Type | Meaning | Literal |
|---|---|---|
| `Null` | null reference | `var n = null;` |
| `Number` | 32-bit signed int | `var x = 5;` |
| `Float` | 32-bit float | `var y = 6.0;` |
| `Long` | 64-bit signed int | `var l = 5l;` |
| `Double` | 64-bit float | `var d = 4.0d;` |
| `Boolean` | true/false | `var b = true;` |
| `Char` | UTF-32 character | `var c = 'x';` |
| `String` | char sequence | `var s = "Hello";` |
| `Symbol` | lightweight constant identifier | `var sym = :mySymbol;` |
| `Array` | fixed size, numerically indexed | `var a = new [50];` / `[1,2,3]` |
| `Dictionary` | hash map | `var d = { "a" => 1 };` |
| `ByteArray` | byte buffer (Lang) | — |
| `Method` | bound callable | `obj.method(:foo)` |
| `WeakReference` | non-counting reference | `obj.weak()` |
| `ResourceId` | compiler-generated resource handle | `Rez.Drawables.icon` |
| `Object` | root class | — |

Lang typedefs: `Numeric` (Number/Float/Long/Double), `Integer` (Number/Long), `Decimal` (Float/Double), `Comparable`, `Comparator`.

### 1.3 Operators and precedence

Precedence (high → low):
1. `new`, `!`, `~`, `()`
2. `*`, `/`, `%`, `&`, `<<`, `>>`
3. `+`, `-`, `|`, `^`
4. `<`, `<=`, `>`, `>=`, `==`, `!=`
5. `&&` / `and`
6. `||` / `or`

Note the **unusual precedence**: bitwise `&` binds like multiplication, `|`/`^` like addition. Comparison ops are all one level.

Assignment: `= += -= *= /= %= <<= >>= &= |= ^=`. Increment/decrement `++ --` (prefix and postfix). Ternary `a ? 1 : 2`.

Truthiness: *non-null is true; `0` is false.* `&&`/`||` short-circuit and **return the operand value**, not a Boolean.

### 1.4 Keywords
`break case catch class const continue default do else enum extends finally for function has hidden if instanceof me module native new private protected public return self static switch throw try using var while as`
Literals (not keywords): `true false null NaN`, plus operators `and`, `or`.

### 1.5 Symbols, constants, enums

```monkeyc
var a = :symbol_1;
var b = :symbol_1;
Sys.println( a == b );   // true

var person = { :firstName=>"Bob", :lastName=>"Jones" };

const PI = 3.14;                 // module or class level only, NOT inside functions
const BANANA_YELLOW = "#FFE135";

enum { Monday, Tuesday, Wednesday }   // 0,1,2
enum { x = 1337, y, z, a = 0, b, c }  // 1337,1338,1339,0,1,2
```
`const` on an array prevents *rebinding*, not element mutation. Enum values must be integers (except when used as a Monkey Types named enum with other value types).

### 1.6 Control flow
- `if` condition must be an **expression**; assignments are not allowed inside it.
- **Loops must have braces** — single-statement loops are not supported.
- `switch` supports fall-through, `case instanceof MyClass:`, and mixed-type cases.
- **Switch scoping trap**: `var` declared directly in a switch block is scoped to the whole switch; it must be initialized before use in a later case, and redeclaring it in a later case is a compile error. A `{ }`-braced case body creates its own scope.

```monkeyc
switch ( obj ) {
    case true:
    var aaa = 1;            // scoped at switch-block level
    case 1:
    var zzz = aaa;          // ERROR: aaa not initialized in this case
    case "B": {
       var aaa = true;      // OK: braced case = local scope
    }
    case instanceof MyClass:
    var aaa = "Hello!";     // ERROR: already defined at switch level
    aaa = 0;                // OK
}
```

### 1.7 Classes, `initialize`, `self`/`me`, inheritance

```monkeyc
class Circle {
    protected var mRadius;
    public function initialize( aRadius ) { mRadius = aRadius; }
}
var c = new Circle( 1.5 );
```
- `initialize()` is the constructor, invoked automatically by `new`.
- **Monkey C does NOT implicitly call the parent's `initialize()`** — call it explicitly, as the first line:

```monkeyc
class Sphere extends Circle {
    function initialize(aRadius) { Circle.initialize(aRadius); }
    function getArea() { return 4 * Math.PI * Math.pow(self.mRadius, 2); }
    function describe() { System.print("I'm a Sphere! My parent is a "); Circle.describe(); }
}
```
- Call a superclass method via `ParentClassName.method()`. **`superclass.memberVariable` syntax is not supported.**
- `self` and `me` both mean "this instance".
- Nested classes: the outer class must be instantiated first, and nested classes have **no access to enclosing class members** (unlike Java).
- **No function overloading** (duck typing). Emulate with `instanceof` dispatch or an options dictionary:

```monkeyc
function aPolymorphicFunction(a) {
    switch(a) {
        case instanceof String: return doTheStringVersion(a);
        case instanceof Number:
        case instanceof Long:   return doTheNumericVersion(a);
        default: throw new UnexpectedTypeException();
    }
}
x = aPolymorphicFunction({ :param1=>"Foo", :param2=>"Bar" });
```

### 1.8 Access modifiers and static
- `public` (default), `protected`, `private`. `hidden` == `protected` (legacy synonym).
- **Data hiding exists only for class members. Modules have no access control** — no `private`/`protected`/`extends` on modules.
- `static` members belong to the class, shared across instances:

```monkeyc
class Conversion { static const FEET_PER_METER = 3.28084; }
System.println( Conversion.FEET_PER_METER );

class BananaBunch { static var mNumberOfBananas = 10; }
bunch1.mNumberOfBananas = 12;   // bunch2 also reads 12
```
- Convention: avoid public static members in classes; move them to the parent module (modules cost runtime memory, so also avoid gratuitous modules).

### 1.9 Modules, `using` vs `import`

```monkeyc
module MyModule {
    class Foo { var mValue; }
    var moduleVariable;
}
MyModule.moduleVariable = new MyModule.Foo();
```
- `using Toybox.System;` → brings only the **module name** into namespace; classes still need the prefix.
- `using Toybox.System as Sys;` → alias.
- `import Toybox.Lang;` → brings the module name **and its class names** into the namespace. **Use `import` when using Monkey Types**, otherwise type annotations need full module paths.

### 1.10 Closures / method references (callbacks)
Functions are not first class. Use `Lang.Method`:

```monkeyc
var v = new Foo();
var m = v.method(:operation);   // instance method
m.invoke(1, 2);

var mm = new Lang.Method(MyModule, :operation);  // module-level function
mm.invoke();
```
**A `Method` holds a STRONG reference to its source object.** This is the #1 source of leaks/circular references (a view holding a timer holding a method back to the view).

### 1.11 `has` and `instanceof`

```monkeyc
if ( value instanceof Toybox.Lang.Number ) { System.println("number"); }

var impl;
if ( Toybox has :Magnetometer ) { impl = new ImplementationWithMagnetometer(); }
else { impl = new ImplementationWithoutMagnetometer(); }

if (dc has :setAntiAlias) { dc.setAntiAlias(true); }
if (sensorInfo has :accel && sensorInfo.accel != null) { ... }
```
`has` checks whether an object/module/class contains a symbol (method, variable, nested module). This is the canonical way to write one codebase across many device generations and to avoid `Symbol Not Found` fatal errors.

### 1.12 Exceptions and fatal errors

```monkeyc
try {
    // ...
}
catch( ex instanceof AnExceptionClass ) { }
catch( ex ) { }
finally { }

throw new Lang.Exception();
```

Custom exception — extend `Toybox.Lang.Exception`, call super initializer, set `mMessage`:

```monkeyc
class AppSpecificException extends Lang.Exception {
    function initialize(msg) {
        Exception.initialize();
        self.mMessage = msg;
    }
}
```

`Toybox.Lang` exception classes: `Exception`, `InvalidOptionsException`, `InvalidValueException`, `OperationNotAllowedException`, `SerializationException`, `StorageFullException`, `SymbolNotAllowedException`, `UnexpectedTypeException`, `ValueOutOfBoundsException`.

**Uncatchable fatal errors** (kill the app):
Array Out Of Bounds · Circular Dependency · Communications Error · File Not Found · Illegal Frame · Initializer Error · Invalid Value · Null Reference · Out of Memory · Permission Required · Stack Underflow · Stack Overflow · Symbol Not Found · System Error · **Too Many Arguments (a method called with >10 arguments)** · Too Many Timers · Unexpected Type · Unhandled Exception · **Watchdog Tripped (a function ran too long)**.

### 1.13 Scope / symbol lookup order (runtime)
1. Instance members of the class
2. Members of the superclass
3. Static members of the class
4. Members of the parent module, up to global
5. Members of the superclass's parent module, up to global
6. Public static members of the parent module, up to global
7. Public static members of the superclass's parent module, up to global

**Bling `$`** restricts the search to the global namespace — both a disambiguator and a **performance optimization**:

```monkeyc
var globalScopedVariable = "Global String";
module A { class B { function c() {
    System.println(globalScopedVariable);     // walks the whole hierarchy
    System.println($.globalScopedVariable);   // direct global lookup (faster)
} } }
$.helloFunction();   // global function, not the class's override
```

### 1.14 String formatting

Two mechanisms:

**`Lang.format(formatString, paramArray)`** — positional `$1$`, `$2$` markers:
```monkeyc
using Toybox.Lang;
var myFormat = "Your next meeting is at $1$:$2$ on $3$ $4$ in room $5$.";
var myParams = [2, 30, "Sep", 4, "6820"];
var myString = Lang.format(myFormat, myParams);
// "Your next meeting is at 2:30 on Sep 4 in room 6820."
```

**`Number/Float/Long/Double.format(spec)`** — printf-style `"%[flags][width][.precision]specifier"`:
- Specifiers: `d`/`i` (signed decimal), `u` (unsigned decimal), `o` (octal), `x`/`X` (hex), `f` (float), `e`/`E` (scientific)
- Flags: `+` (always sign), `0` (zero pad)
- Width/precision must be literal numbers — `*` wildcard is **not** supported
```monkeyc
hours.format("%02d");     // "09"
value.format("%.2f");     // "12.34"
```

`Lang.String` methods: `compareTo`, `equals`, `hashCode`, `length`, `toString`, `find`, `substring`, `toLower`, `toUpper`, `toNumber`, `toNumberWithBase`, `toLong`, `toLongWithBase`, `toFloat`, `toDouble`, `toCharArray`, `toUtf8Array`. There is **no `String.format` instance method** — use `Lang.format` or number `.format()`.

### 1.15 Coding conventions (official)
- Modules/Classes: `UpperCamelCase`. Functions: `lowerCamelCase`.
- Private members: `_leadingUnderscoreCamelCase`. Public members: `lowerCamelCase`.
- Enums need a common prefix: `COLOR_RED`, `COLOR_BLUE`.
- One class per `.mc` file. Four-space indent. Opening brace on the same line.
- Always call the superclass `initialize()` as the first line of your `initialize()`.
- Minimize true globals; prefer class definitions in the global module over extra modules (modules cost runtime memory).

---

## 2. Monkey Types (optional static typing)

### 2.1 Type checking levels (`-l` / `--typecheck`, or `project.typecheck` in a jungle)
| Level | Name | Behavior |
|---|---|---|
| 0 | Silent | no type checking; everything dynamic |
| 1 | Gradual | check only where types can be inferred; silent otherwise |
| 2 | Informative | validate typed declarations; warn on ambiguity ("Maybe") |
| 3 | Strict | reject all compiler ambiguity |

The VS Code extension needs **gradual or higher** for full IntelliSense/error features.

### 2.2 Syntax

```monkeyc
import Toybox.Lang;

var globalX as Number = 0;
var globalY as Number or String = 0;

typedef Numeric as Number or Float or Long or Double;
typedef Addable as Number or Float or Long or Double or String;

function doWork() as Number or Null { ... }
function doWork2() as Number? { ... }        // ? shorthand for "or Null"
function doNothing() as Void { }             // returning a value is an error
```

### 2.3 Type categories
- **Any** — undecorated; full duck typing.
- **Void** — return-only.
- **Concrete** — a single class; accepts subclasses.
- **Poly** — union via `or`.
- **Interface** — structural typing:
```monkeyc
typedef LittleBoys as interface {
    var frogs as Array<Frogs>;
    var snails as Array<Snails>;
    var puppyDogTails as Array<PuppyDogTails>;
};
```
- **Container** — `Array<Number>`, `Dictionary<String, Number>`:
```monkeyc
var typedArray as Array<Number> = new Array<Number>[10];
var init as Array<Number> = [1,2,3,4,5] as Array<Number>;
var d as Dictionary<String,String> = {"this"=>"that"} as Dictionary<String,String>;
```
- **Tuple** — positional array types:
```monkeyc
function getInitialView() as [Views] or [Views, InputDelegates] {
    return [ new StartView(), new StartDelegate() ];
}
function foo(x as [Number, Number, Number]) as [Number, Number, Number] {
    x[1] = "Hello";   // allowed: type becomes [Number, String, Number]
    return x;         // ERROR: type mismatch
}
```
- **Dictionary literal / options pattern**:
```monkeyc
function doWork(options as {
    :option1 as String,
    :option2 as { "name" as String, "value" as Number }
})
```
- **Enum** — named enums can carry non-integer values in the type system:
```monkeyc
enum Dog { SPOT = "Spot", LUKE = "Luke" }
function getDogName(dog as Dog) as String { return dog.toString(); }
```
- **Callback**:
```monkeyc
function doWork(x as Method(a as Number) as String) as String { return x.invoke(2); }
```
- **Null** — `or Null` / `?`.

### 2.4 Compatibility results
Every assignment resolves to **True / False / Maybe**. `Maybe` is the ambiguity that level 3 rejects and level 2 warns on. Key rules: Any accepts and is accepted by everything (Maybe in reverse); Concrete accepts B if B is or extends A; Poly accepts if all source types are present in the destination; Interface accepts if the value has all required members; Containers match only if key **and** value types match exactly.

### 2.5 Local inference and if-splitting
Local variables (unlike class members) infer their type from assignment and can be reassigned to a different type. Branching produces poly types (`var x = null; if(a){x=true;}` → `Boolean or Null`).

```monkeyc
public function foo(x as Number?) as Boolean {
    if(x != null) { /* x is Number here */ }
    else          { /* x is Null here   */ }
}
```
Mutation table:

| Operator | Poly type | Concrete type |
|---|---|---|
| `== null` | mutate to Null | ignore |
| `!= null` | mutate to poly minus Null | ignore |
| `instanceof` | mutate to that type | mutate to that type |
| `!instanceof` | mutate to poly minus type | ignore |

`&&` carries mutations forward; `||` produces a union. **Calling any function clears type mutations on member variables** (it could have changed them) — copy a nullable member into a local before narrowing.

### 2.6 Class/module member typing
- Members default to `Any`; `const` infers from its assignment.
- A typed member **must** be initialized (in the declaration or in `initialize()`) or be nullable, otherwise compile error.
```monkeyc
class Messenger {
    private var _message as String;        // ERROR if never initialized
    public function initialize() { _message = ""; }
}
```
- `(:initialized)` annotation tells the checker a member will be initialized before use.
- Inheritance: overriding with the same arg count and **no** decoration inherits the parent's types verbatim; adding decoration means it must match the parent exactly.

### 2.7 Runtime limits of the type system
Types are **compile-time only**. `instanceof` and `has` work on concrete classes only — **interfaces cannot be checked at runtime**; test for members instead:
```monkeyc
if(jack has :isNimble and jack has :isQuick and jack has :jumpOverCandleStick) { ... }
```
`as` is a pure compile-time cast with no runtime effect: `(a as MyView).specialMyViewMethod();`

### 2.8 Scope checking annotations
The checker verifies that symbols used in background/glance scope actually exist there.
```monkeyc
:typecheck(disableBackgroundCheck)
:typecheck(disableGlanceCheck)
:typecheck([disableBackgroundCheck, disableGlanceCheck])
```

---

## 3. Memory model

### 3.1 Reference counting
Monkey C frees memory when an object's reference count hits zero — chosen because it reclaims memory immediately, which matters on tiny heaps. (Note: one Garmin doc calls it "garbage collection"; the authoritative Objects-and-Memory page states reference counting.)

### 3.2 Circular references
If A references B and B references A, dropping the outside reference leaves both at refcount 1 → **permanently leaked**. Classic sources: a `Method` callback (strong ref to its owner), parent/child view graphs, delegates holding views that hold delegates.

### 3.3 WeakReference

```monkeyc
var weakRef = obj.weak();

class WeakReference {
    function stillAlive();
    function get();
}

if( weakRef.stillAlive() ) {
    var strongRef = weakRef.get();
    strongRef.doTheThing();
}
```
- On immutable types (`Number, Float, Char, Long, Double, String`) `weak()` returns the object itself.
- Keep the strong reference **only in the needed scope**.

### 3.4 Heap and handles
- Since Connect IQ **2.4.x**, memory handles come from a dynamically allocated heap. Each *unique object* consumes one handle; extra references do not allocate.
- Pre-2.4 devices have a smaller, **static** per-device object limit. Exceeding it is a runtime error.
- Peak memory is what matters. Exceeding the budget kills the app (watch faces fall back to the default face). Evidence lands in `GARMIN/APPS/LOGS/CIQ_LOG.YAML` (or `CIQ_LOG.TXT` below API 3.0.0).

### 3.5 Memory limits per app type
Limits are **per device and per app type**, published in each device's `.xml` in the SDK and shown in the simulator's status bar; the simulator's **File → View Memory** shows peak usage. Representative figures from Garmin's own developer blog:

| Context | Example limit |
|---|---|
| fēnix 5 watch face | 92 kB |
| fēnix 5 data field | 28 kB |
| **Glance mode** | **32 kB on most devices** |
| Background service | much smaller than the foreground pool; services can be killed at any time to free foreground memory |

Persisted data limits (separate from RAM):
- `Application.Storage` (API 2.4.0+): **8 kB per key and per value, 128 kB total per app**
- Legacy Object Store (`AppBase.getProperty/setProperty`, API 1.0.0): held in RAM until app close (~6 kB practical) — avoid
- `Application.Properties` (API 2.4.0+): user settings; keys must be predeclared in resource XML or you get `InvalidKeyException`; shares the 128 kB budget
- Only `Number, Float, Long, Double, Char, String, Boolean, Array, Dictionary` are storable (no Symbols inside containers)

### 3.6 Optimizing memory
- Use `excludeAnnotations` in the jungle to strip code the target device can't use (see §4.4).
- Use `(:background)` / `(:glance)` so only the needed subset compiles into those scopes.
- Use resource `scope="background|glance|foreground"` (API 3.1.0+) so resources aren't loaded where unusable.
- Pre-compute and persist expensive values (sunrise/sunset, BMI, history arrays) instead of recomputing each launch.
- Load resources in `initialize`/`onLayout`, **never in `onUpdate`** — loading uses reference counting and is computationally expensive.
- Streamline copy-pasted code: compiled size directly eats the same budget as fonts and localized strings.
- Use `(:extendedCode)` (API 5.1.0+) to page functions into a separate 16 MB extended code space on supported devices — MRU paged, so it costs performance; keep hot code out of it.
- `(:optimizer(do_not_remove))` blocks constant substitution when you need a runtime lookup.

### 3.7 The graphics pool (API 4.0.0+)
Before 4.0.0 every runtime-loaded bitmap/font came out of the **application heap**. Since 4.0.0 there is a **separate graphics pool**:
- Runtime-loaded bitmaps and fonts go into the pool and return a `Graphics.ResourceReference`.
- The pool dynamically caches, unloads and reloads based on available memory.
- Drawing primitives accept a `ResourceReference` transparently — no code change needed.
- `ResourceReference.get()` returns the live object and **locks it in the pool** for as long as it's in scope.
- **Static resources reload automatically if purged. `BufferedBitmap`s do NOT** — you must re-render them, or lock them with `get()` (which risks exhausting the pool).
- Practical rule: use short-lived buffered bitmaps freely; lock only long-lived ones, and sparingly.

Compatibility factory:
```monkeyc
import Toybox.Graphics;
function bufferedBitmapFactory(options as {
    :width as Number, :height as Number,
    :palette as Array<ColorType>, :colorDepth as Number,
    :bitmapResource as WatchUi.BitmapResource
}) as BufferedBitmapReference or BufferedBitmap {
    if (Graphics has :createBufferedBitmap) { return Graphics.createBufferedBitmap(options); }
    else { return new Graphics.BufferedBitmap(options); }
}
```

---

## 4. Project structure

### 4.1 Layout generated by "Monkey C: New Project"
```
myproject/
  bin/                 compiled PRG, .debug.xml, debug output
  resources/           layouts, drawables, fonts, strings, settings
  resources-<qualifier>/ per-device / per-family / per-language overrides
  source/              .mc files (App + View + Delegate)
  manifest.xml
  monkey.jungle        (default jungle filename looked up by VS Code)
  developer_key        (RSA 4096, kept outside the project ideally)
```

### 4.2 manifest.xml
`<iq:application>` attributes:
- `id` — 128-bit UUID (regenerate with **Monkey C: Regenerate UUID**)
- `entry` — the `Application.AppBase` subclass name
- `name` — resource id of a string; `launcherIcon` — resource id of a bitmap (auto-sized per product; don't reuse the launcher icon elsewhere, duplicate it)
- `type` — `watchface | datafield | widget | watch-app | audio-content-provider-app`
- `minApiLevel` — only major.minor matter; micro is ignored

```xml
<iq:products>
    <iq:product id="fenix5"/>
    <iq:product id="round-watch"/>
</iq:products>

<iq:permissions>
    <iq:uses-permission id="Sensor"/>
</iq:permissions>

<iq:barrels>
    <iq:depends name="IconLibrary" version="0.0.0"/>
</iq:barrels>
```

Data-field activity filter (API 5.2+):
```xml
<iq:activityFilter>
    <iq:activity sport="Toybox.Activity.SPORT_RUNNING"
                 subsport="Toybox.Activity.SUB_SPORT_GENERIC" />
</iq:activityFilter>
```

Permissions matrix (permission → modules, min API, allowed app types):
`Ant` (Toybox.Ant, 1.0.0 — not watchface) · `Background` (2.3.0, all) · `BluetoothLowEnergy` (3.1.0, not watchface) · `Communications` (Toybox.Communications + Toybox.Authentication, 1.0.0; on watchface/datafield Communications needs the Background permission, Authentication does not) · `ComplicationProvider` (4.1.0, app/audio) · `ComplicationSubscriber` (4.1.0, watchface) · `DataFieldAlert` (3.2.0, datafield only) · `Fit` (ActivityRecording + FitContributor, 1.0.0, app only — also makes the app appear in the Activities list) · `PersistedContent` (2.2.0) · `Positioning` (1.0.0; `enableLocationEvents()` only in widgets and apps) · `Sensor` (1.0.0) · `SensorHistory` (2.1.0) · `SensorLogging` (2.3.0) · `UserProfile` (1.0.0, all).

Barrel version specs: exact `version="1.2.3"`, at-least `">=1.2.3"`, pessimistic `"~>1.2.3"` (same major.minor, micro ≥), or omit the attribute for "whatever". Format `a.b.c.d` where `d` is optional alphanumeric/underscore.

### 4.3 Resources folders and qualifiers
Folder naming: `resources-<qualifier>`; more specific wins; the base `resources` folder is always applied first.

- **Device qualifier**: `resources-fenix5`
- **Family qualifiers**: screen shape first, then optional size — `resources-round`, `resources-round-218x218`, `resources-rectangle`, `resources-semiround`, `resources-semioctagon`. A size-only qualifier is invalid.
- **Localization qualifier**: ISO 639-2 code, always last — `resources-fre`, `resources-round-fre`, `resources-fenix5s-fre`.
- 30+ supported languages: ara bul ces dan deu dut eng est fin fre hrv hun ind ita jpn kor lav lit nob pol por slo slv spa swe rus ron tha tur ukr vie zsm zhs zht.

Resource XML:
```xml
<resources xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:noNamespaceSchemaLocation="http://developer.garmin.com/downloads/connect-iq/resources.xsd">
    <bitmap id="bitmap_id" filename="path/for/image" />
    <font id="font_id" filename="path/to/fnt" />
    <string id="string_id">Hello World!</string>
</resources>
```

The **resource compiler** emits a Monkey C module `Rez` with `Lang.ResourceId` constants:
```monkeyc
image = Application.loadResource(Rez.Drawables.bitmap_id) as BitmapResource;
dc.drawBitmap(50, 50, image);
```
`WatchUi.loadResource()` (API 1.0.0) / `Application.loadResource()` (API 3.1.0).
Cross-references use `@Module.id`: `<menu-item id="item_1" label="@Strings.menu_item_1_label" />`

**Resource scopes** (API 3.1.0+): `scope="background|glance|foreground"` (default foreground). Background-scoped resources are visible everywhere; glance-scoped reach foreground too; foreground-scoped are isolated. Cuts runtime memory. `scope="settings"` on a string removes it from the runtime image entirely.

Bitmap attributes: `id`, `filename`, `dithering` (`floyd_steinberg`|`none`), `compress`, `automaticPalette`, `packingFormat` (`default`|`png`|`jpg`|`yuv`, API 4.0.0+), `scaleX`, `scaleY`, `scaleRelativeTo` (`screen`|`image`), `personality`; child `<palette disableTransparency="false">`. Supported inputs: JPG/JPEG, BMP/WBMP, GIF, SVG, PNG.
Packing tradeoffs: `default` (uncompressed, fast, alpha) · `png` (lossless+alpha, slow load) · `jpg` (best compression, lossy, no alpha) · `yuv` (lossy, keeps alpha).

Fonts: BMFont `.fnt` (TXT or PNG), attributes `id`, `filename`, `filter` (character whitelist), `antialias`, `scope`, `personality`. Bitmap fonts default to 1-bit non-antialiased to save RAM; set color with `Dc.setColor()`.
```xml
<font id="numeric_font" filename="big_font.fnt" filter="0123456789:"/>
```

JSON data resources (kept out of RAM until loaded):
```xml
<jsonData id="jsonArray">[1,2,3,4,5,6]</jsonData>
<jsonData id="jsonFile" filename="data.json"/>
```
```monkeyc
var array = Application.loadResource(Rez.JsonData.jsonArray);
```

Menus (`<menu2>`, `<menu-item>`, `<icon-menu-item>`, `<checkbox-menu>`, `<action-menu>`), animations (`<animation id="swirl" filename="swirl.mmm" />`, API 3.1.0+, built with Monkey Motion from `.y4m`/GIF).

### 4.4 Jungle files
`.jungle` at project root; `monkey.jungle` is the default the VS Code extension looks for. A built-in **default jungle** is always applied first (defines `base` = all `.mc` in the project + `resources/` at root), then your jungles override it. With multiple `-f` jungles, **the last one wins**.

Syntax: `qualifier[.property] = value`, values separated by `;`, dereference with `$(VAR)`, comments with `#`. Quote values with spaces.

Project qualifiers: `manifest` (`project.manifest = manifest.xml` — exactly one across all jungles), `optimization`, `typecheck`.
Device qualifier properties: `annotations`, `barrelPath`, `excludeAnnotations`, `lang`, `personality` (`.mss`), `resourcePath`, `sourcePath`.
Device prefixes: `base` (all), `round`, `semiround`, `rectangle`, `semioctagon`, `<product id>`, optionally suffixed `-<width>x<height>`.

```
base.sourcePath = source
round.resourcePath = $(base.resourcePath);resource-round
semiround.resourcePath = $(base.resourcePath);resource-semiround
rectangle.resourcePath = $(base.resourcePath);resource-rectangle
venu.sourcePath = $(base.sourcePath);source-venu
venu.resourcePath = $(base.resourcePath);resource-venu

fenix5.resourcePath = $(fenix5.resourcePath);fenix-resources
fenix5.lang.eng = $(fenix5.lang.eng);fenix-resources-eng
fenix5.lang.spa = $(fenix5.lang.spa);fenix-resources-spa
```
Path precedence is **left to right**; later paths can override earlier ones. Qualifiers resolve lazily after all jungles are processed; local variables resolve after the jungle that defines them. Languages set via `lang` are ignored unless also declared in the manifest.

**Build exclusions** — the main memory lever:
```
base.excludeAnnotations = experimental
fenix5.excludeAnnotations = boring
```
```monkeyc
(:boring)       const experimental = false;
(:experimental) const experimental = Toybox.Sensor has :AccelerometerData;

(:experimental) function myAlgorithm() { sharedLogic(); newHotnessLogic(); }
(:boring)       function myAlgorithm() { sharedLogic(); oldAndBoringLogic(); }
```

Barrels in a jungle:
```
base.barrelPath = barrels
base.barrelPath = barrels/IconLibrary.barrel
base.barrelPath = barrels/IconLibrary.barrel;barrels/GraphLibrary.barrel
base.GraphLibrary.annotations = bar
# depend on a barrel PROJECT directly (no re-export needed during development)
base.barrelPath = MyIconBarrel/MyIconBarrel.jungle
base.barrelPath = barrels/MathLibrary.barrel;[MyIconBarrel/roundIcons.jungle;MyIconBarrel/rectangleIcons.jungle]
```

### 4.5 Barrels (Monkey Barrels / shareable libraries)
- Create via **Monkey C: New Project** → project type *Monkey Barrel*. Cannot be named `Toybox`.
- A barrel is a module tree; annotate sub-modules so consumers can import only what they need. A module directly under the namespace **without** an annotation produces a compile warning.
```monkeyc
module FooBarrel {
    (:Bars)
    module Bars {
        var currentBars = 0;
        function getCurrentBars() { return currentBars; }
    }
}
```
- Barrel resources become a `Rez` sub-module of the barrel module; reference as `@IconLibrary.Drawables.myIcon` in XML, `IconLibrary.Rez.Drawables.myIcon` in code. **All files must live under the barrel project root** — external files can't be imported.
- Versioning: `Major.Minor.Micro.Qualifier`; qualifier is letters/digits/underscore.
- Export: **Monkey C: Export Project** → `.barrel` (the compiler runs a syntax check during packaging).
- Consume: **Monkey C: Configure Monkey Barrel** (updates both jungle and manifest), then:
```monkeyc
using Toybox.System;
using FooBarrel.Bars as Bars;   // `using` needed only for aliases

FooBarrel.BarsToo.fancyBars();
var globalBars = Bars.getCurrentBars();
var icon = UserInterface.loadResource(IconLibrary.Rez.Drawables.myIcon);
```
- Annotation selection in the consumer's jungle: `base.FooBarrel.annotations = Bars;BarsToo`
- CLI: `barrelbuild -o <output.barrel> -f <barrel.jungle>` and `barreltest -o <output.barrel> -f <barrel.jungle> -d <device_id>`.

### 4.6 App types
| Type | manifest `type` | Notes |
|---|---|---|
| Watch Face | `watchface` | Home screen. Heavily restricted APIs (no GPS/compass/sensors). Sleep mode: update once per minute. Awake: once per second, animations allowed. |
| Data Field | `datafield` | Plug-in to activities; must handle 1/2/3+ field layouts. `SimpleDataField` handles scaling for you. |
| Widget | `widget` | Mini-app; times out on inactivity; can't record activities. Base view can't take up/down input. Glance mode (3.1.0+) runs in reduced memory with **no input**. |
| Device App | `watch-app` | Full system access: activity recording, sensors, files. Needs deliberate launch; initial view should be a call to action. |
| Audio Content Provider | `audio-content-provider-app` | Plug-in to the media player; three contexts: playback config, sync, playback. |

Requesting a module your app type can't use → **Symbol Not Found**. (e.g. `Toybox.ActivityRecording` is app-only; `Toybox.Media` is audio-provider-only; `Toybox.Position`/`Toybox.Sensor` are unavailable to watch faces and data fields.)

### 4.7 App lifecycle
`initialize → onStart(state) → getInitialView()/getGlanceView()/getGoalView() → onLayout → onShow → onUpdate → onHide → onStop(state)`

```monkeyc
class SampleName extends Toybox.Application.AppBase {
    function initialize() { AppBase.initialize(); }
    function onStart(state) { }
    function onStop(state) { }
    function getInitialView() { return [new SampleNameView(), new SampleNameDelegate()]; }
}
```
- Do **not** push a view in `onStart()`.
- `Application.getApp()` gets the app object anywhere.
- Launch-source and suspend/resume detection:
```monkeyc
function onStart(state) {
    if ((state != null) && (state.get(:launchedFromGlance))) { /* glance list: has a timeout */ }
    if ((state != null) && (state.get(:resume))) { restoreState(); }
}
function onStop(state) {
    if ((state != null) && (state.get(:suspend))) { saveState(); }
}
```
- `onActive()` / `onInactive()` on devices with a task switcher. **Inactive state restrictions**: can't start/stop recording unless already recording; ANT channels close and must be reopened; high-frequency sensors drop to max 10 Hz; `Attention` (vibe/tone) is denied.
- `onAppInstall()` / `onAppUpdate()` (API 3.0.0+, need Background permission) are **not guaranteed to run** — never depend on them.
- Glances (API 3.1.0+): override `AppBase.getGlanceView()`. **API 4.0.0+ requires a glance view for an app/widget to appear in the glance list.** Two update modes: live UI update (keep under 1 Hz) and background UI update (min 30 s between updates, full lifecycle each time, rendering cached to filesystem).
- Background services: `AppBase.getServiceDelegate()` returns a `System.ServiceDelegate`; the event method (`onTemporalEvent()` etc.) fires; you must call `Background.exit(data)` promptly (services are killed after ~30 s). Temporal events fire at most every 5 minutes: `Background.registerForTemporalEvent(new Time.Duration(5 * 60))`. Everything reachable from the service must carry `(:background)` — the compiler catches violations at typecheck level `informative` or higher.

---

## 5. Build and tooling

### 5.1 SDK Manager
- Downloads: `connectiq-sdk-manager-windows.zip`, `connectiq-sdk-manager.dmg`, `connectiq-sdk-manager-linux.zip` (from developer.garmin.com/connect-iq/sdk/).
- Log in with a Garmin Connect account; two tabs: **SDKs** and **Devices**. Options for storing credentials, auto-updating SDKs, and auto-downloading new device profiles.
- Prereq: **Java Runtime Environment 11+**.
- The active SDK path is written to a config file; the CLI tools live in `<active sdk>/bin`.

### 5.2 VS Code Monkey C extension
Requires VS Code, JRE 11+, Connect IQ SDK 4.0.6+. Verify with **Monkey C: Verify Installation**.

Features: real-time errors/warnings for `.mc`, jungle, settings, `.mss` and resource XML (Problems tab); autocompletion with argument and type info; symbol search (`@symbol` in document, `#symbol` in workspace); hover type info; Go to Definition; code folding. **Needs typecheck level gradual or higher.** Real-time errors target the last device built for, or the first product in the manifest.

Commands:
| Command | Purpose |
|---|---|
| Monkey C: New Project | app or Monkey Barrel |
| Monkey C: Build Current Project | compile for a device |
| Monkey C: Build for Device | export wizard → side-loadable PRG |
| Monkey C: Clean Project | delete cached build artifacts |
| Monkey C: Export Project | produce `.iq` or `.barrel` |
| Monkey C: Edit Products / Permissions / Languages / Application / Annotations | manifest editors |
| Monkey C: Configure Barrel | add/remove barrels |
| Monkey C: Set Products by Connect IQ Version | bulk product selection |
| Monkey C: Regenerate UUID | new app id |
| Monkey C: Run Tests | run all Run No Evil tests |
| Monkey C: Launch Complication | run publisher + subscriber under the debugger |
| Monkey C: Launch Native Pairing | sensor native pairing mode |
| Monkey C: Open ERA Viewer / Monkey Graph / Monkey Motion / SDK Manager | SDK tools |
| Monkey C: View Documentation | API docs |

Run without debugging: **Ctrl+F5** / **Cmd+F5** (a `.mc` file must be the active editor). Command palette **Ctrl+Shift+P** / **Cmd+Shift+P**.

`launch.json` properties: `prg` (req), `prgDebugXml` (req), `stopAtLaunch`, `runTests`, `device` (or `${command:GetTargetDevice}` to pick per run), `settingsJson`, `tests` (string array), `runNativePairing`, `complicationPublisherFolder`, `complicationSubscriberFolder`.

Jungle file location is configurable at File → Preferences → Settings → Monkey C.

### 5.3 CLI
Add `<sdk>/bin` to `PATH` (`.bash_profile` / `.bashrc` on macOS/Linux; a config-file lookup on Windows).

- **`connectiq`** — launches the simulator. Must be running *before* `monkeydo`. The simulator only exposes APIs matching the target device's Connect IQ version.
- **`monkeyc`** — the compiler.
- **`monkeydo`** — loads a compiled PRG into the running simulator.
- **`barrelbuild`** / **`barreltest`** — barrels.
- **`monkeygraph`** — Monkey Graph (preview how FIT developer-data charts will render; takes an `.iq` file + a `.fit` file).
- **`mdd`** — command line debugger.

Typical flow:
```
connectiq                       # start the simulator
monkeyc -o bin/MyApp.prg -f monkey.jungle -d fenix5 -y developer_key
monkeydo bin/MyApp.prg fenix5
monkeyc -o myApp.prg myApp.mc -d fenix5 -f monkey.jungle;monkey2.jungle
```

Developer key: RSA **4096-bit** private key, generated via the VS Code command palette or OpenSSL (PEM then DER); pass the `.der` with `-y`. **Losing the key means you can never update your published app.**

### 5.4 monkeyc flags
| Flag | Long | Meaning |
|---|---|---|
| `-f` | `--jungles` | colon/semicolon-separated jungle file list (**required** in modern builds) |
| `-o` | `--output` | output file |
| `-y` | `--private-key` | developer key path |
| `-d` | `--device` | target device id |
| `-e` | `--package-app` | produce a store-submittable `.iq` |
| `-r` | `--release` | strip debug info from the PRG |
| `-g` | `--debug` | debug output |
| `-w` | `--warn` | enable compiler warnings (**off by default**) |
| `-k` | `--profile` | embed profiler data |
| `-t` | `--unit-test` | include unit tests |
| `-O` | `--optimization` | optimization level |
| `-l` | `--typecheck` | 0 off / 1 gradual / 2 informative / 3 strict |
| `-h` / `-v` | `--help` / `--version` | |
| | `--debug-log-level` | 0–3 (Errors → Verbose Debug); higher levels leak project detail |
| | `--debug-log-output` | log file path |
| | `--debug-log-device` | restrict logs to one device |
| | `--disable-api-has-check-removal` | keep `has` checks the optimizer would fold |
| | `--disable-v2-opcodes` | |

**Optimization levels (`-O`)**: `0` none · `1` basic (**default for debug**) · `2` fast optimizations (**default for release**) · `3` slow optimizations · `p` performance · `z` code space. Combinable: `-O 2pz`.

**Deprecated**: `-z` (resource paths), `-x` (exclusions), `-m` (manifest), and bare source files on the command line. Mixing `-f` with any of them is a compiler error; using them alone produces a warning.

`monkeydo` options: executable path, device id, `-n` (sensor native pairing), `-t` (unit test, optional test name).

### 5.5 Simulator
- Started by `connectiq` or automatically by VS Code Run.
- **Only exposes the API level of the simulated device** — an API your device doesn't have won't appear.
- **Debugging is only supported in the simulator, never on hardware.**
- **File → View Memory** shows peak memory; the bottom status panel shows the device's limits.
- **File → View Profiler** — Start/Stop capture; **Profiler → Settings** sets an automatic sampling duration.
- Run No Evil unit tests run **only** in the simulator.
- Asserts fire automatically in the simulator and are stripped from release builds.

### 5.6 Debugging
Three levels:
1. `System.println()` — console in VS Code; on hardware it writes to `/GARMIN/APPS/LOGS/<APPNAME>.TXT`, **which you must create manually** (name must match the PRG: `MYAPP.PRG` → `MYAPP.TXT`).
2. **VS Code debugger** — Run → Start Debugging; click the gutter for breakpoints; Run and Debug panel shows Variables, Call Stack, and globals as the `$` variable **visible only in the top stack frame**.
3. **`mdd`** command line debugger (start the simulator first):
```
(mdd) file MyFace.prg MyFace.prg.debug.xml fenix6
(mdd) break \path\to\File.mc:1138
(mdd) run
(mdd) next | step | continue
(mdd) info frame
(mdd) print <expr>
```

Crash artifacts on device:
- App crash → `/GARMIN/APPS/LOGS/CIQ_LOG.YAML` (`CIQ_LOG.TXT` below API 3.0.0): error name, description, timestamp, device + SDK info, stack trace with file/line/function.
- Device reboot/freeze → `/GARMIN/ERR_LOG.txt` (firmware-level, usually not your bug).
- **Any log over 5 kB is rotated to `<LOGNAME>.BAK`**, ~10 kB total per log — grab logs promptly.
- **ERA** (Error Reporting Application) aggregates crashes from published apps: **Monkey C: Open ERA Viewer**.

### 5.7 Unit testing — Run No Evil
Simulator-only. Test methods must: carry `(:test)`, take a `Test.Logger` parameter, be `static` if inside a class/module, and return a Boolean.

```monkeyc
(:test)
function myUnitTest(logger as Logger) as Boolean {
  var x = 2 + 2;
  logger.debug("x = " + x);
  return (x == 4);
}
```
Logger levels: `debug()`, `warning()`, `error()`.

Asserts: `Test.assert()`, `Test.assertMessage()`, `Test.assertNotEqual()`, `Test.assertNotEqualMessage()` — run automatically on simulator launch, removed in release builds.

```monkeyc
import Toybox.Test;
function onShow() {
  var x = 1; var y = 1;
  Test.assertNotEqualMessage(x, y, "x and y are equal!");
}
```

Running: **Test Explorer** (test-tube icon) groups tests by module/class with per-test play buttons; results in the Test Results tab. Or CLI:
```
monkeyc ... --unit-test
monkeydo.bat path\to\projects\bin\MyApp.prg /t [testName]
```
Output:
```
Executing test myUnitTest…
DEBUG (14:16): x = 4
Pass
RESULTS: myUnitTest - Pass
Ran 1 test
PASSED (failures=0, errors=0)
```
Each test is independent; a failure doesn't stop the rest. Barrels: right-click the barrel project root → Run Tests, or use `barreltest`.

### 5.8 Profiler
Simulator: File → View Profiler → Start/Stop. Columns: Function, **Total Time (µs)** (including nested calls), **Actual Time (µs)** (excluding callees), **Average Time (µs)**, **Call Count**, **Call Stack**.
On device: compile with `-k`, use **Monkey C: Build for Device**, side-load and run, then pull `GARMIN\APPS\LOGS\<appname>.PRF` and Load it in the simulator profiler.
Watch for high call count × low average time — that pattern dominates on wearables.

### 5.9 Annotations reference
| Annotation | Effect |
|---|---|
| `(:background)` | include in the background process build |
| `(:glance)` | include in the glance build |
| `(:debug)` | **excluded from release builds** |
| `(:release)` | **excluded from debug builds** |
| `(:test)` | Run No Evil test; excluded from the app |
| `(:typecheck(...))` | steer the type checker (`disableBackgroundCheck`, `disableGlanceCheck`) |
| `(:initialized)` | promise the checker a member is initialized before use |
| `(:extendedCode)` | API 5.1.0+; move the function to a 16 MB paged extended code space (MRU paging, slower) |
| `(:optimizer(do_not_remove))` | block constant substitution; force a runtime lookup |
| `(:anyCustomName)` | arbitrary tag used with `excludeAnnotations` in jungles, and barrel sub-module selection |

Annotations are written into `bin/debug.xml` at build time.
```monkeyc
(:debug) class TestMethods
{
    (:test) static function testThisClass( x ) { }
}
```

---

## 6. Gotchas for a new Connect IQ developer

**Language**
1. **Parent `initialize()` is never called implicitly.** Call `Parent.initialize()` as your first line or you get an Initializer Error.
2. **Functions without a `return` return a garbage value** (the last value on the stack), not null. Always return explicitly.
3. `superclass.memberVariable` doesn't exist. Only `ParentClass.method()` works.
4. **Bitwise `&` has multiplication precedence, `|` and `^` have addition precedence.** Parenthesize.
5. `&&`/`||` return the operand value, not a Boolean. `0` is falsy, non-null is truthy.
6. **Loops and `if` require braces.** No single-statement bodies.
7. The switch-block variable scoping rule (§1.6) bites constantly — brace your case bodies.
8. `const` at function scope is a compile error; module/class level only. `const` arrays are still mutable element-wise.
9. **Max 10 arguments per method** — more is the fatal "Too Many Arguments".
10. Symbol lookup is a runtime hierarchy walk. Use `$.` for globals to skip it (and to disambiguate shadowed names).
11. Functions aren't first class — every callback is a `Lang.Method`.
12. No `String.format` instance method; use `Lang.format("$1$", [x])` or `number.format("%02d")`.
13. `instanceof`/`has` work on concrete classes and symbols only. **Monkey Types interfaces are invisible at runtime.**
14. `as` casts are erased at compile time — they change nothing at runtime.
15. Calling a function invalidates if-split narrowing of member variables. Copy nullable members into locals first.
16. **Compiler warnings are off by default** (`-w`). Turn them on.

**Memory**
17. **Reference counting, not tracing GC → circular references leak permanently.**
18. `Lang.Method` holds a **strong** reference to its owner. Timers, delegates and callbacks are the usual leak path — use `weak()`.
19. **Peak** memory is what kills you, not steady state. Watch face limits can be as low as ~28 kB (data fields) / ~92 kB (watch faces) on mid-range devices; glances get ~32 kB.
20. Never load resources inside `onUpdate()` — load in `initialize`/`onLayout`.
21. Pre-API-4.0 devices load all bitmaps/fonts into the app heap; API 4.0+ uses the graphics pool. **Purged `BufferedBitmap`s are not restored automatically** — re-render or lock with `get()`.
22. Modules cost runtime memory; don't create them gratuitously.
23. Long copy-pasted code inflates compiled size, eating the same budget as fonts and strings.
24. Storage: 8 kB per key/value, 128 kB total; no Symbols inside stored containers; `Properties` throws `InvalidKeyException` for keys not predeclared in resource XML.

**Build / platform**
25. Apps must declare products, permissions and languages in `manifest.xml` — jungle `lang` overrides are **silently ignored** if the language isn't in the manifest.
26. `minApiLevel` micro version is ignored; only major.minor gate device availability.
27. Using a module your app type can't access → **Symbol Not Found** at runtime, not compile time. Check §4.6.
28. The default jungle always applies first; with multiple `-f` jungles the **last** wins; jungle path precedence is left-to-right.
29. Only **one** `project.manifest` across all jungle files. Relative jungle paths resolve against the jungle's own directory; `default.jungle` paths resolve against the manifest's directory.
30. Family resource qualifiers must state shape before size (`resources-round-218x218`); size-only is invalid.
31. Barrel files must all live under the barrel project root; a barrel can't be named `Toybox`; un-annotated top-level barrel modules warn.
32. **Debugging only works in the simulator.** On-device you get `System.println` to a log file you created yourself, plus `CIQ_LOG.YAML` on crash — and logs rotate at 5 kB.
33. `connectiq` (simulator) must already be running before `monkeydo`.
34. Guard every newer API with `has` (`Graphics has :createBufferedBitmap`, `dc has :setAntiAlias`, `Toybox.Application has :Storage`) rather than assuming a device generation.
35. Guard the `Communications` permission on watch faces/data fields — it also needs `Background` there.
36. `onAppInstall()` / `onAppUpdate()` are best-effort; never rely on them.
37. Background services must call `Background.exit()` within ~30 s and only see `(:background)`-annotated code.
38. API 4.0.0+: an app/widget without a `getGlanceView()` **won't appear in the glance list**.
39. Watch faces: once-per-minute updates asleep, once-per-second awake; use `onPartialUpdate` (CIQ 2.3+) for seconds. Complex drawing can take ~700 ms and freezes navigation.
40. **Guard your developer key like a production secret** — losing it ends your ability to update the published app.

---

## Sources

### Monkey C
- https://developer.garmin.com/connect-iq/monkey-c/
- https://developer.garmin.com/connect-iq/monkey-c/functions/ → https://developer.garmin.com/connect-iq/articles/monkey-c/Functions.html
- https://developer.garmin.com/connect-iq/monkey-c/objects-and-memory/ → https://developer.garmin.com/connect-iq/articles/monkey-c/Objects_and_Memory.html
- https://developer.garmin.com/connect-iq/monkey-c/containers/ → https://developer.garmin.com/connect-iq/articles/monkey-c/Containers.html
- https://developer.garmin.com/connect-iq/monkey-c/monkey-types/ → https://developer.garmin.com/connect-iq/articles/monkey-c/Monkey_Types.html
- https://developer.garmin.com/connect-iq/monkey-c/exceptions-and-errors/ → https://developer.garmin.com/connect-iq/articles/monkey-c/Exceptions_and_Errors.html
- https://developer.garmin.com/connect-iq/monkey-c/annotations/ → https://developer.garmin.com/connect-iq/articles/monkey-c/Annotations.html
- https://developer.garmin.com/connect-iq/monkey-c/coding-conventions/ → https://developer.garmin.com/connect-iq/articles/monkey-c/Coding_Conventions.html
- https://developer.garmin.com/connect-iq/monkey-c/compiler-options/ → https://developer.garmin.com/connect-iq/articles/monkey-c/Compiler_Options.html
- https://developer.garmin.com/connect-iq/programmers-guide/monkey-c/
- https://developer.garmin.com/connect-iq/programmers-guide/

### Reference guides
- https://developer.garmin.com/connect-iq/reference-guides/
- https://developer.garmin.com/connect-iq/articles/reference-guides/Monkey_C_Reference.html
- https://developer.garmin.com/connect-iq/articles/reference-guides/Jungle_Reference.html
- https://developer.garmin.com/connect-iq/articles/reference-guides/Visual_Studio_Code_Extension.html
- https://developer.garmin.com/connect-iq/articles/reference-guides/Monkey_C_Command_Line_Setup.html
- https://developer.garmin.com/connect-iq/articles/reference-guides/Monkey_Graph_Reference.html

### Basics
- https://developer.garmin.com/connect-iq/connect-iq-basics/
- https://developer.garmin.com/connect-iq/articles/connect-iq-basics/Getting_Started.html
- https://developer.garmin.com/connect-iq/articles/connect-iq-basics/Your_First_App.html
- https://developer.garmin.com/connect-iq/articles/connect-iq-basics/App_Types.html

### Core topics
- https://developer.garmin.com/connect-iq/core-topics/
- https://developer.garmin.com/connect-iq/articles/core-topics/Manifest_and_Permissions.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Application_and_System_Modules.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Build_Configuration.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Resources.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Graphics.html
- https://developer.garmin.com/connect-iq/articles/core-topics/User_Interface.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Shareable_Libraries.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Unit_Testing.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Debugging.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Profiling.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Persisting_Data.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Backgrounding.html
- https://developer.garmin.com/connect-iq/articles/core-topics/Glances.html

### SDK, API docs, other
- https://developer.garmin.com/connect-iq/sdk/
- https://developer.garmin.com/connect-iq/compatible-devices/
- https://developer.garmin.com/connect-iq/device-reference/
- https://developer.garmin.com/connect-iq/api-docs/Toybox/Lang.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/Lang/String.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/Lang/Number.html
- https://www.garmin.com/en-US/blog/developer/improve-your-app-performance/ (source of the concrete memory-limit figures)

### Notes on gaps
- Per-device memory limit tables are **not published on the website**; they live in each device's `.xml` inside the SDK and are shown in the simulator status bar. The only public figures found are the Garmin blog's fēnix 5 examples (92 kB watch face, 28 kB data field) and the 32 kB glance limit from the Glances page.
- `https://developer.garmin.com/connect-iq/connect-iq-faq/` renders only an index of linked sub-questions; no substantive content was retrievable.
- The Monkey Graph tool is a **FIT developer-data chart previewer**, not a memory/call-graph analyzer, despite the name.
- Direct `curl` to developer.garmin.com is blocked by this environment's egress proxy; all content was retrieved through WebFetch against the static article paths.
