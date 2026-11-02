(** Today's NBA games, parsed from ESPN's scoreboard feed. *)

type status =
  | Scheduled
  | Live
  | Final

type team = {
  tricode : string;  (** NBA abbreviation, e.g. ["BOS"] or ["GSW"]. *)
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
  status_text : string;  (** ESPN's short detail, e.g. ["5:21 - 3rd"] or ["Final/OT"]. *)
  period : int;  (** Current or last period; [0] before tip-off. *)
  home : team;
  away : team;
}

type t = {
  date : string;  (** ESPN's scoreboard day, [YYYY-MM-DD]. *)
  games : game list;
}

val finished : t -> bool
(** Every game is over, including postponed or cancelled ones, which ESPN
    also reports as final. True for a day without games. *)

val of_json : ?date:string -> Yojson.Safe.t -> t
(** Raises [Failure] if the JSON doesn't look like a scoreboard. *)

val of_string : ?date:string -> string -> t
(** Dated ESPN responses omit [day]; pass the requested [date] for those. *)
