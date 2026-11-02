let days_in_month year = function
  | 2 -> if year mod 400 = 0 || (year mod 4 = 0 && year mod 100 <> 0) then 29 else 28
  | 4 | 6 | 9 | 11 -> 30
  | _ -> 31

let parse date =
  let invalid () = invalid_arg "Score_date: expected a valid YYYY-MM-DD date" in
  if String.length date <> 10 then invalid ();
  match String.split_on_char '-' date with
  | [y; m; d] -> (
      match int_of_string_opt y, int_of_string_opt m, int_of_string_opt d with
      | Some y, Some m, Some d
        when y >= 1 && m >= 1 && m <= 12 && d >= 1 && d <= days_in_month y m
             && Printf.sprintf "%04d-%02d-%02d" y m d = date -> (y, m, d)
      | _ -> invalid ())
  | _ -> invalid ()

let previous date =
  let y, m, d = parse date in
  let y, m, d =
    if d > 1 then (y, m, d - 1)
    else if m > 1 then (y, m - 1, days_in_month y (m - 1))
    else if y > 1 then (y - 1, 12, 31)
    else invalid_arg "Score_date: no previous date"
  in
  Printf.sprintf "%04d-%02d-%02d" y m d

let espn_query date =
  let y, m, d = parse date in
  Printf.sprintf "%04d%02d%02d" y m d
