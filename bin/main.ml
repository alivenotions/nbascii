module Dream = Dream_eio

let page = Nbascii_web.Page.render

let respond_html ?status node = Dream.html ?status (Pure_html.to_string node)

let cached_page ~label ~render cache req =
  let path = "/" ^ String.concat "/" (Dream.path req) in
  let page = page ~path in
  match Nbascii.Cache.get cache with
  | data -> respond_html (Nbascii_web.Page.render_document ~path (render data))
  | exception (Eio.Cancel.Cancelled _ as exn) -> raise exn
  | exception exn ->
      Logs.err (fun m -> m "Fetching %s failed: %s" label (Printexc.to_string exn));
      respond_html ~status:`Service_unavailable
        (page (Printf.sprintf "Couldn't load %s. Try again in a moment." label))

let () =
  Dream.setup_log ();
  Mirage_crypto_rng_unix.use_default ();
  Eio_main.run @@ fun env ->
  let clock = Eio.Stdenv.clock env in
  let net = Eio.Stdenv.net env in
  let static = Eio.Path.(Eio.Stdenv.cwd env / "static") in
  let client = Nbascii.Nba_api.make_client ~net in
  let cache =
    Nbascii.Cache.create ~clock ~ttl:20.0 (fun () ->
        Nbascii.Nba_api.todays_scoreboard client ~clock)
  in
  let yesterday =
    Nbascii.Cache.create ~clock ~ttl:20.0 (fun () ->
      let today = Nbascii.Cache.get cache in
      let date = Nbascii.Score_date.previous today.date in
      Nbascii.Nba_api.scoreboard_on client ~clock ~date)
  in
  let standings =
    Nbascii.Cache.create ~clock ~ttl:300.0 (fun () -> Nbascii.Nba_api.standings client ~clock)
  in
  let leaders =
    Nbascii.Cache.create ~clock ~ttl:300.0 (fun () -> Nbascii.Nba_api.leaders client ~clock)
  in
  Dream.run ~net
  @@ Dream.logger ~clock
  @@ Dream.router [
    Dream.get "/" (cached_page ~label:"today's scores" ~render:Nbascii.Render.scoreboard_document cache);
    Dream.get "/yesterday" (cached_page ~label:"yesterday's scores" ~render:Nbascii.Render.scoreboard_document yesterday);
    Dream.get "/standings" (cached_page ~label:"standings" ~render:Nbascii.Render.standings_document standings);
    Dream.get "/stats" (cached_page ~label:"season leaders" ~render:Nbascii.Render.leaders_document leaders);
    Dream.get "/static/**" (Dream.static static);
  ]
