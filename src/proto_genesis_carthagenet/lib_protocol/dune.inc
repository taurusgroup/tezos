

;
;        /!\ /!\ Do not modify this file /!\ /!\
;
; but the original template in `tezos-protocol-compiler`
;

; generated from src/lib_protocol_compiler/dune_protocol.template.v0
;
; This template is intended for protocols written when the Tezos
; project was using OCaml 4.10 or earlier.
;
; Protocols that have already been activated on-chain cannot be
; changed. Additionally, protocols written when the tezos project was
; using OCaml 4.10 or earlier may trigger warnings when compiled with a more
; recent version of the OCaml compiler. Consequently, this template
; sets some specific warning-related options so that protocols written
; on OCaml 4.10 or earlier can be compiled with the more recent compiler version
; currently used in the tezos project.

(rule
 (targets environment.ml)
 (action
  (write-file %{targets}
              "module Name = struct let name = \"genesis-carthagenet\" end
include Tezos_protocol_environment.MakeV0(Name)()
module CamlinternalFormatBasics = struct include CamlinternalFormatBasics end
")))

(rule
 (targets registerer.ml)
 (deps
   data.ml
   services.ml
   main.mli main.ml
   (:src_dir TEZOS_PROTOCOL))
 (action
  (with-stdout-to %{targets}
                  (chdir %{workspace_root} (run %{bin:tezos-embedded-protocol-packer} "%{src_dir}" "genesis_carthagenet")))))

(rule
 (targets functor.ml)
 (deps
   data.ml
   services.ml
   main.mli main.ml
   (:src_dir TEZOS_PROTOCOL))
 (action (with-stdout-to %{targets}
                         (chdir %{workspace_root}
                                (run %{bin:tezos-protocol-compiler.tezos-protocol-packer} %{src_dir})))))

(rule
 (targets protocol.ml)
 (deps
   data.ml
   services.ml
   main.mli main.ml)
 (action
  (write-file %{targets}
    "module Environment = Tezos_protocol_environment_genesis_carthagenet.Environment
let hash = Tezos_crypto.Protocol_hash.of_b58check_exn \"PtYuensgYBb3G3x1hLLbCmcav8ue8Kyd2khADcL5LsT5R1hcXex\"
let name = Environment.Name.name
include Tezos_raw_protocol_genesis_carthagenet
include Tezos_raw_protocol_genesis_carthagenet.Main
")))

(library
 (name tezos_protocol_environment_genesis_carthagenet)
 (instrumentation (backend bisect_ppx))
 (public_name tezos-protocol-genesis-carthagenet.environment)
 (library_flags (:standard -linkall))
 (libraries tezos-protocol-environment)
 (modules Environment))

(library
 (name tezos_raw_protocol_genesis_carthagenet)
 (instrumentation (backend bisect_ppx))
 (public_name tezos-protocol-genesis-carthagenet.raw)
 (libraries tezos_protocol_environment_genesis_carthagenet)
 (library_flags (:standard -linkall))
 (flags (:standard -nopervasives -nostdlib
                   -w +a-4-6-7-9-16-29-32-40..42-44-45-48-60-67-68
                   -warn-error +a
                   -open Tezos_protocol_environment_genesis_carthagenet__Environment
                   -open Pervasives
                   -open Error_monad))
 (modules
   Data
   Services
   Main))

(install
 (section lib)
 (package tezos-protocol-genesis-carthagenet)
 (files (TEZOS_PROTOCOL as raw/TEZOS_PROTOCOL)))

(library
 (name tezos_protocol_genesis_carthagenet)
 (instrumentation (backend bisect_ppx))
 (public_name tezos-protocol-genesis-carthagenet)
 (libraries
      tezos-protocol-environment
      tezos-protocol-environment-sigs
      tezos_raw_protocol_genesis_carthagenet)
 (flags -w "+a-4-6-7-9-16-29-40..42-44-45-48-60-67-68"
        -warn-error "-A"
        -nopervasives)
 (modules Protocol))

(library
 (name tezos_protocol_genesis_carthagenet_functor)
 (instrumentation (backend bisect_ppx))
 (public_name tezos-protocol-functor-genesis-carthagenet)
 (libraries
      tezos-protocol-environment
      tezos-protocol-environment-sigs
      tezos-protocol-genesis-carthagenet.raw)
 (flags -w "+a-4-6-7-9-16-29-40..42-44-45-48-60-67-68"
        -warn-error "-A"
        -nopervasives)
 (modules Functor))

(library
 (name tezos_embedded_protocol_genesis_carthagenet)
 (instrumentation (backend bisect_ppx))
 (public_name tezos-embedded-protocol-genesis-carthagenet)
 (library_flags (:standard -linkall))
 (libraries tezos-protocol-genesis-carthagenet
            tezos-protocol-updater
            tezos-protocol-environment)
 (flags (:standard -w +a-4-6-7-9-16-29-32-40..42-44-45-48-60-67
                   -warn-error +a))
 (modules Registerer))

(rule
 (alias runtest_compile_protocol)
 (deps
   data.ml
   services.ml
   main.mli main.ml
  (:src_dir TEZOS_PROTOCOL))
 (action (run %{bin:tezos-protocol-compiler} -no-hash-check .)))

(rule
 (alias runtest_sandbox)
 (deps .tezos_protocol_genesis_carthagenet.objs/native/tezos_protocol_genesis_carthagenet.cmx)
 (action (progn)))

(rule
 (alias runtest)
 (package tezos-protocol-genesis-carthagenet)
 (deps (alias runtest_sandbox))
 (action (progn)))
