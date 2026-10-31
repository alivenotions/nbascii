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
  (eio
   (>= 1.6))
  (eio_main
   (>= 1.6))
  (cohttp-eio
   (>= 6.3.0))
  (http
   (>= 6.3.0))
  (uri
   (>= 4.4.0))
  (magic-mime
   (>= 1.3.1))
  (logs
   (>= 0.10.0))
  (pure-html
   (>= 4.0.0))
  (tls-eio
   (>= 2.1.4))
  (ca-certs
   (>= 1.0.3))
  (mirage-crypto-rng
   (>= 2.4.1))
  (domain-name
   (>= 0.4.0))
  (yojson
   (>= 3.0.0)))
 (tags
  ()))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/reference/dune-project/index.html
