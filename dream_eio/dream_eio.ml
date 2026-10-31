let log_src = Logs.Src.create "dream_eio" ~doc:"Dream-style web framework on Eio"

module Log = (val Logs.src_log log_src)

type request = {
  meth : Http.Method.t;
  target : string;
  uri : Uri.t;
  headers : Http.Header.t;
  body : string Lazy.t;
  client : string;
  path : string list;
  params : (string * string) list;
}

type response = { status : Http.Status.t; headers : Http.Header.t; body : string }
type handler = request -> response
type middleware = handler -> handler

type entry = {
  route_meth : Http.Method.t option;
  pattern : string list;
  handler : handler;
}

type route = entry list

(* Requests *)

let split_path s =
  String.split_on_char '/' s |> List.filter (fun seg -> seg <> "")

let make_request ~meth ~target ~headers ~body ~client =
  let uri = Uri.of_string target in
  let path = split_path (Uri.path uri) |> List.map Uri.pct_decode in
  { meth; target; uri; headers; body; client; path; params = [] }

let request ?(meth = `GET) ?(headers = []) ?(body = "") target =
  make_request ~meth ~target ~headers:(Http.Header.of_list headers)
    ~body:(Lazy.from_val body) ~client:"test"

let meth (req : request) = req.meth
let target (req : request) = req.target
let path (req : request) = req.path
let header (req : request) name = Http.Header.get req.headers name
let query (req : request) name = Uri.get_query_param req.uri name
let body (req : request) = Lazy.force req.body

let param (req : request) name =
  match List.assoc_opt name req.params with
  | Some value -> value
  | None -> failwith (Printf.sprintf "Dream_eio.param: no parameter %S" name)

(* Responses *)

let respond ?(status = `OK) ?(headers = []) body =
  { status; headers = Http.Header.of_list headers; body }

let html ?status ?(headers = []) body =
  respond ?status ~headers:(("content-type", "text/html; charset=utf-8") :: headers) body

let empty ?headers status = respond ~status ?headers ""
let not_found _ = empty `Not_found
let status (res : response) = res.status
let response_header (res : response) name = Http.Header.get res.headers name
let response_body (res : response) = res.body

(* Routing *)

let rec match_pattern pattern path params =
  match (pattern, path) with
  | [], [] -> Some (List.rev params, None)
  | [ "**" ], rest -> Some (List.rev params, Some rest)
  | p :: pattern, seg :: path when String.starts_with ~prefix:":" p ->
      let name = String.sub p 1 (String.length p - 1) in
      match_pattern pattern path ((name, seg) :: params)
  | p :: pattern, seg :: path when p = seg -> match_pattern pattern path params
  | _ -> None

let meth_matches entry meth =
  match entry.route_meth with
  | None -> true
  | Some m -> m = meth || (m = `GET && meth = `HEAD)

let router routes =
  let entries = List.concat routes in
  fun req ->
    let matching entry =
      if not (meth_matches entry req.meth) then None
      else
        match_pattern entry.pattern req.path []
        |> Option.map (fun (params, rest) -> (entry, params, rest))
    in
    match List.find_map matching entries with
    | None -> not_found req
    | Some (entry, params, rest) ->
        let path = Option.value rest ~default:req.path in
        entry.handler { req with params = req.params @ params; path }

let route meth pattern handler =
  [ { route_meth = meth; pattern = split_path pattern; handler } ]

let get = route (Some `GET)
let post = route (Some `POST)
let put = route (Some `PUT)
let delete = route (Some `DELETE)
let any = route None

let pipeline middlewares handler = List.fold_right ( @@ ) middlewares handler

let scope prefix middlewares routes =
  let prefix = split_path prefix in
  List.concat routes
  |> List.map (fun entry ->
         {
           entry with
           pattern = prefix @ entry.pattern;
           handler = pipeline middlewares entry.handler;
         })

(* Middleware *)

let logger ~clock next req =
  let start = Eio.Time.now clock in
  let elapsed_ms () = (Eio.Time.now clock -. start) *. 1000. in
  match next req with
  | res ->
      Log.info (fun m ->
          m "%s %s %s %d in %.1f ms" req.client
            (Http.Method.to_string req.meth)
            req.target
            (Http.Status.to_int res.status)
            (elapsed_ms ()));
      res
  | exception exn ->
      Log.warn (fun m ->
          m "%s %s %s raised after %.1f ms" req.client
            (Http.Method.to_string req.meth)
            req.target (elapsed_ms ()));
      raise exn

(* Static files *)

let safe_segment seg =
  seg <> "" && seg <> "." && seg <> ".."
  && not (String.exists (fun c -> c = '/' || c = '\\' || c = '\000') seg)

let static root req =
  match List.rev req.path with
  | [] -> not_found req
  | filename :: _ when List.for_all safe_segment req.path -> (
      try
        Eio.Path.with_subtree root @@ fun dir ->
        let file = List.fold_left Eio.Path.( / ) dir req.path in
        match Eio.Path.kind ~follow:true file with
        | `Regular_file ->
            let content_type = Magic_mime.lookup filename in
            respond ~headers:[ ("content-type", content_type) ] (Eio.Path.load file)
        | _ -> not_found req
      with Eio.Io _ -> not_found req)
  | _ -> not_found req

(* Server *)

let internal_error req exn =
  Log.err (fun m ->
      m "%s %s: %s" (Http.Method.to_string req.meth) req.target
        (Printexc.to_string exn));
  empty `Internal_server_error

let callback handler ((_sw, client), _) (http_req : Http.Request.t) body =
  let read_body () =
    Eio.Buf_read.(parse_exn take_all) ~max_size:max_int body
  in
  let req =
    make_request ~meth:(Http.Request.meth http_req)
      ~target:(Http.Request.resource http_req)
      ~headers:(Http.Request.headers http_req)
      ~body:(Lazy.from_fun read_body)
      ~client:(Format.asprintf "%a" Eio.Net.Sockaddr.pp client)
  in
  let res =
    match handler req with
    | res -> res
    | exception (Eio.Cancel.Cancelled _ as exn) -> raise exn
    | exception exn -> internal_error req exn
  in
  let body = if req.meth = `HEAD then "" else res.body in
  Cohttp_eio.Server.respond_string ~headers:res.headers ~status:res.status ~body ()

let run ~net ?(interface = "localhost") ?(port = 8080) ?on_listen handler =
  Eio.Switch.run @@ fun sw ->
  let addr =
    List.hd (Eio.Net.getaddrinfo_stream ~service:(string_of_int port) net interface)
  in
  let socket = Eio.Net.listen ~sw ~backlog:128 ~reuse_addr:true net addr in
  let addr = Eio.Net.listening_addr socket in
  Log.info (fun m -> m "Listening on %a" Eio.Net.Sockaddr.pp addr);
  Option.iter (fun f -> f addr) on_listen;
  let server = Cohttp_eio.Server.make ~callback:(callback handler) () in
  Cohttp_eio.Server.run socket server ~on_error:(fun exn ->
      Log.warn (fun m -> m "Connection error: %s" (Printexc.to_string exn)))

(* Logging *)

let setup_log ?(level = Logs.Info) () =
  Logs.set_reporter (Logs_fmt.reporter ());
  Logs.set_level (Some level);
  Logs.Src.set_level Cohttp_eio.src (Some Logs.Warning)
