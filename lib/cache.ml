let src = Logs.Src.create "nbascii.cache"

module Log = (val Logs.src_log src)

type 'a t = {
  now : unit -> float;
  ttl : float;
  fetch : unit -> 'a;
  mutex : Eio.Mutex.t;
  mutable value : ('a * float) option;
}

let create ~clock ~ttl fetch =
  { now = (fun () -> Eio.Time.now clock); ttl; fetch; mutex = Eio.Mutex.create (); value = None }

let get t =
  (* [use_ro] unlocks rather than poisons the mutex if [fetch] raises; [value]
     is only assigned after a successful fetch, so it stays consistent. *)
  Eio.Mutex.use_ro t.mutex @@ fun () ->
  let now = t.now () in
  match t.value with
  | Some (v, fetched_at) when now -. fetched_at < t.ttl -> v
  | stale -> (
      match t.fetch () with
      | v ->
          t.value <- Some (v, now);
          v
      | exception (Eio.Cancel.Cancelled _ as exn) -> raise exn
      | exception exn -> (
          match stale with
          | Some (v, _) ->
              Log.warn (fun m -> m "Refresh failed, serving stale value: %s" (Printexc.to_string exn));
              v
          | None -> raise exn))
