open Cmdliner

let greet () = print_endline "Hello, world!"

let greet_t = Term.(const greet $ const ())

let cmd =
  Cmd.v (Cmd.info "greet") greet_t

let () = exit @@ Cmd.eval cmd
