type status =
  | Scheduled
  | Live
  | Final

type team = {
  tricode : string;
  city : string;
  name : string;
  wins : int;
  losses : int;
  score : int;
  periods : int list;
}

type game = {
  id : string;
  status : status;
  status_text : string;
  period : int;
  home : team;
  away : team;
}

type t = { date : string; games : game list }

let fail fmt = Printf.ksprintf failwith fmt

let field name json =
  match json with
  | `Assoc fields -> Option.value (List.assoc_opt name fields) ~default:`Null
  | _ -> fail "Scoreboard: expected an object around %S" name

(* The feed sends [null] or omits numbers for games that haven't started. *)
let int name json =
  match field name json with
  | `Int n -> n
  | `Float f -> int_of_float f
  | `Null -> 0
  | _ -> fail "Scoreboard: %S is not a number" name

let string name json =
  match field name json with
  | `String s -> s
  | `Null -> ""
  | _ -> fail "Scoreboard: %S is not a string" name

let list name json =
  match field name json with
  | `List items -> items
  | `Null -> []
  | _ -> fail "Scoreboard: %S is not a list" name

let status_of_int = function
  | 1 -> Scheduled
  | 2 -> Live
  | 3 -> Final
  | n -> fail "Scoreboard: unknown gameStatus %d" n

let team json =
  {
    tricode = string "teamTricode" json;
    city = string "teamCity" json;
    name = string "teamName" json;
    wins = int "wins" json;
    losses = int "losses" json;
    score = int "score" json;
    periods = List.map (int "score") (list "periods" json);
  }

let game json =
  {
    id = string "gameId" json;
    status = status_of_int (int "gameStatus" json);
    status_text = String.trim (string "gameStatusText" json);
    period = int "period" json;
    home = team (field "homeTeam" json);
    away = team (field "awayTeam" json);
  }

let of_json json =
  let board = field "scoreboard" json in
  { date = string "gameDate" board; games = List.map game (list "games" board) }

let of_string s =
  match Yojson.Safe.from_string s with
  | json -> of_json json
  | exception Yojson.Json_error msg -> fail "Scoreboard: invalid JSON: %s" msg
