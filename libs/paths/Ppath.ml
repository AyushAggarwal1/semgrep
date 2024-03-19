(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(*
   Abstract type for a file path within a project

   The name of the module imitates Fpath.ml, but use Ppath.ml for
   Project path (instead of File path).

   !!! The tests for this module are in the git_wrapper library because
   they depend on git.
   TODO: create a 'project' library that depends both on 'git_wrapper'
   and 'paths'?
*)

open Common
open Fpath_.Operators

(*****************************************************************************)
(* Types *)
(*****************************************************************************)

(*
   Type to represent an *absolute*, *normalized* path relative to a project
   root. This is purely syntactic. For example,

     in_project ~root:(Fpath.v "/a") (Fpath.v "/a/b/c")

   will return { segments = [""; "b"; "c"]; string = "/b/c"; }
 *)
type t = {
  (* Path segments within the project root.
   * Invariants:
     - the first element of the list should always be "",
       because all ppaths are absolute paths.
     - no segment may be "." or "..".
     - no segment may contain a "/".
   *)
  segments : string list;
  (* String.concat "/" segments
   * TODO: get rid of it? just compute it dynamically?
   *)
  string : string;
}

(* old: was of_string_for_tests "/" *)
let root = { string = "/"; segments = [ ""; "" ] }

(*****************************************************************************)
(* Accessors *)
(*****************************************************************************)

(* Useful to debug, to use in error messages, or when passing the ppath
 * to a regexp matcher (e.g., Glob.Match.run()).
 * However, you should prefer to_fpath() most of the time, and then
 * Fpath.to_string() if needed.
 *)
let to_string x = x.string

(* TODO: make a rel_segments function so the caller does not have to do
   let rel_segments =
      match Ppath.segments full_git_path with
      | "" :: xs -> xs
      | __else__ -> assert false
    in
*)

let segments x = x.segments

(*****************************************************************************)
(* Builder helpers (not exposed in Ppath.mli) *)
(*****************************************************************************)

let rec normalize_aux (xs : string list) : string list =
  match xs with
  | ".." :: xs -> ".." :: normalize_aux xs
  | [ "" ] as xs (* preserve trailing slash *) -> xs
  | ("." | "") :: xs -> normalize_aux xs
  | _ :: ".." :: xs -> normalize_aux xs
  | x :: xs as orig ->
      let res = normalize_aux xs in
      (* If nothing changes via normalization, return the original list *)
      if Stdlib.( == ) res xs then orig
      else (* Something changed, make another pass *)
        normalize_aux (x :: res)
  | [] -> []

let normalize_segments (segments : string list) =
  match segments with
  | "" :: xs -> (
      match normalize_aux xs with
      | ".." :: _ -> invalid_arg ("invalid ppath: " ^ String.concat "/" segments)
      | [] -> [ ""; "" ]
      | segments -> "" :: segments)
  | _ ->
      invalid_arg
        ("Ppath.create: not an absolute ppath: " ^ String.concat "/" segments)

let check_normalized_segment str =
  if String.contains str '/' then
    invalid_arg ("Ppath.create: path segment may not contain a slash: " ^ str)
  else
    match str with
    | ""
    | "."
    | ".." ->
        invalid_arg ("Ppath.create: unsupported path segment: " ^ str)
    | _ -> ()

let check_normalized_segments segments =
  let rec iter segs =
    match segs with
    | [ "" ] (* trailing slash *) -> ()
    | seg :: segs ->
        check_normalized_segment seg;
        iter segs
    | [] -> ()
  in
  match segments with
  | []
  | [ _ ] ->
      invalid_arg
        ("Ppath.create: ppath should have at least 2 segments: "
       ^ String.concat "/" segments)
  | "" :: segs -> iter segs
  | _ ->
      invalid_arg
        ("Ppath.create: ppath must be absolute (start with '/'): "
       ^ String.concat "/" segments)

let unsafe_create segments = { string = String.concat "/" segments; segments }

let create segments =
  let norm_segments = normalize_segments segments in
  Printf.printf "normalize_segments %S -> %S\n%!"
    (String.concat "|" segments)
    (String.concat "|" norm_segments);
  check_normalized_segments norm_segments;
  unsafe_create norm_segments

(*****************************************************************************)
(* Append *)
(*****************************************************************************)

let append_segment xs x =
  let rec loop xs =
    match xs with
    | [] -> [ x ]
    | [ "" ] -> (* ignore trailing slash that's not a leading slash *) [ x ]
    | x :: xs -> x :: loop xs
  in
  match xs with
  | "" :: xs -> "" :: loop xs
  (* TODO: this case should not happen anymore now *)
  | xs -> loop xs

(* use same terminology as in Fpath *)
let add_seg path seg =
  check_normalized_segment seg;
  let segments = append_segment path.segments seg in
  unsafe_create segments

(* saving you 3 neurons *)
let add_segs (path : t) segs = List.fold_left add_seg path segs

let append_fpath (path : t) fpath =
  match Fpath.segs fpath with
  | "" :: _ ->
      invalid_arg
        ("Ppath.append_fpath: not a relative path: " ^ Fpath.to_string fpath)
  | segs -> add_segs path segs

module Operators = struct
  let ( / ) = add_seg
end

(*****************************************************************************)
(* Export *)
(*****************************************************************************)

let to_fpath ~root path =
  match path.segments with
  | "" :: segments ->
      List.fold_left Fpath.add_seg root segments
      |> (* remove leading "./" typically occuring when the project root
            is "." *)
      Fpath.normalize
  | _ -> assert false

let relativize ~root:orig_root orig_ppath =
  let rec aux root ppath =
    match (root, ppath) with
    | [ "" ], [ "" ] -> Fpath.v "."
    | [], [ "" ] -> (* no trailing slash is necessary *) Fpath.v "."
    | [], segs -> Fpath_.of_relative_segments segs
    | [ "" ], [] -> (* tolerate "/foo/" vs "/foo" *) Fpath.v "."
    | _ :: _, [] ->
        invalid_arg
          (spf "Ppath.relativize: %S is shorter than %S" orig_root.string
             orig_ppath.string)
    | x :: xs, y :: ys ->
        if x = y then aux xs ys
        else
          invalid_arg
            (spf "Ppath.relativize: %S is not a prefix of %S" orig_root.string
               orig_ppath.string)
  in
  aux orig_root.segments orig_ppath.segments

(*****************************************************************************)
(* Project Builder *)
(*****************************************************************************)

(*
   Prepend "./" to relative paths so as to make "." a prefix.
*)
let make_matchable_relative_path path =
  match Fpath.segs path with
  | "" :: _ -> (* absolute *) path
  | "." :: _ -> (* keep as is *) path
  | _rel -> Fpath.v "." // path

(*
   This is a collection of fixes on top of Fpath.rem_prefix to make it
   work as a user would expect.

   if 'root' is a parent of 'path', then return the relative path
   to go from the root to that path:

     (/a, /a/b) -> b

   We try to make it work even if the root string is not a string prefix
   of the path e.g.

     (., a) -> a
     (./a, a/b) -> b
     (a, ./a/b) -> b

   This returns a relative path.

   TODO: Move to File module?
*)
let remove_prefix root path =
  let had_a_trailing_slash = Fpath.is_dir_path path in
  (* normalize paths syntactically e.g. "./a/b/c/.." -> "a/b"
     to allow matching *)
  let root = Fpath.normalize root in
  let path = Fpath.normalize path in
  (* prepend "./" to relative paths in case one of the paths is "." *)
  let root = make_matchable_relative_path root in
  let path = make_matchable_relative_path path in
  (* add a trailing slash as required by Fpath.rem_prefix (why?) *)
  let path = Fpath.to_dir_path path in
  (* now we can call this function to remove the root prefix from path *)
  match Fpath.rem_prefix root path with
  | None -> if Fpath.equal root path then Some (Fpath.v ".") else None
  | Some rel_path ->
      (* remove the trailing slash if we added one *)
      let rel_path =
        if not had_a_trailing_slash then Fpath.rem_empty_seg rel_path
        else rel_path
      in
      Some rel_path

(*****************************************************************************)
(* Builder entry points *)
(*****************************************************************************)

(*
   Make a path absolute, using getcwd() if needed.
   I hesitated to put this into Fpath_ since Fpath is purely syntactic.
*)
let make_absolute path =
  if Fpath.is_rel path then Fpath.(v (Unix.getcwd ()) // path)
  else (* save a syscall *)
    path

let of_relative_fpath (fpath : Fpath.t) =
  if Fpath.is_rel fpath then create ("" :: Fpath.segs fpath)
  else invalid_arg ("Ppath.of_relative_fpath: " ^ Fpath.to_string fpath)

(*
   This assumes the input paths are normalized. We use this
   in tests to avoid having to create actual files.
*)
let in_project_unsafe_for_tests ~(phys_root : Fpath.t) (path : Fpath.t) =
  let abs_path = make_absolute path in
  match remove_prefix phys_root abs_path with
  | None ->
      Error
        (Common.spf
           "cannot make path %S relative to project root %S.\n\
            cwd: %s\n\
            realpath for .: %s\n\
            Sys.argv: %s" !!path !!phys_root (Sys.getcwd ())
           (Rfpath.of_string_exn "." |> Rfpath.show)
           (Sys.argv |> Array.to_list |> String.concat " "))
  | Some rel_path -> Ok (of_relative_fpath rel_path)

let in_project ~(root : Rfpath.t) (path : Fpath.t) =
  in_project_unsafe_for_tests ~phys_root:(root.rpath |> Rpath.to_fpath) path

(*****************************************************************************)
(* Tests helpers *)
(*****************************************************************************)

let of_string_for_tests string = create (String.split_on_char '/' string)
