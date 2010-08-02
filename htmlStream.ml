(** Stream of html elements *)

open Control
open Printf
open Prelude
open ExtLib

let log = Log.from "html"

module Stream = ExtStream

type elem = Tag of (string * (string*string) list) | Text of string | Close of string

module Parser = struct 

let eq : char -> char -> bool = (=)
let neq : char -> char -> bool = (<>)
let is_alpha = function 
  | 'a'..'z' | 'A'..'Z' | '0'..'9' -> true 
  | _ -> false
let is_ws = function
  | c when Char.code c <= 32 -> true
  | _ -> false

exception EndTag

let label = String.lowercase

(** parse stream of characters @return stream of html elements *)
let rec parse = parser
  | [< ''<'; x = tag; t >] -> [< 'x; parse t >]
  | [< 'c; x = chars c (neq '<'); t >] -> [< 'Text x; parse t >]
  | [< >] -> [< >]
  and tag = parser
  | [< 'c when is_alpha c; name = chars c is_alpha; () = skip is_ws; a=tag_attrs [] >] -> Tag (label name,List.rev a)
  | [< ''/'; () = skip is_ws; x = close_tag >] -> Close (label x)
  | [< t >] -> skip_till '>' t; Tag ("",[]) (* skip garbage *)
  and close_tag = parser
  | [< 'c when is_alpha c; name = chars c is_alpha; () = skip_till '>' >] -> name
  | [< t >] -> skip_till '>' t; ""
  and tag_attrs a = parser
  | [< ''>' >] -> a
  | [< 'c when is_alpha c; name = chars c is_alpha; () = skip is_ws; t >] ->
    begin match try Some (maybe_value t) with EndTag -> None with
    | Some v -> skip is_ws t; tag_attrs ((label name,v) :: a) t
    | None -> (label name,"") :: a
    end
  | [< t >] -> skip_till '>' t; a (* skip garbage *)
  and maybe_value = parser
  | [< ''>' >] -> raise EndTag
  | [< ''='; () = skip is_ws; t >] -> parse_value t
  | [< >] -> ""
  and parse_value = parser
  | [< ''\''; s = till '\'' >] -> s
  | [< ''"'; s = till '"' >] -> s
  | [< ''>' >] -> raise EndTag
  | [< 'c when is_alpha c; s = chars c is_alpha >] -> s
  | [< t >] -> skip_till '>' t; raise EndTag (* skip garbage *)
  (** @return all that match [f] *)
  and chars c f strm =
    let b = Buffer.create 10 in
    Buffer.add_char b c;
    let rec loop () =
      match Stream.peek strm with
      | Some c when f c -> Stream.junk strm; Buffer.add_char b c; loop ()
      | None -> Buffer.contents b
      | _ -> Buffer.contents b 
    in loop ()
  (** @return everything till [delim] (consumed but not included) *)
  and till delim strm =
    let b = Buffer.create 10 in
    let rec loop () =
      let c = Stream.next strm in
      if c = delim then () else (Buffer.add_char b c; loop ())
    in 
    begin try loop () with Stream.Failure -> () end;
    Buffer.contents b
  (** skip all that match [f] *)
  and skip f = parser
  | [< 'c when f c; t >] -> skip f t
  | [< >] -> ()
  (** skip all till [delim] (including) *)
  and skip_till delim strm =
    if try Stream.next strm = delim with Stream.Failure -> true then () else skip_till delim strm

end (* Parser *)

(** convert char stream to html elements stream.
  Names (tags and attributes) are lowercased *)
let parse s = try Parser.parse s with exn -> log #warn ~exn "HtmlStream.parse"; [< >]

(* open Printf *)

let quote =
  let rex = Pcre.regexp "['\"&]" in
  Pcre.substitute ~rex ~subst:(function "'" -> "&apos;" | "\"" -> "&quot;" | "&" -> "&amp;" | _ -> assert false)

let show c elem = 
  match elem with
  | Tag (name,attrs) ->
    wrapped_output (IO.output_string ()) begin fun out ->
      IO.printf out "<%s" name; 
      List.iter (fun (k,v) -> IO.printf out " %s=%c%s%c" k c (quote v) c) attrs;
      IO.printf out ">"
    end
  | Text t -> t
  | Close name -> sprintf "</%s>" name

let show' = show '\''
let show = show '"'

let rec show_stream = parser
  | [< 'c; t >] -> Printf.printf "-> %c\n%!" c; [< 'c; show_stream t >]
  | [< >] -> [< >] 

let dump = Stream.iter (print_endline $ show) $ parse $ 
(*   show_stream $ *)
  Stream.of_string

let tag name ?(a=[]) = function
  | Tag (name',attrs) when name = name' ->
    let attrs = List.map (fun (k,v) -> (k,String.nsplit v " ")) attrs in
    begin try List.for_all (fun (k,v) -> assert (not & String.contains v ' '); List.mem v (List.assoc k attrs)) a with Not_found -> false end
  | _ -> false

let close name = function Close name' when name = name' -> true | _ -> false 

let to_text = function
  | Tag _ -> None
  | Text x -> Some x
  | Close _ -> None

(** extract text from the list elements *)
let make_text l = wrapped_outs (fun out -> List.iter (Option.may (IO.nwrite out) $ to_text) l)
