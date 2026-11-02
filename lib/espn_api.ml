type client = Cohttp_eio.Client.t

let scoreboard_url =
  Uri.of_string "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard"

let standings_url =
  Uri.of_string "https://site.api.espn.com/apis/v2/sports/basketball/nba/standings"

let leaders_url =
  Uri.of_string "https://site.api.espn.com/apis/site/v3/sports/basketball/nba/leaders"

let scoreboard_url_for_date date =
  Uri.add_query_param' scoreboard_url ("dates", Score_date.espn_query date)

let headers =
  Http.Header.of_list
    [
      ("user-agent", "nbascii");
      ("accept", "application/json");
    ]

let https () =
  let authenticator =
    match Ca_certs.authenticator () with
    | Ok a -> a
    | Error (`Msg msg) -> failwith ("Espn_api: loading CA certificates: " ^ msg)
  in
  let config =
    match Tls.Config.client ~authenticator () with
    | Ok c -> c
    | Error (`Msg msg) -> failwith ("Espn_api: TLS config: " ^ msg)
  in
  fun uri raw ->
    let host =
      Uri.host uri |> Option.map (fun h -> Domain_name.(host_exn (of_string_exn h)))
    in
    Tls_eio.client_of_flow ?host config raw

let make_client ~net = Cohttp_eio.Client.make ~https:(Some (https ())) net

let get_string client uri =
  Eio.Switch.run @@ fun sw ->
  let resp, body = Cohttp_eio.Client.get client ~sw ~headers uri in
  match Http.Response.status resp with
  | `OK -> Eio.Buf_read.(parse_exn take_all) ~max_size:(10 * 1024 * 1024) body
  | status ->
      Printf.ksprintf failwith "Espn_api: %s returned %s" (Uri.to_string uri)
        (Http.Status.to_string status)

let todays_scoreboard client ~clock =
  Eio.Time.with_timeout_exn clock 10.0 (fun () -> get_string client scoreboard_url)
  |> Scoreboard.of_string

let scoreboard_on client ~clock ~date =
  let url = scoreboard_url_for_date date in
  Eio.Time.with_timeout_exn clock 10.0 (fun () -> get_string client url)
  |> Scoreboard.of_string ~date

let standings client ~clock =
  Eio.Time.with_timeout_exn clock 10.0 (fun () -> get_string client standings_url)
  |> Standings.of_string

let leaders client ~clock =
  Eio.Time.with_timeout_exn clock 10.0 (fun () -> get_string client leaders_url)
  |> Leaders.of_string
