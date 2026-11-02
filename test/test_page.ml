let check name cond = if not cond then failwith ("FAIL: " ^ name)

let contains text part =
  let n = String.length part in
  let rec loop i =
    i + n <= String.length text && (String.sub text i n = part || loop (i + 1))
  in
  loop 0

let html path text = Nbascii_web.Page.render ~path text |> Pure_html.to_string

let pre_content html =
  let start = ref 0 in
  while String.sub html !start 5 <> "<pre>" do incr start done;
  let stop = ref (!start + 5) in
  while String.sub html !stop 6 <> "</pre>" do incr stop done;
  String.sub html (!start + 5) (!stop - !start - 5)

let strip_tags html =
  let output = Buffer.create (String.length html) in
  let in_tag = ref false in
  String.iter (function
    | '<' -> in_tag := true
    | '>' -> in_tag := false
    | c when not !in_tag -> Buffer.add_char output c
    | _ -> ()) html;
  Buffer.contents output

let read path = In_channel.with_open_bin path In_channel.input_all

let test_semantic_colors () =
  let open Nbascii.Render in
  let board = Nbascii.Scoreboard.of_string (read "scoreboard.json") in
  let standings = Nbascii.Standings.of_string (read "standings.json") in
  let leaders = Nbascii.Leaders.of_string (read "leaders.json") in
  let documents = [scoreboard_document board; standings_document standings; leaders_document leaders] in
  List.iter (fun document ->
    let page = Nbascii_web.Page.render_document ~path:"/" document |> Pure_html.to_string in
    let expected = Pure_html.to_string (Pure_html.txt "%s" (to_text document)) in
    check "semantic spans preserve ASCII" (strip_tags (pre_content page) = expected)) documents;
  let spans = List.concat (standings_document standings) in
  check "winning streak is green"
    (List.exists (fun s -> String.trim s.text = "W4" && s.tone = Positive) spans);
  check "losing streak is red"
    (List.exists (fun s -> String.trim s.text = "L1" && s.tone = Negative) spans);
  check "column headings subdued"
    (List.exists (fun s -> contains s.text "STRK" && s.tone = Muted) spans);
  let final = List.hd board.games and live = List.nth board.games 1 in
  let final_spans = List.concat (game_document final) in
  check "winner team highlighted"
    (List.exists (fun s -> String.trim s.text = "CLE" && s.tone = Positive) final_spans);
  check "loser not highlighted as winner"
    (not (List.exists (fun s -> String.trim s.text = "NYK" && s.tone = Positive) final_spans));
  let live_spans = List.concat (game_document live) in
  check "live status amber" (List.exists (fun s -> s.tone = Live && contains s.text "LIVE") live_spans);
  check "live leader not yet a winner" (not (List.exists (fun s -> s.tone = Positive) live_spans));
  let page = Nbascii_web.Page.render_document ~path:"/standings" (standings_document standings)
    |> Pure_html.to_string in
  check "positive CSS hook" (contains page "class=\"ascii-positive\"");
  check "negative CSS hook" (contains page "class=\"ascii-negative\"");
  let injected = [[{text="<script>&"; tone=Positive}]] in
  let page = Nbascii_web.Page.render_document ~path:"/" injected |> Pure_html.to_string in
  check "semantic text escaped" (contains page "&lt;script&gt;&amp;")

let () =
  test_semantic_colors ();
  let text = "NBA SCORES  2026-11-01\n\n+----------+\n| Final    |\n| BOS  100 |\n+----------+\n" in
  let page = html "/" text in
  check "ASCII spacing unchanged" (strip_tags (pre_content page) = text);
  List.iter (fun class_name ->
    check class_name (contains page ("class=\"" ^ class_name ^ "\"")))
    ["ascii-heading"; "ascii-label"; "ascii-rule"];
  List.iter (fun path ->
    let page = html path text in
    check ("active page " ^ path)
      (contains page ("href=\"" ^ path ^ "\"\naria-current=\"page\""));
    List.iter (fun other ->
      if path <> other then check ("inactive page " ^ other)
        (not (contains page ("href=\"" ^ other ^ "\"\naria-current=\"page\""))))
      ["/"; "/yesterday"; "/standings"; "/stats"])
    ["/"; "/yesterday"; "/standings"; "/stats"];
  let unsafe = html "/stats" "<script>alert(1)</script>\n+--+\n| <b>& |" in
  check "heading escaped" (contains unsafe "&lt;script&gt;alert(1)&lt;/script&gt;");
  check "row escaped" (contains unsafe "&lt;b&gt;&amp;");
  check "no injected script" (not (contains unsafe "<script>"));
  check "empty content" (strip_tags (pre_content (html "/" "")) = "");
  check "stylesheet absolute path" (contains page "href=\"/static/main.css\"");
  print_endline "page tests passed"
