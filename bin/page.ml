open Pure_html
open HTML

(* Style the existing text, rather than rebuilding its spacing in HTML. Copying
   the <pre> still gives the original ASCII, without hidden padding or labels. *)
let ascii text =
  let rule text = span [class_ "ascii-rule"] [txt "%s" text] in
  let rec lines index after_rule = function
    | [] -> []
    | line :: rest ->
        let is_rule = String.starts_with ~prefix:"+" line in
        let nodes =
          if index = 0 then [span [class_ "ascii-heading"] [txt "%s" line]]
          else if is_rule then [rule line]
          else if String.length line >= 2 && String.starts_with ~prefix:"|" line
                  && String.ends_with ~suffix:"|" line then
            let content = String.sub line 1 (String.length line - 2) in
            [rule "|";
             span (if after_rule then [class_ "ascii-label"] else []) [txt "%s" content];
             rule "|"]
          else [txt "%s" line]
        in
        nodes @ (if rest = [] then [] else [txt "\n"])
        @ lines (index + 1) is_rule rest
  in
  lines 0 false (String.split_on_char '\n' text)

let document_nodes (document : Nbascii.Render.document) =
  let tone_class = function
    | Nbascii.Render.Plain -> "ascii-text"
    | Heading -> "ascii-heading"
    | Label -> "ascii-label"
    | Muted -> "ascii-muted"
    | Positive -> "ascii-positive"
    | Negative -> "ascii-negative"
    | Live -> "ascii-live"
    | Value -> "ascii-value"
  in
  List.concat (List.mapi (fun i line ->
    (if i = 0 then [] else [txt "\n"])
    @ List.map (fun (s : Nbascii.Render.span) ->
      span [class_ "%s" (tone_class s.tone)] [txt "%s" s.text]) line) document)

let layout ?refresh ~path nodes =
  let nav_link url label =
    let attrs = if path = url then [href "%s" url; Aria.current `page] else [href "%s" url] in
    a attrs [txt "%s" label]
  in
  html [lang "en"] [
    head [] [
      meta [charset "utf-8"];
      meta [name "viewport"; content "width=device-width, initial-scale=1"];
      (match refresh with
       | Some seconds -> meta [http_equiv `refresh; content "%d" seconds]
       | None -> null []);
      title [] "nbascii";
      link [rel "stylesheet"; href "/static/main.css"];
      link [rel "preconnect"; href "https://fonts.googleapis.com/"];
      link [rel "preconnect"; href "https://fonts.gstatic.com/"; crossorigin `anonymous];
      link [href "https://fonts.googleapis.com/css2?family=Courier+Prime:wght@400;700&display=swap"; rel "stylesheet"];
    ];
    body [] [
      div [] [
        nav [Aria.label "NBA pages"] [
          nav_link "/" "Today"; txt " | ";
          nav_link "/yesterday" "Yesterday"; txt " | ";
          nav_link "/standings" "Standings"; txt " | ";
          nav_link "/stats" "Stats";
        ];
        pre [] nodes;
      ];
    ];
  ]

let render ~path text = layout ~path (ascii text)
let render_document ?refresh ~path document = layout ?refresh ~path (document_nodes document)
