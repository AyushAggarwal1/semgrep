type tainted_tokens = AST_generic.tok list [@@deriving show]
(** A list of tokens showing where the taint passed through,
  * at present these represent only code variables. *)

(** A call trace to a source or sink match.
  * E.g. Call('foo(a)', PM('sink(x)')) is an indirect match for 'sink(x)'
  * through the function call 'foo(a)'. *)
type 'a call_trace =
  | PM of Pattern_match.t * 'a  (** A direct match.  *)
  | Call of AST_generic.expr * tainted_tokens * 'a call_trace
      (** An indirect match through a function call. *)
[@@deriving show]

type source = {
  call_trace : Rule.taint_source call_trace;
  label : string;
      (** The label of this particular taint.
        This may not agree with the source of the `call_trace`, because
        this label may have changed, for instance by being propagated to
        a different label.
      *)
}
[@@deriving show]

type sink = Rule.taint_sink call_trace [@@deriving show]
type arg_pos = string * int [@@deriving show]
type arg = { pos : arg_pos; offset : IL.name list } [@@deriving show]

(** The origin of taint, where does taint comes from? *)
type orig =
  | Src of source  (** An actual taint source (`pattern-sources:` match). *)
  | Arg of arg
      (** A taint variable (potential taint coming through an argument). *)
[@@deriving show]

type taint = { orig : orig; tokens : tainted_tokens } [@@deriving show]

type taints_to_sink = {
  taints_with_precondition : taint list * AST_generic.expr;
  sink : sink;
  merged_env : Metavariable.bindings;
}
[@@deriving show]

(** Function-level finding (not necessarily a Semgrep finding). These may
  * depend on taint variables so they must be interpreted on a specific
  * context.
  *)
type finding =
  | ToSink of taints_to_sink
      (** Taint sources or potentially-tainted arguments inside the function
          reach a sink. *)
  | ToReturn of taint list * AST_generic.tok
      (** Taint sources or potentially-tainted arguments
          would reach a `return` statement. *)
[@@deriving show]

type signature = finding list
(** A taint signature, it is simply a list of findings for a function.
 *
 * Note that `ArgToSink` and `ArgToReturn` introduce a form of
 * "taint polymorphism", making the taint analysis context-sensitive.
 *
 * Also note that, within each function, if there are multiple paths through
 * which a taint source may reach a sink, we do not keep all of them but only
 * the shortest one.
 *
 * THINK: We could write this in a way that resembles a function type,
 *   but right now it would probably just add complexity. *)

(** A set of taint sources. *)
module Taint_set : sig
  type t

  val empty : t
  val is_empty : t -> bool
  val equal : t -> t -> bool
  val singleton : taint -> t
  val add : taint -> t -> t
  val union : t -> t -> t
  val diff : t -> t -> t
  val map : (taint -> taint) -> t -> t
  val iter : (taint -> unit) -> t -> unit
  val fold : (taint -> 'a -> 'a) -> t -> 'a -> 'a
  val of_list : taint list -> t
  val to_seq : t -> taint Seq.t
  val elements : t -> taint list
end

type taints = Taint_set.t

val trace_of_pm : Pattern_match.t * 'a -> 'a call_trace
val pm_of_trace : 'a call_trace -> Pattern_match.t * 'a
val taint_of_pm : Pattern_match.t * Rule.taint_source -> taint
val taints_of_pms : (Pattern_match.t * Rule.taint_source) list -> taints
val show_taints : taints -> string
val _show_arg : arg -> string
val _show_finding : finding -> string
