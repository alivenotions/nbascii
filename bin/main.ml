module Dream = Dream_eio
module Cache = Nbascii.Cache

let page = Nbascii_web.Page.render

let respond_html ?status node = Dream.html ?status (Pure_html.to_string node)

(* While a game is live, the browser reloads the page every 30 seconds. *)
let live_refresh board = if Nbascii.Scoreboard.live board then Some 30 else None

let cached_page ?(refresh = fun _ -> None) ~label ~render read req =
  let path = "/" ^ String.concat "/" (Dream.path req) in
  match read () with
  | ({ value; age; stale } : _ Cache.reading) ->
      let document = render value in
      let document =
        if stale then Nbascii.Render.with_note (Nbascii.Render.stale_note ~age) document
        else document
      in
      respond_html (Nbascii_web.Page.render_document ?refresh:(refresh value) ~path document)
  | exception (Eio.Cancel.Cancelled _ as exn) -> raise exn
  | exception exn ->
      Logs.err (fun m -> m "Fetching %s failed: %s" label (Printexc.to_string exn));
      respond_html ~status:`Service_unavailable
        (page ~path (Printf.sprintf "Couldn't load %s. Try again in a moment." label))

let () =
  Dream.setup_log ();
  Mirage_crypto_rng_unix.use_default ();
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let clock = Eio.Stdenv.clock env in
  let mono = Eio.Stdenv.mono_clock env in
  let net = Eio.Stdenv.net env in
  let static = Eio.Path.(Eio.Stdenv.cwd env / "static") in
  let client = Nbascii.Espn_api.make_client ~net in
  let today =
    Cache.create ~sw ~clock:mono ~ttl:20.0 ~max_age:60.0 (fun () ->
        Nbascii.Espn_api.todays_scoreboard client ~clock)
  in
  (* Keyed by date, so it moves on when today's date rolls over, and frozen
     once all of that day's games have finished. *)
  let yesterday =
    Cache.Keyed.create ~sw ~clock:mono ~ttl:20.0 ~max_age:60.0 ~final:Nbascii.Scoreboard.finished
      (fun date -> Nbascii.Espn_api.scoreboard_on client ~clock ~date)
  in
  let read_yesterday () =
    let date = Nbascii.Score_date.previous (Cache.get today).date in
    Cache.Keyed.read yesterday date
  in
  let standings =
    Cache.create ~sw ~clock:mono ~ttl:300.0 ~max_age:900.0 (fun () ->
        Nbascii.Espn_api.standings client ~clock)
  in
  let leaders =
    Cache.create ~sw ~clock:mono ~ttl:300.0 ~max_age:900.0 (fun () ->
        Nbascii.Espn_api.leaders client ~clock)
  in
  let render = Nbascii.Render.scoreboard_document in
  Dream.run ~net
  @@ Dream.logger ~clock
  @@ Dream.router [
    Dream.get "/"
      (cached_page ~refresh:live_refresh ~label:"today's scores" ~render
         (fun () -> Cache.read today));
    Dream.get "/yesterday"
      (cached_page ~refresh:live_refresh ~label:"yesterday's scores" ~render read_yesterday);
    Dream.get "/standings"
      (cached_page ~label:"standings" ~render:Nbascii.Render.standings_document
         (fun () -> Cache.read standings));
    Dream.get "/stats"
      (cached_page ~label:"season leaders" ~render:Nbascii.Render.leaders_document
         (fun () -> Cache.read leaders));
    Dream.get "/static/**" (Dream.static static);
  ]
