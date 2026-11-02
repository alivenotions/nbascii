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
  let module Cache = Nbascii.Cache in
  Eio_mock.Backend.run @@ fun () ->
  Eio.Switch.run @@ fun sw ->
  let clock = Eio_mock.Clock.Mono.make () in
  let at s = Eio_mock.Clock.Mono.set_time clock (Mtime.of_uint64_ns (Int64.of_float (s *. 1e9))) in
  let raises f = match f () with _ -> false | exception Failure _ -> true in
  (* [fetch] returns call numbers; [gate], when set, blocks it until resolved. *)
  let calls = ref 0 and fail = ref false and gate = ref None in
  let fetch () =
    incr calls;
    Option.iter Eio.Promise.await !gate;
    if !fail then failwith "upstream down";
    !calls
  in
  let cache = Cache.create ~sw ~clock ~ttl:20.0 ~retry_after:30.0 fetch in
  check "lazy" (!calls = 0);
  check "first fetch" (Cache.get cache = 1);
  check "cached" (Cache.get cache = 1 && !calls = 1);

  (* Expired: the old value comes back at once while the refresh is blocked. *)
  at 21.0;
  let release, resolve = Eio.Promise.create () in
  gate := Some release;
  let r = Cache.read cache in
  check "no wait on refresh" (r.value = 1 && (not r.stale) && !calls = 2);
  check "one refresh at a time" (Cache.get cache = 1 && !calls = 2);
  gate := None;
  Eio.Promise.resolve resolve ();
  Eio.Fiber.yield ();
  check "refreshed value" (Cache.get cache = 2);

  (* A failed refresh keeps the old value, marks it stale, and backs off. *)
  fail := true;
  at 42.0;
  check "refresh started" (Cache.get cache = 2 && !calls = 3);
  let r = Cache.read cache in
  check "stale after failure" (r.value = 2 && r.stale && r.age = 21.0);
  at 60.0;
  check "backing off" (Cache.get cache = 2 && !calls = 3);
  at 73.0;
  check "retried after backoff" (Cache.get cache = 2 && !calls = 4);
  fail := false;
  at 104.0;
  ignore (Cache.get cache);
  let r = Cache.read cache in
  check "recovered" (r.value = 5 && not r.stale);

  (* Nothing loaded yet: the error is raised, then re-raised without
     refetching until the backoff ends. *)
  let attempts = ref 0 in
  let empty = Cache.create ~sw ~clock ~ttl:20.0 ~retry_after:30.0 (fun () -> incr attempts; failwith "down") in
  check "error without value" (raises (fun () -> Cache.get empty) && !attempts = 1);
  check "fails fast while backing off" (raises (fun () -> Cache.get empty) && !attempts = 1);
  at 140.0;
  check "retries after backoff" (raises (fun () -> Cache.get empty) && !attempts = 2);

  (* Concurrent first reads share one fetch. *)
  let shared_calls = ref 0 and release, resolve = Eio.Promise.create () in
  let shared = Cache.create ~sw ~clock ~ttl:20.0 (fun () -> incr shared_calls; Eio.Promise.await release; "v") in
  let results = ref [] in
  Eio.Fiber.all [
    (fun () -> let v = Cache.get shared in results := v :: !results);
    (fun () -> let v = Cache.get shared in results := v :: !results);
    (fun () -> Eio.Promise.resolve resolve ());
  ];
  check "shared first fetch" (!results = [ "v"; "v" ] && !shared_calls = 1);

  (* A final value is never refreshed. *)
  let final_calls = ref 0 in
  let frozen = Cache.create ~sw ~clock ~ttl:20.0 ~final:(fun v -> v >= 2) (fun () -> incr final_calls; !final_calls) in
  check "not final yet" (Cache.get frozen = 1);
  at 200.0;
  ignore (Cache.get frozen);
  check "became final" (Cache.get frozen = 2);
  at 10_000.0;
  check "final never refreshed" (Cache.get frozen = 2 && !final_calls = 2);

  (* Keyed: one cache per key, replaced when the key changes. *)
  let keyed_calls = ref 0 in
  let keyed =
    Cache.Keyed.create ~sw ~clock ~ttl:20.0 ~final:(fun _ -> true) (fun key -> incr keyed_calls; key ^ "!")
  in
  check "keyed fetch" ((Cache.Keyed.read keyed "a").value = "a!");
  at 20_000.0;
  check "keyed final" ((Cache.Keyed.read keyed "a").value = "a!" && !keyed_calls = 1);
  check "new key fetches" ((Cache.Keyed.read keyed "b").value = "b!" && !keyed_calls = 2)

let test_stale_note () =
  let module R = Nbascii.Render in
  check "seconds" (R.stale_note ~age:42.0 = "Showing data from 42 s ago; ESPN isn't responding.");
  check "minutes" (R.stale_note ~age:720.0 = "Showing data from 12 min ago; ESPN isn't responding.");
  check "hours" (R.stale_note ~age:7200.0 = "Showing data from 2 h ago; ESPN isn't responding.");
  let doc = [ [ { R.text = "HEAD"; tone = Heading } ]; [ { R.text = "body"; tone = Plain } ] ] in
  check "note under heading"
    (R.to_text (R.with_note "note" doc) = "HEAD\nnote\nbody")

let test_finished () =
  let module S = Nbascii.Scoreboard in
  let board = S.of_string (In_channel.with_open_bin "scoreboard.json" In_channel.input_all) in
  check "fixture has unfinished games" (not (S.finished board));
  check "all final"
    (S.finished { board with games = List.filter (fun (g : S.game) -> g.status = Final) board.games });
  check "no games" (S.finished { board with games = [] })

let () =
  Logs.set_level None;
  test_router ();
  test_scoreboard_errors ();
  test_espn_edge_cases ();
  test_cache ();
  test_stale_note ();
  test_finished ();
  test_scoreboard ();
  Eio_main.run @@ fun env ->
  test_static env;
  test_server env;
  print_endline "all tests passed"
