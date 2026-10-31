type client = Cohttp_eio.Client.t

let scoreboard_url =
  Uri.of_string "https://cdn.nba.com/static/json/liveData/scoreboard/todaysScoreboard_00.json"

(* The CDN may reject requests that don't look like they come from nba.com. *)
let headers =
  Http.Header.of_list
    [
      ("user-agent", "Mozilla/5.0 (compatible; nbascii)");
      ("referer", "https://www.nba.com/");
      ("accept", "application/json");
    ]

let https () =
  let authenticator =
    match Ca_certs.authenticator () with
    | Ok a -> a
    | Error (`Msg msg) -> failwith ("Nba_api: loading CA certificates: " ^ msg)
  in
  let config =
    match Tls.Config.client ~authenticator () with
    | Ok c -> c
    | Error (`Msg msg) -> failwith ("Nba_api: TLS config: " ^ msg)
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
      Printf.ksprintf failwith "Nba_api: %s returned %s" (Uri.to_string uri)
        (Http.Status.to_string status)

let todays_scoreboard client ~clock =
  Eio.Time.with_timeout_exn clock 10.0 (fun () -> get_string client scoreboard_url)
  |> Scoreboard.of_string
