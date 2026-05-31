type slice = { buf : Bigstringaf.t; off : int; len : int }
type ('a, 'b) just = Left of 'a | Right of 'b
type cursor = { mutable off : int }

type _ typ =
  | Int : int typ
  | String : string typ
  | Slice : slice typ
  | Pair : 'a typ * 'b typ -> ('a * 'b) typ
  | Map : 'b typ * ('b -> 'a) * ('a -> 'b) -> 'a typ
  | Nothing : unit typ
  | Just : 'a typ * 'b typ -> ('a, 'b) just typ

let size_varint n =
  let rec loop acc n =
    if n < 0 then 10 else if n < 128 then acc + 1 else loop (acc + 1) (n lsr 7)
  in
  loop 0 n

let rec write_varint =
 fun buf off n ->
  if n < 128 then begin
    Bigstringaf.set buf off (Char.unsafe_chr n);
    off + 1
  end
  else begin
    let byte = n land 0x7f lor 0x80 in
    Bigstringaf.set buf off (Char.unsafe_chr byte);
    write_varint buf (off + 1) (n lsr 7)
  end

let rec read_varint_helper buf shift acc curr_off =
  let byte = Char.code (Bigstringaf.get buf curr_off) in
  let data = byte land 0x7f in
  let acc' = acc lor (data lsl shift) in
  if byte land 0x80 = 0 then (acc', curr_off + 1)
  else read_varint_helper buf (shift + 7) acc' (curr_off + 1)

let read_varint buf off = read_varint_helper buf 0 0 off

let rec size : type a. a typ -> a -> int =
 fun t value ->
  match t with
  | Int -> size_varint value
  | String ->
      let len = String.length value in
      size_varint len + len
  | Slice -> size_varint value.len + value.len
  | Pair (ta, tb) ->
      let va, vb = value in
      size ta va + size tb vb
  | Map (inner, _, to_wire) -> size inner (to_wire value)
  | Nothing -> 0
  | Just (ta, tb) ->
      begin match value with
      | Left va -> 1 + size ta va
      | Right vb -> 1 + size tb vb
      end

let rec write : type a. a typ -> a -> Bigstringaf.t -> int -> int =
 fun t value buf off ->
  match t with
  | Int -> write_varint buf off value
  | String ->
      let len = String.length value in
      let off' = write_varint buf off len in
      Bigstringaf.blit_from_string value ~src_off:0 buf ~dst_off:off' ~len;
      off' + len
  | Slice ->
      let off' = write_varint buf off value.len in
      Bigstringaf.blit value.buf ~src_off:value.off buf ~dst_off:off'
        ~len:value.len;
      off' + value.len
  | Pair (ta, tb) ->
      let va, vb = value in
      let off' = write ta va buf off in
      write tb vb buf off'
  | Map (inner, _, to_wire) -> write inner (to_wire value) buf off
  | Nothing -> off
  | Just (ta, tb) ->
      begin match value with
      | Left va ->
          Bigstringaf.set buf off (Char.chr 0);
          write ta va buf (off + 1)
      | Right vb ->
          Bigstringaf.set buf off (Char.chr 1);
          write tb vb buf (off + 1)
      end

let rec read : type a. a typ -> Bigstringaf.t -> cursor -> a =
 fun t buf cursor ->
  match t with
  | Int ->
      let value, off' = read_varint buf cursor.off in
      cursor.off <- off';
      value
  | String ->
      let len, off' = read_varint buf cursor.off in
      let value = Bigstringaf.substring buf ~off:off' ~len in
      cursor.off <- off' + len;
      value
  | Slice ->
      let len, off' = read_varint buf cursor.off in
      let value = { buf; off = off'; len } in
      cursor.off <- off' + len;
      value
  | Pair (ta, tb) ->
      let va = read ta buf cursor in
      let vb = read tb buf cursor in
      (va, vb)
  | Map (inner, to_domain, _) ->
      let wire_val = read inner buf cursor in
      to_domain wire_val
  | Nothing -> ()
  | Just (ta, tb) ->
      let tag = Char.code (Bigstringaf.get buf cursor.off) in
      cursor.off <- cursor.off + 1;
      if tag = 0 then Left (read ta buf cursor)
      else if tag = 1 then Right (read tb buf cursor)
      else failwith "Invalid tag for Maybe"

let map inner to_domain to_wire = Map (inner, to_domain, to_wire)
let nothing = Nothing
let just ta tb = Just (ta, tb)

let maybe : 'a typ -> 'a option typ =
 fun inner ->
  let to_domain = function Left () -> None | Right v -> Some v in
  let to_wire = function None -> Left () | Some v -> Right v in
  map (Just (Nothing, inner)) to_domain to_wire
