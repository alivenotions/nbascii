(** A value fetched on demand and refreshed in the background.

    Once a value has loaded, an expired value is returned straight away
    while a background fiber fetches a new one. Readers only wait on the
    first load, or briefly when a value is older than [max_age] (e.g. after
    nobody has asked for it in a while). Concurrent readers share a single
    fetch, and a failed fetch isn't retried for [retry_after] seconds.

    State is not protected by a lock, so a cache must only be used from the
    Eio domain that created it. *)

type 'a t

val create :
  sw:Eio.Switch.t ->
  clock:_ Eio.Time.Mono.t ->
  ttl:float ->
  ?max_age:float ->
  ?max_wait:float ->
  ?retry_after:float ->
  ?final:('a -> bool) ->
  (unit -> 'a) ->
  'a t
(** [create ~sw ~clock ~ttl fetch] calls [fetch] lazily, on the first read.
    Background fetches run in fibers attached to [sw].

    @param ttl Seconds before a value is refreshed.
    @param max_age Seconds after which a read waits for the refresh it
      starts instead of returning the old value at once (default: never).
    @param max_wait The longest such a read waits, in seconds (default 2);
      after that, or if the refresh fails, it returns the old value.
    @param retry_after Seconds to wait after a failed fetch before trying
      again (default 30). Until then, reads get the last good value, or
      re-raise the last error if nothing has loaded yet.
    @param final If [final v] holds for a fetched value, it is never
      refreshed, e.g. a day whose games have all finished. *)

type 'a reading = {
  value : 'a;
  age : float;  (** Seconds since [value] was fetched. *)
  stale : bool;
      (** [value] is outdated: the most recent fetch failed, or it is older
          than [max_age] because a refresh didn't finish in time. *)
}

val read : 'a t -> 'a reading
(** The current value. Waits if nothing has loaded yet, raising the fetch's
    exception if that first load fails, and for up to [max_wait] seconds if
    the value is older than [max_age]. *)

val get : 'a t -> 'a
(** [get t] is [(read t).value]. *)

(** A cache for one key at a time, such as a date. Reading a different key
    starts a fresh cache for it and drops the previous one. *)
module Keyed : sig
  type ('k, 'a) t

  val create :
    sw:Eio.Switch.t ->
    clock:_ Eio.Time.Mono.t ->
    ttl:float ->
    ?max_age:float ->
    ?max_wait:float ->
    ?retry_after:float ->
    ?final:('a -> bool) ->
    ('k -> 'a) ->
    ('k, 'a) t

  val read : ('k, 'a) t -> 'k -> 'a reading
end
