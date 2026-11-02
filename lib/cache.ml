let src = Logs.Src.create "nbascii.cache"

module Log = (val Logs.src_log src)

type 'a entry = { value : 'a; fetched_at : float; final : bool }

type 'a t = {
  sw : Eio.Switch.t;
  now : unit -> float;
  ttl : float;
  retry_after : float;
  final : 'a -> bool;
  fetch : unit -> 'a;
  mutable entry : 'a entry option;
  mutable failure : (float * exn) option;  (** Time and error of the last failed fetch. *)
  mutable in_flight : ('a entry, exn) result Eio.Promise.t option;
}

type 'a reading = { value : 'a; age : float; stale : bool }

let seconds mtime = Int64.to_float (Mtime.to_uint64_ns mtime) /. 1e9

let create ~sw ~clock ~ttl ?(retry_after = 30.0) ?(final = fun _ -> false) fetch =
  {
    sw;
    now = (fun () -> seconds (Eio.Time.Mono.now clock));
    ttl;
    retry_after;
    final;
    fetch;
    entry = None;
    failure = None;
    in_flight = None;
  }

(* The fetch runs in its own fiber on the cache's switch, so a reader that
   gives up (e.g. the client disconnects) doesn't cancel it for everyone. *)
let start_fetch t =
  match t.in_flight with
  | Some promise -> promise
  | None ->
      let promise, resolver = Eio.Promise.create () in
      t.in_flight <- Some promise;
      let finish result =
        t.in_flight <- None;
        Eio.Promise.resolve resolver result
      in
      Eio.Fiber.fork ~sw:t.sw (fun () ->
          match t.fetch () with
          | value ->
              let entry = { value; fetched_at = t.now (); final = t.final value } in
              t.entry <- Some entry;
              t.failure <- None;
              finish (Ok entry)
          | exception (Eio.Cancel.Cancelled _ as exn) ->
              finish (Error exn);
              raise exn
          | exception exn ->
              Log.warn (fun m -> m "Fetch failed: %s" (Printexc.to_string exn));
              t.failure <- Some (t.now (), exn);
              finish (Error exn));
      promise

let backing_off t =
  match t.failure with
  | Some (failed_at, _) -> t.now () -. failed_at < t.retry_after
  | None -> false

let reading t (entry : _ entry) =
  {
    value = entry.value;
    age = t.now () -. entry.fetched_at;
    stale =
      (match t.failure with
      | Some (failed_at, _) -> failed_at >= entry.fetched_at
      | None -> false);
  }

let read t =
  match t.entry with
  | Some entry ->
      let expired = (not entry.final) && t.now () -. entry.fetched_at >= t.ttl in
      if expired && Option.is_none t.in_flight && not (backing_off t) then
        ignore (start_fetch t);
      (* A fetch that finished without blocking may have replaced [entry]. *)
      reading t (Option.value t.entry ~default:entry)
  | None -> (
      match t.failure with
      | Some (_, exn) when Option.is_none t.in_flight && backing_off t -> raise exn
      | _ -> (
          match Eio.Promise.await (start_fetch t) with
          | Ok entry -> reading t entry
          | Error exn -> raise exn))

let get t = (read t).value

module Keyed = struct
  type nonrec ('k, 'a) t = {
    make : 'k -> 'a t;
    mutable current : ('k * 'a t) option;
  }

  let create ~sw ~clock ~ttl ?retry_after ?final fetch =
    {
      make = (fun key -> create ~sw ~clock ~ttl ?retry_after ?final (fun () -> fetch key));
      current = None;
    }

  let read t key =
    let cache =
      match t.current with
      | Some (k, cache) when k = key -> cache
      | _ ->
          let cache = t.make key in
          t.current <- Some (key, cache);
          cache
    in
    read cache
end
