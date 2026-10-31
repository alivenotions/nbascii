(** Today's NBA games, as published by NBA's live data feed. *)

type status =
  | Scheduled
  | Live
  | Final

type team = {
  tricode : string;  (** e.g. ["BOS"] *)
  city : string;
  name : string;
  wins : int;
  losses : int;
  score : int;
  periods : int list;  (** Points per period, including overtimes. *)
}

type game = {
  id : string;
  status : status;
  status_text : string;  (** e.g. ["7:30 pm ET"], ["Q3 5:21"], ["Final/OT"]. *)
  period : int;  (** Current or last period; [0] before tip-off. *)
  home : team;
  away : team;
}

type t = {
  date : string;  (** [YYYY-MM-DD], in US Eastern time. *)
  games : game list;
}

val of_json : Yojson.Safe.t -> t
(** Raises [Failure] if the JSON doesn't look like a scoreboard. *)

val of_string : string -> t
