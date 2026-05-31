open Tiny_bin

type payload = {
  data_str : string;
  data_slice : slice;
}

let payload_schema = Pair (String, Slice)

let measure_allocations f =
  Gc.full_major ();
  let before = Gc.allocated_bytes () in
  let result = f () in
  let after = Gc.allocated_bytes () in
  (result, after -. before)

let () =
  let raw_data = "This is a moderately large string designed to make copies visible" in
  let source_bigstring = Bigstringaf.of_string ~off:0 ~len:(String.length raw_data) raw_data in
  
  let sample_slice = { buf = source_bigstring; off = 0; len = Bigstringaf.length source_bigstring } in
  let sample = (raw_data, sample_slice) in
  
  let buf_len = size payload_schema sample in
  let buf = Bigstringaf.create buf_len in
  let _ = write payload_schema sample buf 0 in

  (* String Copying - 10,000 runs *)
  let string_schema = String in
  let cursor = { off = 0 } in
  let _, string_bytes = measure_allocations (fun () ->
    for _ = 1 to 10000 do
      cursor.off <- 0;
      ignore (read string_schema buf cursor)
    done
  ) in

  (* Slice - 10,000 runs *)
  let slice_schema = Slice in
  let _, slice_bytes = measure_allocations (fun () ->
    for _ = 1 to 10000 do
      cursor.off <- 0;
      ignore (read slice_schema buf cursor)
    done
  ) in

  Printf.printf "GC Allocation Benchmark (10,000 runs):\n";
  Printf.printf "String Copying: Allocated %.0f bytes\n" string_bytes;
  Printf.printf "Slice: Allocated %.0f bytes\n" slice_bytes