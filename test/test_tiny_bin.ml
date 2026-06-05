open Tiny_bin

type point = { x : int; y : int }

let assert_round_trip =
 fun schema value eq label ->
  let expected_size = size schema value in
  let buf = Bigstringaf.create expected_size in
  let write_offset = write schema value buf 0 in
  if write_offset <> expected_size then
    failwith
      (Printf.sprintf
         "[%s] Write Mismatch: size calculated %d, but wrote %d bytes" label
         expected_size write_offset);
  let cursor = { off = 0 } in
  let decoded = read schema buf cursor in
  if cursor.off <> expected_size then
    failwith
      (Printf.sprintf
         "[%s] Read Mismatch: size calculated %d, but read ended at offset %d"
         label expected_size cursor.off);
  if eq value decoded then ()
  else
    failwith
      (Printf.sprintf
         "[%s] Value mismatch between original and decoded structure!" label)

let string_of_slice s = Bigstringaf.substring s.buf ~off:s.off ~len:s.len

let () =
  Printf.printf "Running Serialization Tests:\n";

  assert_round_trip Int 0 ( = ) "Int (0)";
  assert_round_trip Int 42 ( = ) "Int (42)";
  assert_round_trip Int 150 ( = ) "Int (150)";
  assert_round_trip Int (-15) ( = ) "Int (-15)";
  assert_round_trip Int 123456789 ( = ) "Int (123456789)";

  assert_round_trip String "hello" String.equal "String (hello)";
  assert_round_trip String "" String.equal "Empty String";

  assert_round_trip
    (Pair (Int, String))
    (100, "alice") ( = ) "Pair (Int, String)";

  let raw = "off-heap raw payload bytes" in
  let origin_buf = Bigstringaf.of_string ~off:0 ~len:(String.length raw) raw in
  let sample_slice =
    { buf = origin_buf; off = 0; len = Bigstringaf.length origin_buf }
  in
  let eq_slice s1 s2 =
    s1.len = s2.len && String.equal (string_of_slice s1) (string_of_slice s2)
  in
  assert_round_trip Slice sample_slice eq_slice "Zero-Copy Slice";

  let point_schema =
    let to_domain (x, y) = { x; y } in
    let to_wire { x; y } = (x, y) in
    map (Pair (Int, Int)) to_domain to_wire
  in
  let eq_point p1 p2 = p1.x = p2.x && p1.y = p2.y in
  assert_round_trip point_schema { x = 10; y = -20 } eq_point
    "Mapped Point Record";

  let maybe_int_schema = maybe Int in
  assert_round_trip maybe_int_schema (Some 42) ( = ) "Maybe (Some 42)";
  assert_round_trip maybe_int_schema None ( = ) "Maybe (None)";

  Printf.printf "Tests completed successfully!\n"
