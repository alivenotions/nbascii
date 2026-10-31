(** A value that is refreshed at most once per [ttl] seconds. *)

type 'a t

val create : clock:_ Eio.Time.clock -> ttl:float -> (unit -> 'a) -> 'a t
(** [create ~clock ~ttl fetch] calls [fetch] lazily, on the first {!get}. *)

val get : 'a t -> 'a
(** The cached value, refetched if older than [ttl]. Concurrent callers
    share a single fetch. If a refetch fails but an older value exists, the
    older value is returned and the error logged; otherwise the error is
    re-raised. *)
