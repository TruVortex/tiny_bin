(lang dune 3.23)

(name tiny_bin)

(generate_opam_files true)

(source (github TruVortex/tiny_bin))
(authors "Henry Bao")
(maintainers "Henry Bao")

(package
 (name tiny_bin)
 (synopsis "GADT-based binary serialization library for OCaml")
 (description "A small, educational serialization library exploring GADTs, existential encodings, typed schemas, allocation-aware parsing, mutable cursors, and zero-copy slices.")
 (depends ocaml bigstringaf))
