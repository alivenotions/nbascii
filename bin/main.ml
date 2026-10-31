module Dream = Dream_eio

let greet who =
  let open Pure_html in
  let open HTML in
  html [lang "en"] [
    head [] [
      title [] "nbascii";
      link [rel "stylesheet"; href "static/main.css"];
      link [rel "preconnect"; href "https://fonts.googleapis.com"; ] ;
      link [rel "preconnect"; href "https://fonts.gstatic.com"; crossorigin `anonymous; ] ;
      link [href "https://fonts.googleapis.com/css2?family=Courier+Prime:ital,wght@0,400;0,700;1,400;1,700&display=swap"; rel "stylesheet"; ] ;
    ];
    comment "Embedded in the HTML";
    body [] [
      h1 [] [txt "Good morning, %s!" who];
    ];
  ]

let respond_html node = Dream.html (Pure_html.to_string node)

let () =
  Dream.setup_log ();
  Eio_main.run @@ fun env ->
  let clock = Eio.Stdenv.clock env in
  let static = Eio.Path.(Eio.Stdenv.cwd env / "static") in
  Dream.run ~net:(Eio.Stdenv.net env)
  @@ Dream.logger ~clock
  @@ Dream.router [
    Dream.get "/"
      (fun _ -> respond_html (greet "world"));
    Dream.get "/static/**" (Dream.static static);
  ]
