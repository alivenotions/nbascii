(** Fetching data from NBA's live data CDN over HTTPS. *)

type client

val make_client : net:_ Eio.Net.t -> client
(** An HTTPS client that verifies certificates against the system's CA
    store. Call [Mirage_crypto_rng_unix.use_default ()] once at startup
    before making requests. *)

val scoreboard_url : Uri.t

val todays_scoreboard : client -> clock:_ Eio.Time.clock -> Scoreboard.t
(** Fetches today's games. Raises [Failure] on a non-200 response or
    malformed data, and [Eio.Time.Timeout] after 10 seconds. *)
