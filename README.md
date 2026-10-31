# nbascii

Quick NBA scores, in ASCII. Written in direct-style OCaml 5 on [Eio](https://github.com/ocaml-multicore/eio).

## Layout

- `bin/` – the web app
- `lib/` – fetching and parsing scores (`Nba_api`, `Scoreboard`), the ASCII
  boxes (`Render`), and a small refresh cache (`Cache`)
- `dream_eio/` – a small Dream-style web framework on Eio and cohttp-eio
  (router, `:param` and `**` routes, scopes, middleware, logger, static files)
- `static/` – CSS and other assets

## Running

```sh
opam install . --deps-only --with-test
dune exec nbascii    # http://localhost:8080
dune test
```

Scores come from NBA's public live data feed
(`cdn.nba.com/.../todaysScoreboard_00.json`), cached for 20 seconds. It only
covers today's games, and it's undocumented, so it can change without notice.
