type player = { name : string; team : string; value : string }
type category = { name : string; abbreviation : string; players : player list }
type t = { season : string; categories : category list }

let of_json json =
  let open Espn_json in
  let categories = list "categories" (field "leaders" json) in
  let category key =
    let c =
      match List.find_opt (fun c -> string "name" c = key) categories with
      | Some c -> c
      | None -> failwith ("Leaders: missing category " ^ key)
    in
    let players = list "leaders" c |> List.filteri (fun i _ -> i < 10) |> List.map (fun p ->
      { name = string "displayName" (field "athlete" p);
        team = (match field "team" p with
          | `Null -> "---"
          | team -> tricode (string "abbreviation" team));
        value = string "displayValue" p })
    in
    { name = string "displayName" c; abbreviation = string "abbreviation" c; players }
  in
  { season = string "displayName" (field "requestedSeason" json);
    categories = List.map category ["pointsPerGame"; "reboundsPerGame"; "assistsPerGame"] }

let of_string = Espn_json.parse of_json
