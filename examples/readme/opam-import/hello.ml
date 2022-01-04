open Cmdliner

let greet () = print_endline "Hello, world!"

let greet_t = Term.(const greet $ const ())

let () = Term.exit @@ Term.eval (greet_t, Term.info "greet")
