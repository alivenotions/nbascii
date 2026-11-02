let fail fmt = Printf.ksprintf failwith fmt

let field name = function
  | `Assoc fields -> Option.value (List.assoc_opt name fields) ~default:`Null
  | _ -> fail "ESPN: expected an object around %S" name

let string name json =
  match field name json with
  | `String s when s <> "" -> s
  | _ -> fail "ESPN: expected a nonempty string for %S" name

let list name json =
  match field name json with
  | `List items -> items
  | _ -> fail "ESPN: expected a list for %S" name

let number name json =
  match field name json with
  | `Int n -> float_of_int n
  | `Float f when Float.is_finite f -> f
  | _ -> fail "ESPN: expected a number for %S" name

let parse of_json s =
  match Yojson.Safe.from_string s with
  | json -> of_json json
  | exception Yojson.Json_error msg -> fail "ESPN: invalid JSON: %s" msg

let tricode = function
  | "GS" -> "GSW"
  | "NY" -> "NYK"
  | "SA" -> "SAS"
  | "NO" -> "NOP"
  | "UTAH" -> "UTA"
  | "WSH" -> "WAS"
  | s -> s
