# nbascii

Quick NBA scores, in ASCII. Written in direct-style OCaml 5 on [Eio](https://github.com/ocaml-multicore/eio).

## Layout

- `bin/` – the web app
- `lib/` – app logic (scores, rendering)
- `dream_eio/` – a small Dream-style web framework on Eio and cohttp-eio
  (router, `:param` and `**` routes, scopes, middleware, logger, static files)
- `static/` – CSS and other assets

## Running

```sh
opam install . --deps-only --with-test
dune exec nbascii    # http://localhost:8080
dune test
```
