(** Shared helpers for ESPN feed adapters. Missing required fields raise [Failure]. *)
val field : string -> Yojson.Safe.t -> Yojson.Safe.t
val string : string -> Yojson.Safe.t -> string
val list : string -> Yojson.Safe.t -> Yojson.Safe.t list
val number : string -> Yojson.Safe.t -> float
val parse : (Yojson.Safe.t -> 'a) -> string -> 'a
val tricode : string -> string
