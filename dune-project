(lang dune 3.24)

(name nbascii)

(generate_opam_files true)

(source
 (github alivenotions/nbascii))

(authors "Bhavdeep Dhanjal<bhavdeep@hey.com>")

(license MIT)

(package
 (name nbascii)
 (synopsis "quick nba score")
 (description "hopefully this will be a quick way to get nba scores")
 (depends
  (ocaml
   (>= 5.5.2))
  (dune
   (>= 3.24.2))
  (dream
   (>= 1.0.0))
  (dream-html
   (>= 4.0.0))
  (cohttp-lwt-unix
   (>= 6.3.0))
  (lwt_ppx
   (>= 6.1.0)))
 (tags
  ()))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/reference/dune-project/index.html
