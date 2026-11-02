(** Browser presentation of the plain-text ASCII renderers. *)
val render : path:string -> string -> Pure_html.node
(** Adds escaped color spans without changing the text or its spacing. *)

val render_document :
  ?refresh:int -> path:string -> Nbascii.Render.document -> Pure_html.node
(** Render model-derived semantic tones without guessing from text. With
    [refresh], the browser reloads the page after that many seconds. *)
