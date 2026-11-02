(** Season per-game leaders, in ESPN's ranked order (including ties). *)
type player = { name : string; team : string; value : string }
type category = { name : string; abbreviation : string; players : player list }
type t = { season : string; categories : category list }
val of_json : Yojson.Safe.t -> t
val of_string : string -> t
(** Malformed feeds raise [Failure]. *)
