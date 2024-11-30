let greet who =
  let open Dream_html in
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

let () =
  Dream.run
  @@ Dream.logger
  @@ Dream.router [
    Dream.get "/"
      (fun _ -> Dream_html.respond (greet "world"));
    Dream.get "/static/**" (Dream.static "./static");
  ]
