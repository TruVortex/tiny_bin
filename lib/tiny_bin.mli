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

val size_varint : int -> int
(** [size_varint n] returns the number of bytes required to represent the
    integer [n] as a variable-length quantity (LEB128). *)

val write_varint : Bigstringaf.t -> int -> int -> int
(** [write_varint buf off n] encodes [n] as a varint and writes it to [buf]
    starting at [off], returning the updated offset. *)

val read_varint : Bigstringaf.t -> int -> int * int
(** [read_varint buf off] reads a varint from [buf] starting at [off], returning
    the decoded integer and the updated offset. *)

val size : 'a typ -> 'a -> int
(** [size schema value] returns the exact size in bytes required to serialize
    [value] according to [schema]. *)

val write : 'a typ -> 'a -> Bigstringaf.t -> int -> int
(** [write schema value buf off] serializes [value] into [buf] starting at
    [off], returning the updated offset. *)

val read : 'a typ -> Bigstringaf.t -> cursor -> 'a
(** [read schema buf off] deserializes a value from [buf] starting at [off],
    returning the value and the new offset. *)

val map : 'a typ -> ('a -> 'b) -> ('b -> 'a) -> 'b typ
(** [map inner to_domain to_wire] maps an underlying schema [inner] to and from
    a custom domain representation. *)

val nothing : unit typ
(** [nothing] is a zero-byte schema representing the OCaml [unit] type. It takes
    up no space on the wire. *)

val just : 'a typ -> 'b typ -> ('a, 'b) just typ
(** [just left_schema right_schema] constructs a binary choice (sum type)
    schema. On the wire, it is encoded as a single tag byte ([0] for the [Left]
    branch, [1] for the [Right] branch) followed by the serialized payload of
    that branch. *)

val maybe : 'a typ -> 'a option typ
(** [maybe inner_schema] constructs an optional schema, mapping OCaml's native
    ['a option] type to an algebraic representation composed of [nothing] and
    [inner_schema]. *)
