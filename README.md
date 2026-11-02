# nbascii

Quick NBA scores, in ASCII. Written in direct-style OCaml 5 on [Eio](https://github.com/ocaml-multicore/eio).

## Layout

- `bin/` – the web app
- `lib/` – fetching and parsing scores (`Espn_api`, `Scoreboard`), the ASCII
  boxes (`Render`), and a small refresh cache (`Cache`)
- `dream_eio/` – a small Dream-style web framework on Eio and cohttp-eio
  (router, `:param` and `**` routes, scopes, middleware, logger, static files)
- `static/` – CSS and other assets

## Running

```sh
opam install . --deps-only --with-test
opam exec -- dune exec nbascii    # http://localhost:8080
opam exec -- dune test
```

`nbascii.opam` is generated from `dune-project`. After changing dependencies,
run `dune build @opam && dune promote` and commit the result.

## Pages

All pages keep the ASCII layout, with navigation links at the top:

The layout uses compact aligned columns instead of a box around every game.
Blue headings, green winners/winning streaks, muted red losing streaks, and
amber live-game labels provide visual cues. Text labels (`W`/`L`, `LIVE`) and
the final winner marker (`<`) remain readable without color. Every text color
has at least 4.5:1 contrast against the dark background.

| Path | Content | Cache |
| --- | --- | --- |
| `/` | Today's scheduled, live, and final games | 20 seconds |
| `/yesterday` | Previous scoreboard day's games | 20 seconds |
| `/standings` | East/West standings: wins, losses, win percentage, games back, streak | 5 minutes |
| `/stats` | Top 10 season leaders in points, rebounds, and assists per game | 5 minutes |

Yesterday is the calendar day before ESPN's current scoreboard day, not the
machine's local date. Month/year boundaries and leap years are handled. Its
first request also loads today's scoreboard to determine that day.

## Data sources

The app uses ESPN's public endpoints; no API key is needed:

- Scores: `https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard`
- Dated scores: the same endpoint with `?dates=YYYYMMDD`
- Standings: `https://site.api.espn.com/apis/v2/sports/basketball/nba/standings`
- Leaders: `https://site.api.espn.com/apis/site/v3/sports/basketball/nba/leaders`

These endpoints are undocumented and have no stability guarantee. Each page
has its own cache. If a refresh fails, it serves its last successful data;
without cached data, it returns 503. Standings follow ESPN's conference seeds;
leaders use ESPN's rankings and season labels.

Quick checks (responses are HTML, not JSON):

```sh
curl -i http://localhost:8080/
curl -i http://localhost:8080/yesterday
curl -i http://localhost:8080/standings
curl -i http://localhost:8080/stats
```
