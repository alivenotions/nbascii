(** Calendar arithmetic on ESPN scoreboard days, independent of local timezone. *)
val previous : string -> string
(** Previous calendar day. Handles leap years; invalid dates raise [Invalid_argument]. *)
val espn_query : string -> string
(** Convert [YYYY-MM-DD] to ESPN's [YYYYMMDD] query format. *)
