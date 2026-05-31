open Tiny_bin

let time_it f =
  let start = Unix.gettimeofday () in
  let () = f () in
  let stop = Unix.gettimeofday () in
  stop -. start

let () =
  let raw_data =
    "This is a moderately large string designed to make copies visible"
  in
  let source_bigstring =
    Bigstringaf.of_string ~off:0 ~len:(String.length raw_data) raw_data
  in

  let sample_slice =
    {
      buf = source_bigstring;
      off = 0;
      len = Bigstringaf.length source_bigstring;
    }
  in
  let sample = (raw_data, sample_slice) in

  let buf_len = size (Pair (String, Slice)) sample in
  let buf = Bigstringaf.create buf_len in
  let _ = write (Pair (String, Slice)) sample buf 0 in

  let cursor = { off = 0 } in
  let runs = 1_000_000 in

  Printf.printf "Micro-Benchmark (%d runs):\n" runs;

  (* String Copying *)
  let string_time =
    time_it (fun () ->
        for _ = 1 to runs do
          cursor.off <- 0;
          ignore (read String buf cursor)
        done)
  in

  (* Slice *)
  let slice_time =
    time_it (fun () ->
        for _ = 1 to runs do
          cursor.off <- 0;
          ignore (read Slice buf cursor)
        done)
  in

  Printf.printf "String Copying:  %.4f seconds (%.2f ns/run)\n" string_time
    (string_time /. float_of_int runs *. 1e9);
  Printf.printf "Slice: %.4f seconds (%.2f ns/run)\n" slice_time
    (slice_time /. float_of_int runs *. 1e9);
  Printf.printf "Speedup: %.2fx\n" (string_time /. slice_time)
