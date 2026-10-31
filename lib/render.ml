open Scoreboard

let period_label n = if n <= 4 then string_of_int n else if n = 5 then "OT" else Printf.sprintf "%dOT" (n - 4)
let cell s = Printf.sprintf "%4s" s
let record t = Printf.sprintf "%d-%d" t.wins t.losses

(* Live games carry zeroes for periods not played yet, so only show those
   reached so far. *)
let periods_played (g : game) =
  match g.status with
  | Scheduled -> 0
  | Live | Final ->
      min g.period (min (List.length g.home.periods) (List.length g.away.periods))

let take n l = List.filteri (fun i _ -> i < n) l

let team_line (g : game) (t : team) ~opponent =
  let played = periods_played g in
  let scores = take played t.periods |> List.map (fun n -> cell (string_of_int n)) in
  let total, marker =
    match g.status with
    | Scheduled -> ("", "")
    | Live -> (string_of_int t.score, "")
    | Final -> (string_of_int t.score, if t.score > opponent.score then " <" else "")
  in
  Printf.sprintf "%-3s %7s%s %5s%s" t.tricode (record t) (String.concat "" scores) total marker

let header_line (g : game) =
  let played = periods_played g in
  let labels = List.init played (fun i -> cell (period_label (i + 1))) in
  if played = 0 then None
  else Some (Printf.sprintf "%-3s %7s%s %5s" "" "" (String.concat "" labels) "T")

let box lines =
  let width = List.fold_left (fun w l -> max w (String.length l)) 0 lines in
  let border = "+" ^ String.make (width + 2) '-' ^ "+" in
  let pad l = "| " ^ l ^ String.make (width - String.length l) ' ' ^ " |" in
  (border :: List.map pad lines) @ [ border ]

let game (g : game) =
  let lines =
    [ g.status_text ]
    @ Option.to_list (header_line g)
    @ [ team_line g g.away ~opponent:g.home; team_line g g.home ~opponent:g.away ]
  in
  box lines

let scoreboard (t : Scoreboard.t) =
  let heading = Printf.sprintf "NBA SCORES  %s" t.date in
  let body =
    match t.games with
    | [] -> [ "No games today." ]
    | games -> List.concat_map (fun g -> game g @ [ "" ]) games
  in
  String.concat "\n" (heading :: "" :: body)
