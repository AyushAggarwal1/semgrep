(* Yoann Padioleau
 *
 * Copyright (C) 2021 r2c
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation, with the
 * special exception on linking described in file LICENSE.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
 * LICENSE for more details.
 *)
open AST_scala
module G = AST_generic
module H = AST_generic_helpers

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(* AST_scala to AST_generic.
 *
 * See AST_generic.ml for more information.
 *
 * TODO:
 * - see TODO, especially generators, This/Super class, etc.
 * - Scala can have multiple parameter lists or argument lists. Right now
 *   In Call position we fold, but for the parameters we flatten.
 *)

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

let fake = G.fake
let fb = Tok.unsafe_fake_bracket
let id x = x
let v_string = id
let v_float = id
let v_bool = id
let v_list = List_.map
let v_option = Option.map

let cases_to_lambda lb cases : G.function_definition =
  let id = ("!hidden_scala_param!", lb) in
  let param = G.Param (G.param_of_id id) in
  let body =
    G.Switch (lb, Some (G.Cond (G.N (H.name_of_id id) |> G.e)), cases) |> G.s
  in
  {
    fkind = (G.BlockCases, lb);
    frettype = None;
    fparams = fb [ param ];
    fbody = G.FBStmt body;
  }

(*****************************************************************************)
(* Boilerplate *)
(*****************************************************************************)

(* generated by ocamltarzan with: camlp4o -o /tmp/yyy.ml -I pa/ pa_type_conv.cmo pa_visitor.cmo  pr_o.cmo /tmp/xxx.ml  *)

let v_tok v = v

let v_wrap _of_a (v1, v2) =
  let v1 = _of_a v1 and v2 = v_tok v2 in
  (v1, v2)

let v_bracket _of_a (v1, v2, v3) =
  let v1 = v_tok v1 and v2 = _of_a v2 and v3 = v_tok v3 in
  (v1, v2, v3)

let v_ident v = v_wrap v_string v
let v_op v = v_wrap v_string v
let v_varid v = v_wrap v_string v
let v_ident_or_wildcard v = v_ident v
let v_varid_or_wildcard v = v_ident v
let v_ident_or_this v = v_ident v
let v_dotted_ident v = v_list v_ident v
let v_qualified_ident v = v_dotted_ident v
let v_selectors v = v_dotted_ident v

let v_simple_ref = function
  | Id v1 ->
      let v1 = v_ident v1 in
      Either.Left v1
  | This (v1, v2) ->
      let _v1TODO = v_option v_ident v1 and v2 = v_tok v2 in
      Either.Right (G.IdSpecial (G.This, v2) |> G.e)
  | Super (v1, v2, v3, v4) ->
      let _v1TODO = v_option v_ident v1
      and v2 = v_tok v2
      and _v3TODO = v_option (v_bracket v_ident) v3
      and v4 = v_ident v4 in
      let fld = G.FN (G.Id (v4, G.empty_id_info ())) in
      Either.Right
        (G.DotAccess (G.IdSpecial (G.Super, v2) |> G.e, fake ".", fld) |> G.e)

(* TODO: should not use *)
let id_of_simple_ref = function
  | Id id -> id
  | This (_, t) -> ("this", t)
  | Super (_, t, _, _) -> ("super", t)

let v_path (v1, v2) =
  let v1 = v_simple_ref v1 and v2 = v_selectors v2 in
  (v1, v2)

let rec v_import_selector tk (path : G.dotted_ident) = function
  | NamedSelector x -> v_named_selector tk path x
  | WildCardSelector x -> v_wildcard_selector tk path x

and v_dotted_name_of_stable_id (v1, v2) =
  let id = id_of_simple_ref v1 in
  id :: v2

and id_of_import_path_elem = function
  | ImportId id -> id
  | ImportThis t -> ("this", t)
  | ImportSuper t -> ("super", t)

and v_dotted_name_of_import_path v1 = List_.map id_of_import_path_elem v1

and v_import_expr tk import_expr =
  match import_expr with
  | ImportExprSpec (path, spec) ->
      let module_name = v_dotted_name_of_import_path path in
      v_import_spec tk module_name spec
  | ImportExprMvar id ->
      (* same as Java *)
      [
        G.ImportFrom
          (tk, G.DottedName [], [ H.mk_import_from_kind (v_ident id) None ])
        |> G.d;
      ]

and v_named_selector tk path ((v1, v2) : named_selector) =
  let id = id_of_import_path_elem v1 in
  let alias =
    match v2 with
    | None -> None
    | Some id -> Some (v_ident_or_wildcard id)
  in
  G.ImportFrom (tk, G.DottedName path, [ H.mk_import_from_kind id alias ])
  |> G.d

and v_wildcard_selector tk path (x : wildcard_selector) =
  match x with
  | Left id -> G.ImportAll (tk, G.DottedName path, snd id) |> G.d
  | Right (tok, tyopt) ->
      (* given *)
      let anys =
        match tyopt with
        | None -> []
        | Some ty -> [ G.T (v_type_ ty) ]
      in
      G.OtherDirective (("ImportGiven", tok), anys) |> G.d

and v_import_spec tk path = function
  | ImportNamed v1 -> [ v_named_selector tk path v1 ]
  | ImportWildcard v1 -> [ v_wildcard_selector tk path v1 ]
  | ImportSelectors (_, v1, _) -> v_list (v_import_selector tk path) v1

and v_import (v1, v2) : G.directive list =
  let v1 = v_tok v1 in
  let v2 = v_list (v_import_expr v1) v2 in
  List_.flatten v2

and v_export (v1, v2) : G.directive list =
  let v1 = v_tok v1 in
  let v2 = v_list (v_import_expr v1) v2 in
  List_.flatten v2
  |> List_.map (fun x ->
         G.OtherDirective (("export", Tok.unsafe_fake_tok "export"), [ G.Dir x ])
         |> G.d)

and v_package (v1, v2) =
  let v1 = v_tok v1 and v2 = v_qualified_ident v2 in
  (v1, v2)

and v_literal = function
  | Symbol (tquote, id) -> Either.Left (G.Atom (tquote, id))
  | Int v1 -> Either.Left (G.Int (Parsed_int.visit ~v_tok v1))
  | Float v1 ->
      let v1 = v_wrap (v_option v_float) v1 in
      Either.Left (G.Float v1)
  | Char v1 ->
      let v1 = v_wrap v_string v1 in
      Either.Left (G.Char v1)
  | String v1 ->
      let v1 = v_wrap v_string v1 in
      Either.Left (G.String (fb v1))
  | Bool v1 ->
      let v1 = v_wrap v_bool v1 in
      Either.Left (G.Bool v1)
  | Null v1 ->
      let v1 = v_tok v1 in
      Either.Left (G.Null v1)
  | Interpolated (v1, v2, v3) ->
      let v1 = v_ident v1 and v2 = v_list v_encaps v2 and v3 = v_tok v3 in
      let special =
        G.IdSpecial (G.ConcatString (G.FString (fst v1)), snd v1) |> G.e
      in
      let args =
        v2
        |> List_.map (function
             | Either.Left lit -> G.Arg (G.L lit |> G.e)
             | Either.Right e ->
                 let special =
                   G.IdSpecial (G.InterpolatedElement, fake "") |> G.e
                 in
                 G.Arg (G.Call (special, fb [ G.Arg e ]) |> G.e))
      in
      Either.Right (G.Call (special, (snd v1, args, v3)) |> G.e)

and v_encaps = function
  | EncapsStr v1 ->
      let v1 = v_wrap v_string v1 in
      Either.Left (G.String (fb v1))
  | EncapsDollarIdent v1 ->
      let v1 = v_ident v1 in
      let name = H.name_of_id v1 in
      Either.Right (G.N name |> G.e)
  | EncapsExpr v1 ->
      (* always a Block *)
      let v1 = v_expr v1 in
      Either.Right v1

and todo_type msg anys = G.OtherType ((msg, fake msg), anys)
and v_type_ x = v_type_kind x |> G.t

and v_type_kind = function
  | TyLiteral v1 -> (
      let v1 = v_literal v1 in
      match v1 with
      | Either.Left lit -> todo_type "TyLiteralLit" [ G.E (G.L lit |> G.e) ]
      | Either.Right e -> todo_type "TyLiteralExpr" [ G.E e ])
  | TyName v1 ->
      let xs = v_dotted_name_of_stable_id v1 in
      let name = H.name_of_ids xs in
      G.TyN name
  | TyProj (v1, v2, v3) ->
      let v1 = v_type_ v1 and _v2 = v_tok v2 and v3 = v_ident v3 in
      todo_type "TyProj" [ G.T v1; G.I v3 ]
  | TyApplied (v1, v2) -> (
      let v1 = v_type_ v1 and v2 = v_bracket (v_list v_type_) v2 in
      let lp, xs, rp = v2 in
      let args = xs |> List_.map (fun x -> G.TA x) in
      match v1.t with
      | G.TyN n -> G.TyApply (G.TyN n |> G.t, (lp, args, rp))
      | _ ->
          todo_type "TyAppliedComplex"
            (G.T v1 :: (xs |> List_.map (fun x -> G.T x))))
  | TyAnon (v1, v2) ->
      (* We'd prefer to see type bounds in a `type_parameter`, but this
         nonterminal needs to become a `type_` argument anyways, and we
         don't really have a way of embedding `type_parameter` into a
         `type`. This won't matter semantically, so let's just keep it
         as an `OtherType`.
      *)
      let bound1, bound2 = v_type_bounds v2 in
      let bound1 =
        match bound1 with
        | None -> []
        | Some (_tok, ty) -> [ G.T ty ]
      in
      let bound2 =
        match bound2 with
        | None -> []
        | Some (_tok, ty) -> [ G.T ty ]
      in
      G.OtherType (("?", v1), bound1 @ bound2)
  | TyInfix (v1, v2, v3) ->
      let v1 = v_type_ v1 and v2 = v_ident v2 and v3 = v_type_ v3 in
      G.TyApply (G.TyN (H.name_of_ids [ v2 ]) |> G.t, fb [ G.TA v1; G.TA v3 ])
  | TyFunction1 (v1, v2, v3) ->
      let v1 = v_type_ v1 and _v2 = v_tok v2 and v3 = v_type_ v3 in
      G.TyFun ([ G.Param (G.param_of_type v1) ], v3)
  | TyFunction2 (v1, v2, v3) ->
      let v1 = v_bracket (v_list v_type_) v1
      and _v2 = v_tok v2
      and v3 = v_type_ v3 in
      let ts =
        v1 |> Tok.unbracket |> List_.map (fun t -> G.Param (G.param_of_type t))
      in
      G.TyFun (ts, v3)
  | TyPoly (v1, _v2, v3) ->
      let v1 = v_list (v_binding None) v1 in
      let v3 = v_type_ v3 in
      G.TyFun (v1, v3)
  | TyDependent (v1, _v2, v3) ->
      let v1 =
        v_list
          (fun (v1, v2) ->
            G.Param (G.param_of_type ~pname:(v_ident v1) (v_type_ v2)))
          v1
      in
      let v3 = v_type_ v3 in
      G.TyFun (v1, v3)
  | TyTuple v1 ->
      let v1 = v_bracket (v_list v_type_) v1 in
      G.TyTuple v1
  | TyRepeated (v1, v2) ->
      let v1 = v_type_ v1 and v2 = v_tok v2 in
      todo_type "TyRepeated" [ G.T v1; G.Tk v2 ]
  | TyByName (v1, v2) ->
      let v1 = v_tok v1 and v2 = v_type_ v2 in
      todo_type "TyByName" [ G.Tk v1; G.T v2 ]
  | TyAnnotated (v1, v2) ->
      let v1 = v_type_ v1 and _v2TODO = v_list v_annotation v2 in
      v1.t
      (* less: losing t_attrs *)
  | TyRefined (v1, v2) ->
      let v1 = v_option v_type_ v1 and _lb, defs, _rb = v_refinement v2 in
      todo_type "TyRefined"
        ((match v1 with
         | None -> []
         | Some t -> [ G.T t ])
        @ (defs |> List_.map (fun def -> G.Def def)))
  | TyMatch (ty, tok, cases) ->
      let cases = v_type_case_clauses cases in
      let ty_expr =
        G.OtherExpr (("type_expr", fake "type_expr"), [ G.T (v_type_ ty) ])
        |> G.e
      in
      let st = G.Switch (tok, Some (G.Cond ty_expr), cases) |> G.s in
      todo_type "TyMatch" [ G.S st ]
  | TyExistential (v1, v2, v3) ->
      let v1 = v_type_ v1 in
      let _v2 = v_tok v2 in
      let _lb, defs, _rb = v_refinement v3 in
      todo_type "TyExistential"
        (G.T v1 :: (defs |> List_.map (fun x -> G.Def x)))
  | TyWith (v1, v2, v3) ->
      let v1 = v_type_ v1 and v2 = v_tok v2 and v3 = v_type_ v3 in
      G.TyAnd (v1, v2, v3)
  | TyWildcard (v1, v2) ->
      let v1 = v_tok v1 and _v2TODO = v_type_bounds v2 in
      G.TyAny v1

and v_refinement v =
  v_bracket (fun xs -> v_list v_refine_stat xs |> List_.flatten) v

and v_refine_stat v = v_definition v

and v_type_bounds { supertype = v_supertype; subtype = v_subtype } =
  let arg1 =
    v_option
      (fun (v1, v2) ->
        let v1 = v_tok v1 and v2 = v_type_ v2 in
        (v1, v2))
      v_supertype
  in
  let arg2 =
    v_option
      (fun (v1, v2) ->
        let v1 = v_tok v1 and v2 = v_type_ v2 in
        (v1, v2))
      v_subtype
  in
  (arg1, arg2)

and v_ascription v = v_type_ v
and todo_pattern msg any = G.OtherPat ((msg, fake msg), any)

and v_pattern = function
  | PatLiteral v1 -> (
      let v1 = v_literal v1 in
      match v1 with
      | Either.Left lit -> G.PatLiteral lit
      | Either.Right e -> todo_pattern "PatLiteralExpr" [ G.E e ])
  | PatName (Id id, [])
    when AST_generic.is_metavar_name (fst (v_varid_or_wildcard id)) ->
      G.PatId (v_varid_or_wildcard id, G.empty_id_info ())
  | PatName v1 ->
      let ids = v_dotted_name_of_stable_id v1 in
      let name = H.name_of_ids ids in
      G.PatConstructor (name, [])
  | PatTuple v1 ->
      let v1 = v_bracket (v_list v_pattern) v1 in
      G.PatTuple v1
  | PatVarid v1 ->
      let v1 = v_varid_or_wildcard v1 in
      G.PatId (v1, G.empty_id_info ())
  | PatTypedVarid (v1, v2, v3) ->
      let v1 = v_varid_or_wildcard v1 and _v2 = v_tok v2 and v3 = v_type_ v3 in
      let p1 = G.PatId (v1, G.empty_id_info ()) in
      G.PatTyped (p1, v3)
  | PatBind (v1, v2, v3) ->
      let v1 = v_varid v1 and _v2 = v_tok v2 and v3 = v_pattern v3 in
      G.PatAs (v3, (v1, G.empty_id_info ()))
  | PatApply (v1, v2, v3) ->
      let ids = v_dotted_name_of_stable_id v1 in
      let _v2TODO = v_option (v_bracket (v_list v_type_)) v2 in
      let v3 = v_option (v_bracket (v_list v_pattern)) v3 in
      let xs =
        match v3 with
        | None -> []
        | Some (_, xs, _) -> xs
      in
      let name = H.name_of_ids ids in
      G.PatConstructor (name, xs)
  | PatInfix (v1, v2, v3) ->
      let v1 = v_pattern v1 and v2 = v_ident v2 and v3 = v_pattern v3 in
      let name = H.name_of_ids [ v2 ] in
      G.PatConstructor (name, [ v1; v3 ])
  | PatUnderscoreStar (v1, v2) ->
      let v1 = v_tok v1 and v2 = v_tok v2 in
      todo_pattern "PatUnderscoreStar" [ G.Tk v1; G.Tk v2 ]
  | PatDisj (v1, v2, v3) ->
      let v1 = v_pattern v1 and _v2 = v_tok v2 and v3 = v_pattern v3 in
      G.PatDisj (v1, v3)
  | PatQuoted quote -> (
      match quote with
      | QuotedBlock (quote_tok, (_, v1, _)) ->
          let stmts = v_block v1 in
          G.OtherPat (("QuotedBlock", quote_tok), [ G.Ss stmts ])
      | QuotedType (quote_tok, (_, v1, _)) ->
          let ty = v_type_ v1 in
          G.OtherPat (("QuotedBlock", quote_tok), [ G.T ty ]))
  | PatEllipsis v1 -> G.PatEllipsis v1

and todo_expr msg any = G.OtherExpr ((msg, fake msg), any) |> G.e

and v_expr e : G.expr =
  match e with
  | Ellipsis v1 -> G.Ellipsis v1 |> G.e
  | DeepEllipsis v1 -> G.DeepEllipsis (v_bracket v_expr v1) |> G.e
  | DotAccessEllipsis (v1, v2) ->
      let v1 = v_expr v1 in
      G.DotAccessEllipsis (v1, v2) |> G.e
  | TypedExpr (Name (Id id, []), v2, v3)
    when AST_generic.is_metavar_name (fst (v_varid_or_wildcard id)) ->
      let v3 = v_type_ v3 in
      G.TypedMetavar (id, v2, v3) |> G.e
  | L v1 -> (
      let v1 = v_literal v1 in
      match v1 with
      | Either.Left lit -> G.L lit |> G.e
      | Either.Right e -> e)
  | Tuple v1 ->
      let v1 = v_bracket (v_list v_expr) v1 in
      G.Container (G.Tuple, v1) |> G.e
  | Name v1 ->
      let sref, ids = v_path v1 in
      let start =
        match sref with
        | Either.Left id -> G.N (H.name_of_id id) |> G.e
        | Either.Right e -> e
      in
      ids
      |> List.fold_left
           (fun acc fld ->
             G.DotAccess (acc, fake ".", G.FN (H.name_of_id fld)) |> G.e)
           start
  | ExprUnderscore v1 ->
      let v1 = v_tok v1 in
      todo_expr "ExprUnderscore" [ G.Tk v1 ]
  | InstanciatedExpr (v1, v2) ->
      let v1 = v_expr v1 and _, v2, _ = v_bracket (v_list v_type_) v2 in
      todo_expr "InstanciatedExpr" (G.E v1 :: List_.map (fun t -> G.T t) v2)
  | TypedExpr (v1, v2, v3) ->
      let v1 = v_expr v1 and v2 = v_tok v2 and v3 = v_ascription v3 in
      G.Cast (v3, v2, v1) |> G.e
  | DotAccess (v1, v2, v3) ->
      let v1 = v_expr v1 and v2 = v_tok v2 and v3 = v_ident v3 in
      let name = H.name_of_id v3 in
      G.DotAccess (v1, v2, G.FN name) |> G.e
  | Apply (Name (Id ((s, _t) as id), [ ("apply", apply_tok) ]), [ args ])
    when String_.is_capitalized s ->
      New
        ( apply_tok,
          TyN (G.Id (id, G.empty_id_info ())) |> G.t,
          G.empty_id_info (),
          v_arguments args )
      |> G.e
  | Apply (v1, v2) ->
      let v1 = v_expr v1 and v2 = v_list v_arguments v2 in
      v2 |> List.fold_left (fun acc xs -> G.Call (acc, xs) |> G.e) v1
  | Infix (v1, v2, v3) ->
      (* In scala [x f y] means [x.f(y)]  *)
      let v1 = v_expr v1 and v2 = v_ident v2 and v3 = v_expr v3 in
      G.Call
        ( G.DotAccess (v1, fake ".", G.FN (H.name_of_id v2)) |> G.e,
          fb [ G.Arg v3 ] )
      |> G.e
  | Prefix (v1, v2) ->
      let v1 = v_op v1 and v2 = v_expr v2 in
      G.Call (G.N (H.name_of_id v1) |> G.e, fb [ G.Arg v2 ]) |> G.e
  | Postfix (v1, v2) ->
      let v1 = v_expr v1 and v2 = v_ident v2 in
      G.Call (G.N (H.name_of_id v2) |> G.e, fb [ G.Arg v1 ]) |> G.e
  | Assign (v1, v2, v3) ->
      let v1 = v_lhs v1 and v2 = v_tok v2 and v3 = v_expr v3 in
      G.Assign (v1, v2, v3) |> G.e
  | Lambda v1 ->
      let v1 = v_function_definition v1 in
      G.Lambda v1 |> G.e
  | New (v1, v2) -> (
      let v1 = v_tok v1 and v2 = v_template_definition v2 in
      match v2 with
      | {
       cextends = [ (tp, args) ];
       cparams = _, [], _;
       cmixins = [];
       cbody = _, [], _;
       cimplements = [];
       ckind = G.Object, _;
      } ->
          let args =
            match args with
            | None -> Tok.unsafe_fake_bracket []
            | Some args -> args
          in
          G.New (v1, tp, G.empty_id_info (), args) |> G.e
      | _ ->
          let cl = G.AnonClass v2 |> G.e in
          G.Call (cl, fb []) |> G.e)
  | Quoted quote -> (
      match quote with
      | QuotedBlock (quote_tok, (_, v1, _)) ->
          let stmts = v_block v1 in
          G.OtherExpr (("QuotedBlock", quote_tok), [ G.Ss stmts ]) |> G.e
      | QuotedType (quote_tok, (_, v1, _)) ->
          let ty = v_type_ v1 in
          G.OtherExpr (("QuotedBlock", quote_tok), [ G.T ty ]) |> G.e)
  | BlockExpr v1 -> (
      let lb, kind, _rb = v_block_expr v1 in
      match kind with
      | Either.Left stats -> expr_of_block stats
      | Either.Right cases -> G.Lambda (cases_to_lambda lb cases) |> G.e)
  (* TODO: should move Match under S in ast_scala.ml *)
  | Match (v1, v2, v3) ->
      let v1 = v_expr v1
      and v2 = v_tok v2
      and v3 = v_bracket v_case_clauses v3 in
      let st = G.Switch (v2, Some (G.Cond v1), Tok.unbracket v3) |> G.s in
      G.stmt_to_expr st
  | S v1 ->
      let v1 = v_stmt v1 in
      G.stmt_to_expr v1

(* alt: transform in a series of Seq? *)
and expr_of_block xs : G.expr =
  let st = G.Block (fb xs) |> G.s in
  G.stmt_to_expr st

and v_lhs v = v_expr v

and v_arguments = function
  | Args v1 -> (
      let lb, v1, rb = v_bracket (v_list (v_argument ~is_using:false)) v1 in
      match List.rev v1 with
      | G.Arg
          { e = Call ({ e = N (Id (("*", tok), _)); _ }, (lb', [ e ], rb')); _ }
        :: rest ->
          let splatted_last_arg =
            G.Call (G.IdSpecial (G.Spread, tok) |> G.e, (lb', [ e ], rb'))
            |> G.e
          in
          (lb, List.rev rest @ [ G.Arg splatted_last_arg ], rb)
      | _ -> (lb, v1, rb))
  | ArgUsing v1 ->
      let v1 = v_bracket (v_list (v_argument ~is_using:true)) v1 in
      v1
  | ArgBlock v1 -> (
      let lb, kind, rb = v_block_expr v1 in
      match kind with
      | Either.Left stats -> (lb, [ G.Arg (expr_of_block stats) ], rb)
      | Either.Right cases ->
          (lb, [ G.Arg (G.Lambda (cases_to_lambda lb cases) |> G.e) ], rb))

and v_argument ?(is_using = false) v =
  let v = v_expr v in
  if is_using then (* TODO: For now, just pass as a regular argument. *)
    G.Arg v
  else G.Arg v

and v_case_clauses v : G.case_and_body list = v_list v_case_clause v
and v_type_case_clauses v : G.case_and_body list = v_list v_type_case_clause v

and v_type_case_clause v : G.case_and_body =
  match v with
  | CC x ->
      let icase, l_ty, r_ty = v_type_case_clause_classic x in
      let pat =
        match l_ty with
        | Either.Left tok -> G.PatWildcard tok
        | Either.Right ty -> PatType ty
      in
      G.CasesAndBody
        ([ Case (icase, pat) ], G.OtherStmt (OS_Todo, [ G.T r_ty ]) |> G.s)
  | CaseEllipsis ii -> G.CaseEllipsis ii

and v_case_clause v : G.case_and_body =
  match v with
  | CC x ->
      let icase, p, s = v_case_clause_classic x in
      G.case_of_pat_and_stmt ~tok:icase (p, s)
  | CaseEllipsis ii -> G.CaseEllipsis ii

and v_case_clause_classic
    {
      casetoks = v_casetoks;
      case_left = v_casepat;
      caseguard = v_caseguard;
      case_right = v_casebody;
    } =
  let icase, _iarrow =
    match v_casetoks with
    | v1, v2 ->
        let v1 = v_tok v1 and v2 = v_tok v2 in
        (v1, v2)
  in
  let pat = v_pattern v_casepat in
  let guardopt = v_option v_guard v_caseguard in
  let block = v_block v_casebody in
  let pat =
    match guardopt with
    | None -> pat
    | Some (_t, e) -> PatWhen (pat, e)
  in
  (icase, pat, G.Block (fb block) |> G.s)

and v_type_case_clause_classic
    {
      casetoks = v_casetoks;
      case_left = v_case_ty_left;
      caseguard = v_caseguard;
      case_right = v_case_ty_right;
    } =
  let icase, _iarrow =
    match v_casetoks with
    | v1, v2 ->
        let v1 = v_tok v1 and v2 = v_tok v2 in
        (v1, v2)
  in
  let left =
    match v_case_ty_left with
    | Either.Left tok -> Either.Left tok
    | Either.Right ty -> Either.Right (v_type_ ty)
  in
  let _guardopt = v_option v_guard v_caseguard in
  let right = v_type_ v_case_ty_right in
  (icase, left, right)

and v_guard (v1, v2) =
  let v1 = v_tok v1 and v2 = v_expr v2 in
  (v1, v2)

and v_block_expr v =
  let lb, xs, rb = v_bracket v_block_expr_kind v in
  (lb, xs, rb)

and v_block_expr_kind = function
  | BEBlock v1 ->
      let v1 = v_block v1 in
      Either.Left v1
  | BECases v1 ->
      let v1 = v_case_clauses v1 in
      Either.Right v1

and v_expr_for_stmt (e : expr) : G.stmt =
  match e with
  | S s -> v_stmt s
  | _ ->
      let e = v_expr e in
      G.ExprStmt (e, G.sc) |> G.s

and v_stmt = function
  | Block v1 ->
      let v1 = v_bracket v_block v1 in
      G.Block v1 |> G.s
  | If (v1, v2, v3, v4) ->
      let v1 = v_tok v1
      and v2 = v_bracket v_expr v2
      and v3 = v_expr_for_stmt v3
      and v4 =
        v_option
          (fun (v1, v2) ->
            let _v1 = v_tok v1 and v2 = v_expr_for_stmt v2 in
            v2)
          v4
      in
      G.If (v1, G.Cond (Tok.unbracket v2), v3, v4) |> G.s
  | While (v1, v2, v3) ->
      let v1 = v_tok v1
      and v2 = v_bracket v_expr v2
      and v3 = v_expr_for_stmt v3 in
      G.While (v1, G.Cond (Tok.unbracket v2), v3) |> G.s
  | DoWhile (v1, v2, v3, v4) ->
      let v1 = v_tok v1
      and v2 = v_expr_for_stmt v2
      and _v3 = v_tok v3
      and v4 = v_bracket v_expr v4 in
      G.DoWhile (v1, v2, Tok.unbracket v4) |> G.s
  | For (v1, v2, v3) ->
      (* See https://scala-lang.org/files/archive/spec/2.13/06-expressions.html#for-comprehensions-and-for-loops
       * for an explanation of for loops in scala
       *)
      let v1 = v_tok v1
      and v2 = v2 |> Tok.unbracket |> v_enumerators
      and v3 = v_for_body v3 in
      G.For (v1, G.MultiForEach v2, v3) |> G.s
  | Return (v1, v2) ->
      let v1 = v_tok v1 and v2 = v_option v_expr v2 in
      G.Return (v1, v2, G.sc) |> G.s
  | Try (v1, v2, v3, v4) ->
      let v1 = v_tok v1
      and v2 = v_expr_for_stmt v2
      and v3 = v_option v_catch_clause v3
      and v4 = v_option v_finally_clause v4 in
      let catches =
        match v3 with
        | None -> []
        | Some xs -> xs
      in
      G.Try (v1, v2, catches, None, v4) |> G.s
  | Throw (v1, v2) ->
      let v1 = v_tok v1 and v2 = v_expr v2 in
      G.Throw (v1, v2, G.sc) |> G.s

and v_enumerators v = v_list v_enumerator v

and v_enumerator = function
  | G v1 -> (
      let pat, tok, e, guards = v_generator v1 in
      match guards with
      | [] -> G.FE (pat, tok, e)
      | (tok2, cond) :: guards ->
          let conds =
            List.fold_left
              (fun e (tok, c) -> G.special (G.Op G.And, tok) [ e; c ])
              cond guards
          in
          G.FECond ((pat, tok, e), tok2, conds))
  | GEllipsis tok -> G.FEllipsis tok

and v_generator
    {
      genpat = v_genpat;
      gentok = v_gentok;
      genbody = v_genbody;
      genguards = v_genguards;
    } =
  let pat = v_pattern v_genpat in
  let t = v_tok v_gentok in
  let e = v_expr v_genbody in
  let guards = v_list v_guard v_genguards in
  (pat, t, e, guards)

and v_for_body = function
  | Yield (v1, v2) ->
      let v1 = v_tok v1 and v2 = v_expr v2 in
      let e = G.Yield (v1, Some v2, false) |> G.e in
      G.exprstmt e
  | NoYield v1 ->
      let v1 = v_expr_for_stmt v1 in
      v1

and v_catch_clause (v1, v2) : G.catch list =
  let v1 = v_tok v1 in
  match v2 with
  | CatchCases (_lb, xs, _rb) ->
      xs
      |> List_.map (function
           | CC x ->
               let icase, pat, st = v_case_clause_classic x in
               (icase, G.CatchPattern pat, st)
           | CaseEllipsis ii ->
               (* TODO: refactor G.catch to allow CatchEllipsis? *)
               let st = G.Ellipsis ii |> G.e |> G.exprstmt in
               (ii, G.CatchPattern (G.PatEllipsis ii), st))
  | CatchExpr e ->
      let e = v_expr e in
      let pat = G.PatWildcard v1 in
      [ (v1, G.CatchPattern pat, G.exprstmt e) ]

and v_finally_clause (v1, v2) =
  let v1 = v_tok v1 and v2 = v_expr_for_stmt v2 in
  (v1, v2)

and v_block v = v_list v_block_stat v |> List_.flatten

and v_block_stat x : G.item list =
  match x with
  | D v1 ->
      let v1 = v_definition v1 in
      v1 |> List_.map (fun def -> G.DefStmt def |> G.s)
  | I v1 ->
      let v1 = v_import v1 in
      v1 |> List_.map (fun dir -> G.DirectiveStmt dir |> G.s)
  | Ex v1 ->
      let v1 = v_export v1 in
      v1 |> List_.map (fun dir -> G.DirectiveStmt dir |> G.s)
  | E v1 ->
      let v1 = v_expr_for_stmt v1 in
      [ v1 ]
  | End v1 ->
      let v1 = v_end_marker v1 in
      [ v1 ]
  | Ext v1 -> v_extension v1
  | Package v1 ->
      let ipak, ids = v_package v1 in
      [ G.DirectiveStmt (G.Package (ipak, ids) |> G.d) |> G.s ]
  | Packaging (v1, (_lb, v2, rb)) ->
      let ipak, ids = v_package v1 in
      let xxs = v_list v_top_stat v2 in
      [ G.DirectiveStmt (G.Package (ipak, ids) |> G.d) |> G.s ]
      @ List_.flatten xxs
      @ [ G.DirectiveStmt (G.PackageEnd rb |> G.d) |> G.s ]

and v_top_stat v = v_block_stat v

and v_modifier v : G.attribute =
  let kind, tok = v_wrap v_modifier_kind v in
  match kind with
  | Either.Left kwd -> G.KeywordAttr (kwd, tok)
  | Either.Right s -> G.OtherAttribute ((s, tok), [])

and v_modifier_kind = function
  | Abstract -> Either.Left G.Abstract
  | Final -> Either.Left G.Final
  | Sealed -> Either.Left G.SealedClass
  | Implicit -> Either.Right "implicit"
  | Lazy -> Either.Left G.Lazy
  | Private v1 ->
      let _v1TODO = v_option (v_bracket v_ident_or_this) v1 in
      Either.Left G.Private
  | Protected v1 ->
      let _v1TODO = v_option (v_bracket v_ident_or_this) v1 in
      Either.Left G.Protected
  | Override -> Either.Left G.Override
  | Inline -> Either.Right "inline"
  | Open -> Either.Right "open"
  | Opaque -> Either.Right "opaque"
  | CaseClassOrObject -> Either.Left G.RecordClass
  | PackageObject -> Either.Right "PackageObject"
  | Val -> Either.Left G.Const
  | Var -> Either.Left G.Mutable
  | EnumClass -> Either.Left G.EnumClass

and v_annotation (v1, v2, v3) : G.attribute =
  let v1 = v_tok v1 and v2 = v_type_ v2 and v3 = v_list v_arguments v3 in
  let args = v3 |> List_.map Tok.unbracket |> List_.flatten in
  match v2.t with
  | TyN name -> G.NamedAttr (v1, name, fb args)
  | _ ->
      G.OtherAttribute (("AnnotationComplexType", v1), [ G.T v2; G.Args args ])

and v_attribute x : G.attribute =
  match x with
  | A v1 ->
      let v1 = v_annotation v1 in
      v1
  | M v1 ->
      let v1 = v_modifier v1 in
      v1

and v_type_parameter
    {
      tpname = v_tpname;
      tpvariance = v_tpvariance;
      tpannots = v_tpannots;
      tpparams = v_tpparams;
      tpbounds = v_tpbounds;
      tpviewbounds = v_tpviewbounds;
      tpcolons = v_tpcolons;
    } : G.type_parameter =
  let tp_id = v_ident_or_wildcard v_tpname in
  let tp_variance = v_option (v_wrap v_variance) v_tpvariance in
  let tp_attrs = v_list v_annotation v_tpannots in
  let _argTODO = v_type_parameters v_tpparams in
  let _argTODO = v_type_bounds v_tpbounds in
  let _argTODO = v_list v_type_ v_tpviewbounds in
  let _argTODO = v_list v_type_ v_tpcolons in
  let tp_bounds = [] in
  (* TODO *)
  TP { G.tp_id; tp_variance; tp_attrs; tp_bounds; tp_default = None }

and v_variance = function
  | Covariant -> G.Covariant
  | Contravariant -> G.Contravariant

and v_type_parameters v : G.type_parameters option =
  v_option (v_bracket (v_list v_type_parameter)) v

and v_definition x : G.definition list =
  match x with
  | DefEnt (v1, v2) ->
      let v1 = v_entity v1 and v2 = v_definition_kind v2 in
      [ (v1, v2) ]
  | EnumCaseDef (attrs, v1) ->
      let attrs = v_list v_attribute attrs in
      v_enum_case_definition attrs v1
  | GivenDef v1 -> v_given_definition v1
  | VarDefs v1 -> v_variable_definitions v1

and v_given_definition { gsig; gkind } =
  let v1 =
    match gsig with
    | None -> []
    | Some { g_id; g_tparams; g_using; g_colon = _ } ->
        let g_id =
          match g_id with
          | None -> []
          | Some id -> [ G.I (v_ident id) ]
        in
        let g_tparams =
          match v_type_parameters g_tparams with
          | None -> []
          | Some (_, xs, _) -> [ G.Anys (xs |> List_.map (fun x -> G.Tp x)) ]
        in
        let g_using =
          [
            G.Anys
              (v_list v_bindings g_using |> List_.flatten
              |> List_.map (fun x -> G.Pa x));
          ]
        in
        g_id @ g_tparams @ g_using
  in
  let v2 =
    match gkind with
    | GivenStructural (constr_apps, body) ->
        let v1 =
          v_list v_constr_app constr_apps
          |> List_.map (fun (ty, argss) ->
                 let flat_args =
                   List.concat_map (fun (_, args, _) -> args) argss
                 in
                 G.Anys
                   [ G.T ty; G.Anys (List_.map (fun x -> G.Ar x) flat_args) ])
        in
        let v2 =
          match body with
          | None -> []
          | Some body ->
              let body = v_template_body body in
              [ G.S (G.Block body |> G.s) ]
        in
        v1 @ v2
    | GivenType (ty, exp) ->
        let v1 = [ G.T (v_type_ ty) ] in
        let v2 =
          match exp with
          | None -> []
          | Some exp -> [ G.E (v_expr exp) ]
        in
        v1 @ v2
  in
  let todo_kind = ("given", Tok.unsafe_fake_tok "given") in
  [
    ( { name = G.OtherEntity (todo_kind, []); attrs = []; tparams = None },
      G.OtherDef (todo_kind, v1 @ [ G.Anys v2 ]) );
  ]

and v_end_marker { end_tok; end_kind } : G.stmt =
  G.OtherStmt (OS_Todo, [ G.Tk end_tok; G.Tk end_kind ]) |> G.s

and v_extension { ext_tok = _; ext_tparams; ext_using; ext_param; ext_methods }
    : G.stmt list =
  let tparams =
    match v_type_parameters ext_tparams with
    | None -> G.Anys []
    | Some (_, xs, _) -> G.Anys (xs |> List_.map (fun tp -> G.Tp tp))
  in
  let using =
    G.Anys
      (v_list v_bindings ext_using |> List_.map (fun params -> G.Params params))
  in
  let params = G.Pa (v_binding None ext_param) in
  let methods = G.Anys (List.concat_map v_ext_method ext_methods) in
  (* Extensions are definitions and methods that extend an existing class. It's not
     super important for semantic analysis right now.
  *)
  [ G.OtherStmt (OS_Extension, [ tparams; using; params; methods ]) |> G.s ]

and v_ext_method ext_method : G.any list =
  match ext_method with
  | ExtDef def -> v_definition def |> List_.map (fun def -> G.Def def)
  | ExtExport import -> v_import import |> List_.map (fun dir -> G.Dir dir)

and v_constr_app (ty, args) = (v_type_ ty, v_list v_arguments args)

and v_enum_case_definition attrs v1 =
  match v1 with
  | EnumIds ids ->
      let ids = v_list v_ident ids in
      ids
      |> List_.map (fun id ->
             ( G.basic_entity id,
               G.EnumEntryDef { ee_args = None; ee_body = None } ))
  | EnumConstr { eid; etyparams; eparams; eattrs; eextends } ->
      let id = v_ident eid in
      let tparams = v_type_parameters etyparams in
      let params = v_list v_bindings eparams |> List_.flatten in
      let attrs = v_list v_attribute eattrs @ attrs in
      (* TODO *)
      let _extends = v_list v_constr_app eextends in
      let fake = Tok.unsafe_fake_tok "Param" in
      (* Here, we turn the params into arguments.
         They are represented syntactically as parameters, but they'll fit
         fine here too. This is with the understanding that this probably
         won't matter semantically.
      *)
      let args =
        match
          List_.map
            (fun param -> G.OtherArg (("Param", fake), [ G.Pa param ]))
            params
        with
        | [] -> None
        | args -> Some (fb args)
      in
      [
        ( G.basic_entity ~attrs ?tparams id,
          G.EnumEntryDef { ee_args = args; ee_body = None } );
      ]

and v_variable_definitions
    {
      vpatterns = v_vpatterns;
      vattrs = v_vattrs;
      vtype = v_vtype;
      vbody = v_vbody;
    } =
  let attrs = v_list v_attribute v_vattrs in
  let topt = v_option v_type_ v_vtype in
  let eopt = v_option v_expr v_vbody in
  v_vpatterns
  |> List_.filter_map (fun pat ->
         match pat with
         | PatVarid id
         | PatName (Id id, []) ->
             let ent = G.basic_entity id ~attrs in
             let vdef = { G.vinit = eopt; vtype = topt; vtok = G.no_sc } in
             Some (ent, G.VarDef vdef)
         | _ ->
             (* TODO: some patterns may have tparams? *)
             let ent =
               { G.name = EPattern (v_pattern pat); attrs; tparams = None }
             in
             let vdef = { G.vinit = eopt; vtype = topt; vtok = G.no_sc } in
             Some (ent, G.VarDef vdef))

and v_entity { name = v_name; attrs = v_attrs; tparams = v_tparams } =
  let v1 = v_ident v_name in
  let v2 = v_list v_attribute v_attrs in
  let v3 = v_type_parameters v_tparams in
  { name = G.EN (H.name_of_id v1); attrs = v2; tparams = v3 }

and v_definition_kind = function
  | FuncDef v1 ->
      let v1 = v_function_definition v1 in
      G.FuncDef v1
  | TypeDef v1 ->
      let v1 = v_type_definition v1 in
      G.TypeDef v1
  | Template v1 ->
      let v1 = v_template_definition v1 in
      G.ClassDef v1

and v_function_definition
    {
      fkind = v_fkind;
      fparams = v_fparams;
      frettype = v_frettype;
      fbody = vfbody;
    } =
  let kind = v_wrap v_function_kind v_fkind in
  let params = v_list v_bindings v_fparams in
  let tret = v_option v_type_ v_frettype in
  let fbody = v_option v_fbody vfbody in
  {
    fkind = kind;
    fparams = fb (List_.flatten params);
    (* TODO? *)
    frettype = tret;
    fbody =
      (match fbody with
      | None -> G.FBDecl G.sc
      | Some st -> st);
  }

and v_function_kind = function
  | LambdaArrow -> G.Arrow
  | Def -> G.Method

and v_fbody body : G.function_body =
  match body with
  | FBlock v1 -> (
      let lb, kind, rb = v_block_expr v1 in
      match kind with
      | Either.Left stats ->
          let st = G.Block (lb, stats, rb) |> G.s in
          G.FBStmt st
      | Either.Right cases ->
          let def = cases_to_lambda lb cases in
          G.FBExpr (G.Lambda def |> G.e))
  | FExpr (v1, v2) ->
      let _v1 = v_tok v1 and v2 = v_expr v2 in
      G.FBExpr v2

and v_bindings v =
  v_bracket (fun (a, b) -> v_list (v_binding b) a) v |> Tok.unbracket

and v_binding using_opt v : G.parameter =
  let pattrs =
    match using_opt with
    | None -> []
    | Some tok -> [ G.OtherAttribute (("using", tok), []) ]
  in
  match v with
  | ParamEllipsis t -> G.ParamEllipsis t
  | ParamType ty -> G.Param (G.param_of_type ~pattrs (v_type_ ty))
  | ParamClassic
      {
        p_name = v_p_name;
        p_attrs = v_p_attrs;
        p_type = v_p_type;
        p_default = v_p_default;
      } -> (
      let id = v_ident_or_wildcard v_p_name in
      let attrs = pattrs @ v_list v_attribute v_p_attrs in
      let default = v_option v_expr v_p_default in
      let pclassic =
        { (G.param_of_id id) with pattrs = attrs; pdefault = default }
      in
      match v_p_type with
      | None -> G.Param pclassic
      | Some (PT v1) ->
          let v1 = v_type_ v1 in
          G.Param { pclassic with ptype = Some v1 }
      | Some (PTByNameApplication (v1, v2, v3)) -> (
          let v1 = v_tok v1 and v2 = v_type_ v2 in
          let pclassic =
            {
              pclassic with
              ptype = Some v2;
              pattrs = G.KeywordAttr (G.Lazy, v1) :: pclassic.pattrs;
            }
          in
          match v3 with
          | Some ii -> G.ParamRest (ii, pclassic)
          | _ -> G.Param pclassic)
      | Some (PTRepeatedApplication (v1, v2)) ->
          let v1 = v_type_ v1 and v2 = v_tok v2 in
          G.ParamRest (v2, { pclassic with ptype = Some v1 }))

and v_template_definition
    {
      ckind = v_ckind;
      cparams = v_cparams;
      cparents = v_cparents;
      cbody = v_cbody;
    } : G.class_definition =
  let ckind = v_wrap v_template_kind v_ckind in
  (* TODO? flatten? *)
  let cparams = fb (v_list v_bindings v_cparams |> List_.flatten) in
  let cextends, cmixins = v_template_parents v_cparents in
  let body = v_option v_template_body v_cbody in
  let cbody =
    match body with
    | None -> G.empty_body
    | Some (lb, xs, rb) -> (lb, xs |> List_.map (fun st -> G.F st), rb)
  in
  { G.ckind; cextends; cmixins; cimplements = []; cparams; cbody }

and v_template_parents { cextends = v_cextends; cwith = v_cwith } =
  let parents =
    match v_cextends with
    | None -> []
    | Some (v1, v2) ->
        let v1 = v_type_ v1 in
        let v2 = v_list v_arguments v2 in
        let parent =
          match v2 with
          | [] -> (v1, None)
          | [ args ] -> (v1, Some args)
          | args :: _otherargsTODO -> (v1, Some args)
        in
        [ parent ]
  in
  let v2 = v_list v_type_ v_cwith in
  (parents, v2)

and v_template_body v =
  v_bracket
    (fun (v1, v2) ->
      let _v1TODO = v_option v_self_type v1 and v2 = v_block v2 in
      v2)
    v

and v_self_type (v1, v2, v3) =
  let _v1 = v_ident_or_this v1
  and _v2 = v_option v_type_ v2
  and _v3 = v_tok v3 in
  ()

and v_template_kind = function
  | Enum -> G.Class
  | Class -> G.Class
  | Trait -> G.Trait
  | Object -> G.Object
  | Singleton -> G.Object

and v_type_definition { ttok = v_ttok; tbody = v_tbody } =
  let _tok = v_tok v_ttok in
  let arg = v_type_definition_kind v_tbody in
  { tbody = arg }

and v_type_definition_kind = function
  | TDef (v1, v2) ->
      let _v1 = v_tok v1 and v2 = v_type_ v2 in
      G.NewType v2
  | TDcl v1 ->
      let _v1TODO = v_type_bounds v1 in
      (* abstract type with constraints? *)
      G.AbstractType (fake "")

let v_program v = v_list v_top_stat v |> List_.flatten

let v_any = function
  | Pr v1 ->
      let v1 = v_program v1 in
      G.Ss v1
  | Tk v1 ->
      let v1 = v_tok v1 in
      G.Tk v1
  | Ex e ->
      let st = v_expr_for_stmt e in
      G.S st
  | Ss b ->
      let xs = v_block b in
      G.Ss xs

(*****************************************************************************)
(* Entry points *)
(*****************************************************************************)

let program xs = v_program xs
let any x = v_any x
