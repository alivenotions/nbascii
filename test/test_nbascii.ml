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

let () =
  Logs.set_level None;
  test_router ();
  Eio_main.run @@ fun env ->
  test_static env;
  test_server env;
  print_endline "all tests passed"
