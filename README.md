# A High-Performance, GADT-Based Binary Serialization Library

`tiny_bin` is a type-safe binary serialization and deserialization library written in OCaml. It uses Generalized Algebraic Data Types (GADTs) to dynamically represent type schemas while maintaining static compiler guarantees. The library is optimized for low-latency systems, featuring LEB128 integer compression (an implementation of Varints) and a mutable cursor pattern to avoid allocation overhead, allowing for zero-copy slicing for large buffers.

---

## Why OCaml?

### 1. Advanced Type Systems & Existential Types
Using GADTs, `tiny_bin` retains type witnesses (`'a typ`) at runtime, guaranteeing that deserialized outputs match their schemas without resorting to unsafe pointer casting (`Obj.magic`). 
The `Map` constructor leverages an existential type variable (`'b`) to decouple the physical layout of raw bytes on the wire from the clean domain-level types exposed to developers:
```ocaml
Map : 'b typ * ('b -> 'a) * ('a -> 'b) -> 'a typ
```

### 2. Micro-Memory Optimization
Managed languages often introduce silent allocation overhead. `tiny_bin` utilizes:
*   **Off-heap memory:** Direct byte manipulation using `Bigstringaf` to interface with system-level I/O.
*   **Variable-length integer compression:** Custom tail-recursive LEB128 encoders/decoders to compress metadata and integers on the fly.
*   **Mutable Cursor Pattern:** Standard tuple-returning reader signatures `('a * int)` replaced with in-place cursor updates (`cursor -> 'a`) to eliminate intermediate tuple allocations during sequential deserialization passes.

---

## Performance & GC Allocation Benchmark

To evaluate memory efficiency, the `Slice` mechanism (which points directly to sub-segments of a `Bigarray`) was benchmarked against standard `String` decoding (which allocates copies on the OCaml heap) by analyzing allocation and execution timing.

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

### 2. High-Precision Execution Time Benchmark (1,000,000 runs)
```text
Micro-Benchmark (1000000 runs)
String Copying:  0.0475 seconds (47.52 ns/run)
Slice: 0.0100 seconds (10.00 ns/run)
```
-   **Throughput Scale**
    - String Copying (47.52 ns/run): Decodes 21.0 million payloads per second on a single thread.
    - Slice (10.00 ns/run): Decodes 100.0 million payloads per second on a single thread.
-   **CPU Cycle Savings**
    Assuming a standard $3.5\text{ GHz}$ processor ($1\text{ ns}\approx3.5\text{ CPU cycles}$)
    - String Copying: Takes $\approx166\text{ CPU cycles}$ per run
    - Slice: Takes $\approx35\text{ CPU cycles}$ per run

Thus, the slice implementation saves roughly $131\text{ CPU cycles}$ per run yielding a $4.75\times$ speedup.

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
