let check name cond = if not cond then failwith ("FAIL: " ^ name)
let read path = In_channel.with_open_bin path In_channel.input_all
let contains text sub =
  let n = String.length sub in
  let rec loop i =
    i + n <= String.length text && (String.sub text i n = sub || loop (i + 1))
  in loop 0

let fails f = match f () with _ -> false | exception Failure _ -> true
let invalid f = match f () with _ -> false | exception Invalid_argument _ -> true

let replace name value = function
  | `Assoc fields -> `Assoc ((name, value) :: List.remove_assoc name fields)
  | _ -> assert false

let aligned_tables text =
  let width = ref None in
  String.split_on_char '\n' text |> List.for_all (fun line ->
    if line = "" then (width := None; true)
    else if String.for_all ((=) '-') line then (width := Some (String.length line); true)
    else match !width with None -> true | Some n -> String.length line = n)

let test_dates () =
  let open Nbascii.Score_date in
  List.iter (fun (date, expected) -> check date (previous date = expected))
    [ "2026-11-01", "2026-10-31";
      "2027-01-01", "2026-12-31";
      "2024-03-01", "2024-02-29";
      "2024-02-29", "2024-02-28";
      "2026-03-01", "2026-02-28";
      "2000-03-01", "2000-02-29";
      "2100-03-01", "2100-02-28" ];
  List.iter (fun date -> check ("invalid date " ^ date) (invalid (fun () -> previous date)))
    ["2026-02-29"; "2026-13-01"; "2026-04-31"; "2026-1-01"; "nonsense"];
  check "query date" (espn_query "2026-10-31" = "20261031");
  check "dated scoreboard URL"
    (Uri.get_query_param (Nbascii.Espn_api.scoreboard_url_for_date "2026-10-31") "dates" = Some "20261031")

let test_dated_scores () =
  let json = Yojson.Safe.from_string (read "scoreboard.json") in
  let without_day = match json with
    | `Assoc fields -> `Assoc (List.remove_assoc "day" fields)
    | _ -> assert false
  in
  let board = Nbascii.Scoreboard.of_json ~date:"2026-10-30" without_day in
  check "dated feed without day" (board.date = "2026-10-30" && List.length board.games = 3);
  check "dated feed empty day"
    ((Nbascii.Scoreboard.of_string ~date:"2026-07-01" {|{"events":[]}|}).games = []);
  check "dated feed malformed"
    (fails (fun () -> Nbascii.Scoreboard.of_string ~date:"2026-07-01" {|{"error":"unavailable"}|}))

let test_standings () =
  let open Nbascii.Standings in
  let board = of_string (read "standings.json") in
  check "standings season" (board.season = "2026-27");
  let east = List.hd board.conferences in
  check "conference name" (east.name = "Eastern Conference");
  check "seed ordering" (List.map (fun e -> e.team) east.entries = ["BOS"; "NYK"]);
  let first = List.hd east.entries in
  check "standings stats"
    (first.wins = "4" && first.losses = "0" && first.percentage = "1.000"
     && first.behind = "-" && first.streak = "W4");
  check "west abbreviation" ((List.hd (List.nth board.conferences 1).entries).team = "GSW");
  let text = Nbascii.Render.standings board in
  check "standings heading" (contains text "NBA STANDINGS  2026-27");
  check "west rendered" (contains text "Western Conference");
  check "standings aligned" (aligned_tables text);
  check "compact standings" (List.for_all (fun l -> String.length l <= 30) (String.split_on_char '\n' text));
  check "standings invalid json" (fails (fun () -> of_string "{"));
  check "standings invalid shape" (fails (fun () -> of_string {|{"error":"unavailable"}|}));
  check "standings invalid entry" (fails (fun () -> of_string
    {|{"season":{"displayName":"2026-27"},"children":[{"name":"East","standings":{"entries":[{"team":{"abbreviation":"BOS"},"stats":[]}]}}]}|}));
  check "empty standings" (contains (Nbascii.Render.standings {season="2026-27"; conferences=[]}) "No standings available.")

let test_leaders () =
  let open Nbascii.Leaders in
  let json = Yojson.Safe.from_string (read "leaders.json") in
  let board = of_json json in
  check "leaders season" (board.season = "2026-27");
  check "category selection and order"
    (List.map (fun (c : category) -> c.abbreviation) board.categories = ["PTS"; "REB"; "AST"]);
  let points = List.hd board.categories in
  let first = List.hd points.players in
  check "leader name and average" (first.name = "Luka Doncic" && first.team = "LAL" && first.value = "36.2");
  check "leader abbreviation" ((List.nth points.players 1).team = "GSW");
  let text = Nbascii.Render.leaders board in
  check "leaders heading" (contains text "NBA SEASON LEADERS  2026-27");
  check "leaders aligned" (aligned_tables text);
  check "leaders invalid json" (fails (fun () -> of_string "{"));
  check "leaders invalid shape" (fails (fun () -> of_string {|{"error":"unavailable"}|}));
  let categories = Nbascii.Espn_json.list "categories" (Nbascii.Espn_json.field "leaders" json) in
  let with_categories categories =
    replace "leaders" (`Assoc ["categories", `List categories]) json
  in
  check "missing leader category" (fails (fun () -> of_json (with_categories [])));
  let empty = of_json (with_categories (List.map (replace "leaders" (`List [])) categories)) in
  check "empty leader lists" (contains (Nbascii.Render.leaders empty) "No leaders available.");
  let free_agent = `Assoc [
    "athlete", `Assoc ["displayName", `String "Free Agent"];
    "displayValue", `String "30.0"]
  in
  let no_team = of_json (with_categories (List.map (replace "leaders" (`List [free_agent])) categories)) in
  check "leader without a team" ((List.hd (List.hd no_team.categories).players).team = "---");
  let many = List.init 12 (fun _ -> free_agent) in
  let capped = of_json (with_categories (List.map (replace "leaders" (`List many)) categories)) in
  check "top ten leaders" (List.for_all (fun (c : category) -> List.length c.players = 10) capped.categories)

let () =
  test_dates ();
  test_dated_scores ();
  test_standings ();
  test_leaders ();
  print_endline "feed tests passed"
