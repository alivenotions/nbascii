type entry = {
  seed : int;
  team : string;
  wins : string;
  losses : string;
  percentage : string;
  behind : string;
  streak : string;
}

type conference = { name : string; entries : entry list }
type t = { season : string; conferences : conference list }

let entry json =
  let open Espn_json in
  let stats = list "stats" json in
  let stat name =
    match List.find_opt (fun s -> string "name" s = name) stats with
    | Some s -> s
    | None -> failwith ("Standings: missing stat " ^ name)
  in
  {
    seed = int_of_float (number "value" (stat "playoffSeed"));
    team = tricode (string "abbreviation" (field "team" json));
    wins = string "displayValue" (stat "wins");
    losses = string "displayValue" (stat "losses");
    percentage = string "displayValue" (stat "winPercent");
    behind = string "displayValue" (stat "gamesBehind");
    streak = string "displayValue" (stat "streak");
  }

let of_json json =
  let open Espn_json in
  let conferences =
    list "children" json |> List.map (fun c ->
      let entries = list "entries" (field "standings" c) |> List.map entry in
      { name = string "name" c;
        entries = List.stable_sort (fun a b -> Int.compare a.seed b.seed) entries })
  in
  { season = string "displayName" (field "season" json); conferences }

let of_string = Espn_json.parse of_json
