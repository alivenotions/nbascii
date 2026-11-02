(** Compact ASCII with semantic styling, shared by plain text and the browser. *)

type tone = Plain | Heading | Label | Muted | Positive | Negative | Live | Value
type span = { text : string; tone : tone }
type document = span list list

val to_text : document -> string
val game_document : Scoreboard.game -> document
val scoreboard_document : Scoreboard.t -> document
val standings_document : Standings.t -> document
val leaders_document : Leaders.t -> document

val game : Scoreboard.game -> string list
(** One compact game, with aligned quarter and total columns. *)

val scoreboard : Scoreboard.t -> string
(** Games separated by a blank line, under a dated heading. *)

val standings : Standings.t -> string
(** Conference standings, with wins, losses, percentage, games back, and streak. *)
val leaders : Leaders.t -> string
(** Season points, rebounds, and assists per-game leaders. *)
