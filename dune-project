(lang dune 3.17)

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
    (>= 5.2.1))
  (dream-html
    (>= 3.3.1))
  dream
  cohttp-lwt-unix)
 (tags
  ()))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/reference/dune-project/index.html
