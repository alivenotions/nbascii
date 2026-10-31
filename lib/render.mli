(** Plain-text rendering of a scoreboard. *)

val game : Scoreboard.game -> string list
(** One game as a box of equal-width lines. *)

val scoreboard : Scoreboard.t -> string
(** Every game, one box after another, under a dated heading. *)
