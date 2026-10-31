module Dream = Dream_eio

let page text =
  let open Pure_html in
  let open HTML in
  html [lang "en"] [
    head [] [
      meta [charset "utf-8"];
      meta [name "viewport"; content "width=device-width, initial-scale=1"];
      title [] "nbascii";
      link [rel "stylesheet"; href "static/main.css"];
      link [rel "preconnect"; href "https://fonts.googleapis.com"; ] ;
      link [rel "preconnect"; href "https://fonts.gstatic.com"; crossorigin `anonymous; ] ;
      link [href "https://fonts.googleapis.com/css2?family=Courier+Prime:ital,wght@0,400;0,700;1,400;1,700&display=swap"; rel "stylesheet"; ] ;
    ];
    body [] [
      pre [] [txt "%s" text];
    ];
  ]

let respond_html ?status node = Dream.html ?status (Pure_html.to_string node)

let scores cache _req =
  match Nbascii.Cache.get cache with
  | board -> respond_html (page (Nbascii.Render.scoreboard board))
  | exception (Eio.Cancel.Cancelled _ as exn) -> raise exn
  | exception exn ->
      Logs.err (fun m -> m "Fetching scores failed: %s" (Printexc.to_string exn));
      respond_html ~status:`Service_unavailable
        (page "Couldn't load today's scores. Try again in a moment.")

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
  Dream.run ~net
  @@ Dream.logger ~clock
  @@ Dream.router [
    Dream.get "/" (scores cache);
    Dream.get "/static/**" (Dream.static static);
  ]
