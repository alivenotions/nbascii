module Dream = Dream_eio

let check name cond = if not cond then failwith ("FAIL: " ^ name)
let status res = Http.Status.to_int (Dream.status res)

let test_router () =
  let app =
    Dream.router [
      Dream.get "/" (fun _ -> Dream.respond "home");
      Dream.get "/games/:id" (fun req -> Dream.respond (Dream.param req "id"));
      Dream.post "/games" (fun req -> Dream.respond ("posted " ^ Dream.body req));
      Dream.get "/files/**" (fun req -> Dream.respond (String.concat "|" (Dream.path req)));
      Dream.scope "/api" [ (fun next req ->
          let res = next req in
          Dream.respond ~headers:[ ("x-api", "1") ] (Dream.response_body res)) ]
        [ Dream.get "/team/:abbr" (fun req -> Dream.respond (Dream.param req "abbr")) ];
    ]
  in
  let run ?meth ?body target = app (Dream.request ?meth ?body target) in
  check "root" (Dream.response_body (run "/") = "home");
  check "param" (Dream.response_body (run "/games/42") = "42");
  check "param decoded" (Dream.response_body (run "/games/a%20b") = "a b");
  check "post" (Dream.response_body (run ~meth:`POST ~body:"x" "/games") = "posted x");
  check "wrong method" (status (run ~meth:`POST "/") = 404);
  check "head falls back to get" (status (run ~meth:`HEAD "/") = 200);
  check "wildcard" (Dream.response_body (run "/files/a/b.css") = "a|b.css");
  check "unknown" (status (run "/nope") = 404);
  check "query" (Dream.query (Dream.request "/x?team=BOS") "team" = Some "BOS");
  let api = run "/api/team/LAL" in
  check "scope" (Dream.response_body api = "LAL");
  check "scope middleware" (Dream.response_header api "x-api" = Some "1")

let test_static env =
  let cwd = Eio.Stdenv.cwd env in
  let root = Eio.Path.(cwd / "static_test") in
  Eio.Path.mkdirs ~exists_ok:true ~perm:0o755 root;
  Eio.Path.save ~create:(`Or_truncate 0o644) Eio.Path.(root / "a.css") "body{}";
  Eio.Path.save ~create:(`Or_truncate 0o644) Eio.Path.(cwd / "secret.txt") "secret";
  Eio.Path.mkdirs ~exists_ok:true ~perm:0o755 Eio.Path.(root / "dir");
  let app = Dream.router [ Dream.get "/static/**" (Dream.static root) ] in
  let get target = app (Dream.request target) in
  let res = get "/static/a.css" in
  check "static ok" (status res = 200 && Dream.response_body res = "body{}");
  check "static mime" (Dream.response_header res "content-type" = Some "text/css");
  check "static missing" (status (get "/static/nope.css") = 404);
  check "static dir" (status (get "/static/dir") = 404);
  check "static dotdot" (status (get "/static/../secret.txt") = 404);
  check "static encoded dotdot" (status (get "/static/%2e%2e/secret.txt") = 404);
  check "static encoded slash" (status (get "/static/..%2Fsecret.txt") = 404)

let test_server env =
  Eio.Switch.run @@ fun sw ->
  let net = Eio.Stdenv.net env in
  let bound, set_bound = Eio.Promise.create () in
  let app =
    Dream.router [
      Dream.get "/" (fun _ -> Dream.html "<p>hi</p>");
      Dream.get "/boom" (fun _ -> failwith "boom");
    ]
  in
  Eio.Fiber.fork_daemon ~sw (fun () ->
      Dream.run ~net ~port:0 ~on_listen:(Eio.Promise.resolve set_bound) app);
  let port = match Eio.Promise.await bound with `Tcp (_, port) -> port | _ -> assert false in
  let fetch path =
    Eio.Net.with_tcp_connect ~host:"localhost" ~service:(string_of_int port) net @@ fun conn ->
    Eio.Flow.copy_string
      (Printf.sprintf "GET %s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" path)
      conn;
    Eio.Buf_read.(parse_exn take_all) ~max_size:max_int conn
  in
  let contains s sub =
    let n = String.length sub in
    let rec go i = i + n <= String.length s && (String.sub s i n = sub || go (i + 1)) in
    go 0
  in
  let ok = fetch "/" in
  check "server 200" (String.starts_with ~prefix:"HTTP/1.1 200" ok);
  check "server body" (contains ok "<p>hi</p>");
  check "server 500" (String.starts_with ~prefix:"HTTP/1.1 500" (fetch "/boom"));
  check "server 404" (String.starts_with ~prefix:"HTTP/1.1 404" (fetch "/missing"))

let test_scoreboard () =
  let json = In_channel.with_open_bin "scoreboard.json" In_channel.input_all in
  let board = Nbascii.Scoreboard.of_string json in
  check "date" (board.date = "2026-10-30");
  match board.games with
  | [ final; live; scheduled ] ->
      check "final status" (final.status = Final && final.status_text = "Final/OT");
      check "final overtime periods" (List.length final.home.periods = 5);
      check "live score" (live.status = Live && live.away.score = 80 && live.period = 3);
      check "scheduled null score" (scheduled.status = Scheduled && scheduled.home.score = 0);
      let text = Nbascii.Render.scoreboard board in
      let lines = String.split_on_char '\n' text in
      check "heading" (List.hd lines = "NBA SCORES  2026-10-30");
      check "winner marked" (List.mem "CLE    3-1 28 30 25 22 13  118 <" lines);
      check "overtime column" (List.mem "TEAM   W-L  1  2  3  4 OT  TOT" lines);
      check "live shows played periods only" (List.mem "BOS    4-0 30 27 23   80" lines);
      check "live label remains without color" (List.mem "LIVE  5:21 - 3rd" lines);
      check "scheduled" (scheduled.status_text = "10/30 - 10:00 PM EDT");
      check "ESPN abbreviations" (final.away.tricode = "NYK" && scheduled.home.tricode = "GSW");
      check "home and away independent of feed order" (final.home.tricode = "CLE" && live.home.tricode = "LAL");
      check "team metadata" (live.away.city = "Boston" && live.away.name = "Celtics");
      check "live status text" (live.status_text = "5:21 - 3rd");
      check "no repeated boxes" (not (List.exists (String.starts_with ~prefix:"+") lines));
      check "scheduled game is compact" (List.length (Nbascii.Render.game scheduled) = 3);
      check "compact final width"
        (List.for_all (fun line -> String.length line <= 32) (Nbascii.Render.game final));
      let columns = List.nth (Nbascii.Render.game final) 1 in
      check "totals aligned with heading"
        (String.sub columns 27 3 = "TOT"
         && String.sub (List.nth (Nbascii.Render.game final) 3) 27 3 = "118")
  | _ -> failwith "FAIL: expected three games"

let test_scoreboard_errors () =
  let fails s = match Nbascii.Scoreboard.of_string s with _ -> false | exception Failure _ -> true in
  check "invalid json" (fails "{");
  check "wrong shape" (fails {|{"error": "upstream unavailable"}|});
  check "missing events" (fails {|{"day": {"date": "2026-07-01"}}|});
  check "invalid events" (fails {|{"day": {"date": "2026-07-01"}, "events": {}}|});
  check "missing date" (fails {|{"day": {}, "events": []}|});
  check "missing competition" (fails {|{"day": {"date": "2026-07-01"}, "events": [{"status": {"type": {"state": "pre"}}, "competitions": []}]}|});
  check "unknown state" (fails {|{"day": {"date": "2026-07-01"}, "events": [{"status": {"type": {"state": "unknown"}}}]}|});
  check "empty day" ((Nbascii.Scoreboard.of_string {|{"day": {"date": "2026-07-01"}, "events": []}|}).games = []);
  check "empty render"
    (Nbascii.Render.scoreboard { date = "2026-07-01"; games = [] } = "NBA SCORES  2026-07-01\n\nNo games today.")

let test_espn_edge_cases () =
  let team side extra =
    `Assoc ([ ("homeAway", `String side);
              ("team", `Assoc [ ("abbreviation", `String "BOS") ]) ] @ extra)
  in
  let board competitors =
    `Assoc [ ("day", `Assoc [ ("date", `String "2026-10-30") ]);
             ("events", `List [ `Assoc [
               ("id", `String "1");
               ("status", `Assoc [ ("type", `Assoc [ ("state", `String "pre");
                                                         ("shortDetail", `String "Postponed") ]) ]);
               ("competitions", `List [ `Assoc [ ("competitors", `List competitors) ] ]) ] ]) ]
  in
  let fails json =
    match Nbascii.Scoreboard.of_json json with
    | _ -> false
    | exception Failure _ -> true
  in
  let home = team "home" [] and away = team "away" [] in
  let parsed = Nbascii.Scoreboard.of_json (board [home; away]) in
  let game = List.hd parsed.games in
  check "missing optional team data"
    (game.home.wins = 0 && game.home.losses = 0 && game.home.score = 0 && game.home.periods = []);
  check "preserve postponed status" (game.status = Scheduled && game.status_text = "Postponed");
  check "missing away team" (fails (board [home]));
  check "duplicate home team" (fails (board [home; home; away]));
  check "invalid score string" (fails (board [team "home" [("score", `String "bad")]; away]));
  check "invalid record"
    (fails (board [team "home" [("records", `List [ `Assoc [
      ("type", `String "total"); ("summary", `String "bad") ] ])]; away]))

let test_cache () =
  Eio_mock.Backend.run @@ fun () ->
  let clock = Eio_mock.Clock.make () in
  let calls = ref 0 and fail = ref false in
  let cache =
    Nbascii.Cache.create ~clock ~ttl:20.0 (fun () ->
        incr calls;
        if !fail then failwith "upstream down";
        !calls)
  in
  check "first fetch" (Nbascii.Cache.get cache = 1);
  check "cached" (Nbascii.Cache.get cache = 1 && !calls = 1);
  Eio_mock.Clock.set_time clock 21.0;
  check "refetched after ttl" (Nbascii.Cache.get cache = 2);
  fail := true;
  Eio_mock.Clock.set_time clock 42.0;
  check "stale on error" (Nbascii.Cache.get cache = 2 && !calls = 3);
  check "still usable after error" (Nbascii.Cache.get cache = 2 && !calls = 4);
  let empty = Nbascii.Cache.create ~clock ~ttl:20.0 (fun () -> failwith "down") in
  check "error without value"
    (match Nbascii.Cache.get empty with _ -> false | exception Failure _ -> true)

let () =
  Logs.set_level None;
  test_router ();
  test_scoreboard_errors ();
  test_espn_edge_cases ();
  test_cache ();
  test_scoreboard ();
  Eio_main.run @@ fun env ->
  test_static env;
  test_server env;
  print_endline "all tests passed"
