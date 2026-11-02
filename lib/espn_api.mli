(** Fetching NBA scores from ESPN's scoreboard endpoint over HTTPS. *)

type client

val make_client : net:_ Eio.Net.t -> client
(** An HTTPS client that verifies certificates against the system's CA
    store. Call [Mirage_crypto_rng_unix.use_default ()] once at startup
    before making requests. *)

val scoreboard_url : Uri.t
val standings_url : Uri.t
val leaders_url : Uri.t
val scoreboard_url_for_date : string -> Uri.t

val todays_scoreboard : client -> clock:_ Eio.Time.clock -> Scoreboard.t
(** Fetches today's games. Raises [Failure] on a non-200 response or
     malformed data, and [Eio.Time.Timeout] after 10 seconds. *)

val scoreboard_on : client -> clock:_ Eio.Time.clock -> date:string -> Scoreboard.t
(** Games on a specified [YYYY-MM-DD] scoreboard day. *)
val standings : client -> clock:_ Eio.Time.clock -> Standings.t
val leaders : client -> clock:_ Eio.Time.clock -> Leaders.t
