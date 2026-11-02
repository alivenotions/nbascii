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

(* ESPN uses strings for totals and numbers for per-period scores. *)
let int name json =
  match field name json with
  | `Int n -> n
  | `Float f -> int_of_float f
  | `String s -> (
      match int_of_string_opt s with
      | Some n -> n
      | None -> fail "Scoreboard: %S is not a number" name)
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

let status_of_state = function
  | "pre" -> Scheduled
  | "in" -> Live
  | "post" -> Final
  | s -> fail "Scoreboard: unknown game state %S" s

let record json =
  match List.find_opt (fun r -> string "type" r = "total") (list "records" json) with
  | None -> (0, 0)
  | Some r -> (
      match String.split_on_char '-' (string "summary" r) with
      | [ wins; losses ] -> (
          match (int_of_string_opt wins, int_of_string_opt losses) with
          | Some w, Some l -> (w, l)
          | _ -> fail "Scoreboard: invalid team record")
      | _ -> fail "Scoreboard: invalid team record")

let team competitor =
  let json = field "team" competitor in
  let wins, losses = record competitor in
  {
    tricode = Espn_json.tricode (string "abbreviation" json);
    city = string "location" json;
    name = string "name" json;
    wins;
    losses;
    score = int "score" competitor;
    periods = List.map (int "value") (list "linescores" competitor);
  }

let game json =
  let status = field "status" json in
  let status_type = field "type" status in
  let state = status_of_state (string "state" status_type) in
  let competition =
    match list "competitions" json with
    | [ c ] -> c
    | _ -> fail "Scoreboard: expected one competition per NBA game"
  in
  let competitors = list "competitors" competition in
  let side side =
    match List.filter (fun c -> string "homeAway" c = side) competitors with
    | [ c ] -> team c
    | _ -> fail "Scoreboard: expected one %s team" side
  in
  {
    id = string "id" json;
    status = state;
    status_text = String.trim (string "shortDetail" status_type);
    period = int "period" status;
    home = side "home";
    away = side "away";
  }

let of_json ?date json =
  let date = match date with Some d -> d | None -> string "date" (field "day" json) in
  if date = "" then fail "Scoreboard: missing scoreboard date";
  let events =
    match field "events" json with
    | `List events -> events
    | _ -> fail "Scoreboard: expected an events list"
  in
  { date; games = List.map game events }

let of_string ?date s =
  match Yojson.Safe.from_string s with
  | json -> of_json ?date json
  | exception Yojson.Json_error msg -> fail "Scoreboard: invalid JSON: %s" msg

let finished t = List.for_all (fun g -> g.status = Final) t.games
let live t = List.exists (fun g -> g.status = Live) t.games
