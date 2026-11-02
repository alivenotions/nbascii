open Scoreboard

type tone = Plain | Heading | Label | Muted | Positive | Negative | Live | Value
type span = { text : string; tone : tone }
type document = span list list

let span ?(tone = Plain) text = { text; tone }
let line_text line = String.concat "" (List.map (fun s -> s.text) line)
let to_text document = String.concat "\n" (List.map line_text document)
let title text = [span ~tone:Heading text]
let rule width = [span ~tone:Muted (String.make width '-')]
let period_label n =
  if n <= 4 then string_of_int n
  else if n = 5 then "OT"
  else Printf.sprintf "%dOT" (n - 4)

(* Only include periods reached so far, not future zero-filled quarters. *)
let periods_played (g : game) =
  match g.status with
  | Scheduled -> 0
  | Live | Final ->
      min g.period (min (List.length g.home.periods) (List.length g.away.periods))

let take n l = List.filteri (fun i _ -> i < n) l

let game_document (g : game) =
  let played = periods_played g in
  let team_line (t : team) ~opponent =
    let winner = g.status = Final && t.score > opponent.score in
    let team_tone = if winner then Positive else Label in
    let record = Printf.sprintf "%d-%d" t.wins t.losses in
    let base = [span ~tone:team_tone (Printf.sprintf "%-4s" t.tricode);
                span ~tone:Muted (Printf.sprintf "%6s" record)] in
    if g.status = Scheduled then base
    else
      base
      @ (take played t.periods |> List.map (fun n -> span (Printf.sprintf "%3d" n)))
      @ [span ~tone:(if winner then Positive else Value) (Printf.sprintf " %4d" t.score)]
      @ (if winner then [span ~tone:Positive " <"] else [])
  in
  let status =
    match g.status with
    | Live -> [span ~tone:Live ("LIVE  " ^ g.status_text)]
    | Final -> [span ~tone:Muted g.status_text]
    | Scheduled -> [span ~tone:Label g.status_text]
  in
  let columns =
    if g.status = Scheduled then []
    else [[span ~tone:Muted (Printf.sprintf "%-4s%6s" "TEAM" "W-L")]
          @ List.init played (fun i -> span ~tone:Muted (Printf.sprintf "%3s" (period_label (i + 1))))
          @ [span ~tone:Muted (Printf.sprintf " %4s" "TOT")]]
  in
  [status] @ columns @ [team_line g.away ~opponent:g.home; team_line g.home ~opponent:g.away]

let sections sections =
  List.concat (List.mapi (fun i section -> if i = 0 then section else [] :: section) sections)

let scoreboard_document (t : Scoreboard.t) =
  [title (Printf.sprintf "NBA SCORES  %s" t.date); []]
  @ (match t.games with
     | [] -> [[span ~tone:Muted "No games today."]]
     | games -> sections (List.map game_document games))

let standings_document (t : Standings.t) =
  let conference (c : Standings.conference) =
    let header = Printf.sprintf "%2s %-4s %2s %2s %5s %4s %4s" "#" "TEAM" "W" "L" "PCT" "GB" "STRK" in
    let rows = List.map (fun (e : Standings.entry) ->
      let streak_tone =
        if String.starts_with ~prefix:"W" e.streak then Positive
        else if String.starts_with ~prefix:"L" e.streak then Negative
        else Muted
      in
      [span ~tone:Muted (Printf.sprintf "%2d " e.seed);
       span ~tone:Label (Printf.sprintf "%-4s" e.team);
       span (Printf.sprintf " %2s %2s" e.wins e.losses);
       span ~tone:Value (Printf.sprintf " %5s" e.percentage);
       span ~tone:Muted (Printf.sprintf " %4s " e.behind);
       span ~tone:streak_tone (Printf.sprintf "%4s" e.streak)]) c.entries
    in
    [title c.name; [span ~tone:Muted header]; rule (String.length header)]
    @ (if rows = [] then [[span ~tone:Muted "No standings available."]] else rows)
  in
  [title (Printf.sprintf "NBA STANDINGS  %s" t.season); []]
  @ (if t.conferences = [] then [[span ~tone:Muted "No standings available."]]
     else sections (List.map conference t.conferences))

let leaders_document (t : Leaders.t) =
  let category (c : Leaders.category) =
    let width = List.fold_left (fun n (p : Leaders.player) -> max n (String.length p.name)) 6 c.players in
    let header = Printf.sprintf "%-*s %-4s %5s" width "PLAYER" "TEAM" c.abbreviation in
    let rows = List.map (fun (p : Leaders.player) ->
      [span ~tone:Label (Printf.sprintf "%-*s" width p.name);
       span ~tone:Muted (Printf.sprintf " %-4s" p.team);
       span ~tone:Value (Printf.sprintf " %5s" p.value)]) c.players
    in
    [title c.name; [span ~tone:Muted header]; rule (String.length header)]
    @ (if rows = [] then [[span ~tone:Muted "No leaders available."]] else rows)
  in
  [title (Printf.sprintf "NBA SEASON LEADERS  %s" t.season); []]
  @ sections (List.map category t.categories)

let game g = List.map line_text (game_document g)
let scoreboard t = to_text (scoreboard_document t)
let standings t = to_text (standings_document t)
let leaders t = to_text (leaders_document t)

let stale_note ~age =
  let age =
    if age < 60. then Printf.sprintf "%.0f s" age
    else if age < 3600. then Printf.sprintf "%.0f min" (age /. 60.)
    else Printf.sprintf "%.0f h" (age /. 3600.)
  in
  Printf.sprintf "Showing data from %s ago; ESPN isn't responding." age

let with_note note = function
  | [] -> [ [ { text = note; tone = Muted } ] ]
  | heading :: rest -> heading :: [ { text = note; tone = Muted } ] :: rest
