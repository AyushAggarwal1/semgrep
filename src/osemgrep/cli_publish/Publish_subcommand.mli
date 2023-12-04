type caps = < stdout : Cap.Console.stdout ; network : Cap.Network.t >

(*
   Parse a semgrep-publish command, execute it and exit.

   Usage: main [| "semgrep-publish"; ... |]

   This function returns an exit code to be passed to the 'exit' function.
*)

val main : caps -> string array -> Exit_code.t
