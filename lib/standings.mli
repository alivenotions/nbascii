(** Conference standings in ESPN playoff-seed order. *)
type entry = {
  seed : int;
  team : string;
  wins : string;
  losses : string;
  percentage : string;
  behind : string;
  streak : string;
}
type conference = { name : string; entries : entry list }
type t = { season : string; conferences : conference list }
val of_json : Yojson.Safe.t -> t
val of_string : string -> t
(** Malformed feeds raise [Failure]. *)
