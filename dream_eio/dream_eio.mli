(** A small, direct-style web framework on Eio, modelled on Dream's API.

    Handlers are plain functions from a request to a response: no promises,
    no [Lwt.t]. Each connection runs in its own Eio fiber, so a handler can
    block on I/O (files, HTTP calls) without stalling other requests. *)

(** {1 Types} *)

type request
type response

type handler = request -> response
(** A handler answers one request. *)

type middleware = handler -> handler
(** A middleware wraps a handler, e.g. to log or to add headers. *)

type route
(** A route built by {!get}, {!post}, {!any} or {!scope}. *)

(** {1 Running a server} *)

val run :
  net:_ Eio.Net.t ->
  ?interface:string ->
  ?port:int ->
  ?on_listen:(Eio.Net.Sockaddr.stream -> unit) ->
  handler ->
  'a
(** [run ~net handler] serves [handler] over HTTP until cancelled. It
    must be called inside [Eio_main.run]. [interface] defaults to
    ["localhost"] and [port] to [8080]. Exceptions raised by [handler] are
    logged and turned into a [500] response. [on_listen] is called once the
    socket is bound (useful with [~port:0]). *)

(** {1 Requests} *)

val request :
  ?meth:Http.Method.t ->
  ?headers:(string * string) list ->
  ?body:string ->
  string ->
  request
(** [request target] builds a request without a server, for tests. [meth]
    defaults to [`GET]. *)

val meth : request -> Http.Method.t
val target : request -> string
(** The full request target, including any query string. *)

val path : request -> string list
(** Path segments, percent-decoded. Inside a [**] route this is the part of
    the path that matched the [**]. *)

val header : request -> string -> string option
val query : request -> string -> string option

val param : request -> string -> string
(** [param req name] is the value of the [:name] segment of the route that
    matched [req]. Raises [Failure] if the route has no such parameter. *)

val body : request -> string
(** Reads the whole request body. *)

(** {1 Responses} *)

val respond :
  ?status:Http.Status.t -> ?headers:(string * string) list -> string -> response

val html :
  ?status:Http.Status.t -> ?headers:(string * string) list -> string -> response

val empty : ?headers:(string * string) list -> Http.Status.t -> response
val not_found : handler

val status : response -> Http.Status.t
val response_header : response -> string -> string option
val response_body : response -> string

(** {1 Routing} *)

val router : route list -> handler
(** [router routes] dispatches to the first route matching the request's
    method and path, or answers [404].

    Route patterns are split on [/]. A segment [:name] matches any single
    segment and binds it for {!param}. A final [**] matches the rest of the
    path, which the handler sees as {!path}. *)

val get : string -> handler -> route
val post : string -> handler -> route
val put : string -> handler -> route
val delete : string -> handler -> route
val any : string -> handler -> route

val scope : string -> middleware list -> route list -> route
(** [scope prefix middlewares routes] mounts [routes] under [prefix], running
    each matching request through [middlewares] first. *)

(** {1 Middleware} *)

val logger : clock:_ Eio.Time.clock -> middleware
(** Logs each request with its status and duration. *)

val pipeline : middleware list -> middleware
(** [pipeline [a; b]] is [fun h -> a (b h)]. *)

(** {1 Static files} *)

val static : _ Eio.Path.t -> handler
(** [static dir] serves files below [dir], using the request's {!path} as the
    file's location. Use it behind a [**] route. Requests cannot escape
    [dir]: [..] and symlinks pointing outside it are refused. *)

(** {1 Logging} *)

val setup_log : ?level:Logs.level -> unit -> unit
(** Sends logs to stderr at [level] (default [Info]). cohttp's own
    per-connection messages are kept at [Warning] so they don't drown out
    {!logger}. *)

val log_src : Logs.src
(** The log source used by {!logger} and {!run}. *)
