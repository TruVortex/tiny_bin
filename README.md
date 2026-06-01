# tiny_bin

This project explores how Generalized Algebraic Data Types (GADTs) can be used to represent type schemas while preserving static type safety. It also demonstrates a few implementation techniques commonly used in low-allocation parsers, featuring LEB128 integer compression for non-negative integers (an implementation of Varints) and a mutable cursor pattern to avoid allocation overhead, allowing for zero-copy slicing for large buffers.

### Why This Exists

The primary goal of this project is educational; it is an exploration of:
- GADTs in OCaml
- typed serialization and deserialization
- allocation-aware parsing design
- existential encodings

---

## Schema Representation & Maps

Schemas are represented as a GADT:
```ocaml
type _ typ =
  | Int : int typ
  | String : string typ
  | Slice : slice typ
  | Pair : 'a typ * 'b typ -> ('a * 'b) typ
  | Map : 'b typ * ('b -> 'a) * ('a -> 'b) -> 'a typ
  | Nothing : unit typ
  | Just : 'a typ * 'b typ -> ('a, 'b) just typ
```
Because schemas carry type information at runtime, the compiler can guarantee that values produced by deserialization match the schema used to decode them without resorting to unsafe pointer casting (`Obj.magic`).
This gives the `Map` constructor the ability to leverage an existential type variable which allows a wire representation to be mapped to a more ergonomic domain type. That is, the intermediate wire type `'a` is hidden from users of the resulting schema,
allowing serialization to operate on one representation while applications work with another.

```ocaml
Map : 'a typ * ('a -> 'b) * ('b -> 'a) -> 'b typ
```

## Allocation-Aware Parsing
Deserialization uses a mutable cursor:
```ocaml
type cursor = {
  mutable off : int;
}
```
rather than returning `(value, next_offset)` pairs.
This avoids allocating offset tuples during sequential parsing and keeps the decoding path allocation-light.

---

## Performance & GC Allocation Benchmark

### Zero-Copy Slices

Strings are decoded by allocating a fresh OCaml string while slices instead return a view into the underlying Bigstringaf buffer:

```ocaml
type slice = {
  buf : Bigstringaf.t;
  off : int;
  len : int;
}
```

This avoids copying payload bytes and can significantly reduce allocation when working with large buffers.

To evaluate memory efficiency, the `Slice` mechanism (which points directly to sub-segments of a `Bigarray`) was benchmarked against standard `String` decoding (which allocates copies on the OCaml heap) by analyzing allocation and execution timing. The benchmarks demonstrate that avoiding string copies reduces allocation and improves throughput in this specific workload.

### 1. GC Allocation Benchmark Results (10,000 runs)
```text
GC Allocation Benchmark (10,000 runs):
String Copying: Allocated 1,040,096 bytes (~104 bytes/run)
Slice: Allocated 560,096 bytes (~56 bytes/run)
```

#### Why 56-Bytes?
In a 64-bit OCaml runtime, every block allocated on the minor heap requires a 1-word (8-byte) header. It is possible to account for every byte of the remaining 56 bytes allocated by the zero-copy pipeline:

1.  `read_varint` Tuple:
    The helper function returns `(len, next_off)` which is a 2-element tuple.
    $$\text{Size} = 1\text{-word header } (8\text{ bytes}) + 2\text{ fields } (16\text{ bytes}) = 24\text{ bytes}$$
2.  `slice` Record:
    Creating a view record `{ buf; off; len }` allocates a 3-field object.
    $$\text{Size} = 1\text{-word header } (8\text{ bytes}) + 3\text{ fields } (24\text{ bytes}) = 32\text{ bytes}$$
*(The additional 96 bytes is a fixed compiler constant representing the stack frame overhead of executing the loop and the `Gc` measurement harness).*

### 2. Execution Time Benchmark (1,000,000 runs)
```text
Micro-Benchmark (1000000 runs)
String Copying:  0.0475 seconds (47.52 ns/run)
Slice: 0.0100 seconds (10.00 ns/run)
```

---

## Usage Examples

The GADT design of `tiny_bin` allows one to declare complex schemas and seamlessly map them to clean domain types.

### Example 1: Basic Primitives and Pairs
A basic schema representing an ID paired with a username.

```ocaml
open Tiny_bin

(* Schema representing: (int * string) *)
let schema : (int * string) typ = Pair (Int, String)

let test_basic () =
  let sample = (42, "developer") in
  let buf_len = size schema sample in
  let buf = Bigstringaf.create buf_len in
  
  (* Serialize *)
  let _ = write schema sample buf 0 in
  
  (* Deserialize *)
  let cursor = { off = 0 } in
  let decoded = read schema buf cursor in
  Printf.printf "Decoded ID: %d, Role: %s\n" (fst decoded) (snd decoded)
```

---

### Example 2: Isomorphic Mapping (`map` for Records)
Usually, tuples are tedious to work with inside an application. One can use the `map` combinator to bind our schema to a clean, user-defined record type.

```ocaml
open Tiny_bin

(* Domain record *)
type coordinates = {
  latitude  : int;
  longitude : int;
}

(* Schema mapping a Pair (Int, Int) -> coordinates *)
let coordinates_schema : coordinates typ =
  let wire_schema = Pair (Int, Int) in
  
  (* Map tuple from wire format to record *)
  let to_domain (lat, lon) = { latitude = lat; longitude = lon } in
  
  (* Map record back to tuple for wire serialization *)
  let to_wire { latitude; longitude } = (latitude, longitude) in
  
  map wire_schema to_domain to_wire

let test_record () =
  let location = { latitude = 407128; longitude = -740060 } in
  let buf_len = size coordinates_schema location in
  let buf = Bigstringaf.create buf_len in
  
  let _ = write coordinates_schema location buf 0 in
  
  let cursor = { off = 0 } in
  let decoded = read coordinates_schema buf cursor in
  Printf.printf "Lat: %d, Lon: %d\n" decoded.latitude decoded.longitude
```

---

### Example 3: Handling Options (`maybe`)
Optional variables (like `string option`) are serialized using a tag byte `0` for `None` and `1` for `Some`. There exists `maybe` inside the library using the algebraic elements `Just` (binary sum) and `Nothing` (empty unit representation).

```ocaml
open Tiny_bin

type config = {
  port : int;
  password : string option; (* Optional field *)
}

let config_schema : config typ =
  (* wire schema: Int *** maybe String *)
  let wire_schema = Pair (Int, maybe String) in
  
  let to_domain (port, password) = { port; password } in
  let to_wire { port; password } = (port, password) in
  
  map wire_schema to_domain to_wire

let run_config sample =
  let buf_len = size config_schema sample in
  let buf = Bigstringaf.create buf_len in
  let _ = write config_schema sample buf 0 in
  
  let cursor = { off = 0 } in
  let decoded = read config_schema buf cursor in
  Printf.printf "Port: %d, Password Set: %b\n" 
    decoded.port 
    (Option.is_some decoded.password)
```
