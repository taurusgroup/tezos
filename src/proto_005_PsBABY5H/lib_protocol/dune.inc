

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
              "module Name = struct let name = \"005-PsBABY5H\" end
include Tezos_protocol_environment.MakeV0(Name)()
module CamlinternalFormatBasics = struct include CamlinternalFormatBasics end
")))

(rule
 (targets registerer.ml)
 (deps
   misc.mli misc.ml
   storage_description.mli storage_description.ml
   state_hash.ml
   nonce_hash.ml
   script_expr_hash.ml
   contract_hash.ml
   blinded_public_key_hash.mli blinded_public_key_hash.ml
   qty_repr.ml
   tez_repr.mli tez_repr.ml
   period_repr.mli period_repr.ml
   time_repr.mli time_repr.ml
   constants_repr.ml
   fitness_repr.ml
   raw_level_repr.mli raw_level_repr.ml
   voting_period_repr.mli voting_period_repr.ml
   cycle_repr.mli cycle_repr.ml
   level_repr.mli level_repr.ml
   seed_repr.mli seed_repr.ml
   gas_limit_repr.mli gas_limit_repr.ml
   script_int_repr.mli script_int_repr.ml
   script_timestamp_repr.mli script_timestamp_repr.ml
   michelson_v1_primitives.mli michelson_v1_primitives.ml
   script_repr.mli script_repr.ml
   legacy_script_support_repr.mli legacy_script_support_repr.ml
   contract_repr.mli contract_repr.ml
   roll_repr.mli roll_repr.ml
   vote_repr.mli vote_repr.ml
   block_header_repr.mli block_header_repr.ml
   operation_repr.mli operation_repr.ml
   manager_repr.mli manager_repr.ml
   commitment_repr.mli commitment_repr.ml
   parameters_repr.mli parameters_repr.ml
   raw_context.mli raw_context.ml
   storage_sigs.ml
   storage_functors.mli storage_functors.ml
   storage.mli storage.ml
   constants_storage.ml
   level_storage.mli level_storage.ml
   nonce_storage.mli nonce_storage.ml
   seed_storage.mli seed_storage.ml
   roll_storage.mli roll_storage.ml
   delegate_storage.mli delegate_storage.ml
   contract_storage.mli contract_storage.ml
   bootstrap_storage.mli bootstrap_storage.ml
   fitness_storage.ml
   vote_storage.mli vote_storage.ml
   commitment_storage.mli commitment_storage.ml
   init_storage.ml
   fees_storage.mli fees_storage.ml
   alpha_context.mli alpha_context.ml
   script_typed_ir.ml
   script_tc_errors.ml
   michelson_v1_gas.mli michelson_v1_gas.ml
   script_ir_annot.mli script_ir_annot.ml
   script_ir_translator.mli script_ir_translator.ml
   script_tc_errors_registration.ml
   script_interpreter.mli script_interpreter.ml
   baking.mli baking.ml
   amendment.mli amendment.ml
   apply_results.mli apply_results.ml
   apply.ml
   services_registration.ml
   constants_services.mli constants_services.ml
   contract_services.mli contract_services.ml
   delegate_services.mli delegate_services.ml
   helpers_services.mli helpers_services.ml
   voting_services.mli voting_services.ml
   alpha_services.mli alpha_services.ml
   main.mli main.ml
   (:src_dir TEZOS_PROTOCOL))
 (action
  (with-stdout-to %{targets}
                  (chdir %{workspace_root} (run %{bin:tezos-embedded-protocol-packer} "%{src_dir}" "005_PsBABY5H")))))

(rule
 (targets functor.ml)
 (deps
   misc.mli misc.ml
   storage_description.mli storage_description.ml
   state_hash.ml
   nonce_hash.ml
   script_expr_hash.ml
   contract_hash.ml
   blinded_public_key_hash.mli blinded_public_key_hash.ml
   qty_repr.ml
   tez_repr.mli tez_repr.ml
   period_repr.mli period_repr.ml
   time_repr.mli time_repr.ml
   constants_repr.ml
   fitness_repr.ml
   raw_level_repr.mli raw_level_repr.ml
   voting_period_repr.mli voting_period_repr.ml
   cycle_repr.mli cycle_repr.ml
   level_repr.mli level_repr.ml
   seed_repr.mli seed_repr.ml
   gas_limit_repr.mli gas_limit_repr.ml
   script_int_repr.mli script_int_repr.ml
   script_timestamp_repr.mli script_timestamp_repr.ml
   michelson_v1_primitives.mli michelson_v1_primitives.ml
   script_repr.mli script_repr.ml
   legacy_script_support_repr.mli legacy_script_support_repr.ml
   contract_repr.mli contract_repr.ml
   roll_repr.mli roll_repr.ml
   vote_repr.mli vote_repr.ml
   block_header_repr.mli block_header_repr.ml
   operation_repr.mli operation_repr.ml
   manager_repr.mli manager_repr.ml
   commitment_repr.mli commitment_repr.ml
   parameters_repr.mli parameters_repr.ml
   raw_context.mli raw_context.ml
   storage_sigs.ml
   storage_functors.mli storage_functors.ml
   storage.mli storage.ml
   constants_storage.ml
   level_storage.mli level_storage.ml
   nonce_storage.mli nonce_storage.ml
   seed_storage.mli seed_storage.ml
   roll_storage.mli roll_storage.ml
   delegate_storage.mli delegate_storage.ml
   contract_storage.mli contract_storage.ml
   bootstrap_storage.mli bootstrap_storage.ml
   fitness_storage.ml
   vote_storage.mli vote_storage.ml
   commitment_storage.mli commitment_storage.ml
   init_storage.ml
   fees_storage.mli fees_storage.ml
   alpha_context.mli alpha_context.ml
   script_typed_ir.ml
   script_tc_errors.ml
   michelson_v1_gas.mli michelson_v1_gas.ml
   script_ir_annot.mli script_ir_annot.ml
   script_ir_translator.mli script_ir_translator.ml
   script_tc_errors_registration.ml
   script_interpreter.mli script_interpreter.ml
   baking.mli baking.ml
   amendment.mli amendment.ml
   apply_results.mli apply_results.ml
   apply.ml
   services_registration.ml
   constants_services.mli constants_services.ml
   contract_services.mli contract_services.ml
   delegate_services.mli delegate_services.ml
   helpers_services.mli helpers_services.ml
   voting_services.mli voting_services.ml
   alpha_services.mli alpha_services.ml
   main.mli main.ml
   (:src_dir TEZOS_PROTOCOL))
 (action (with-stdout-to %{targets}
                         (chdir %{workspace_root}
                                (run %{bin:tezos-protocol-compiler.tezos-protocol-packer} %{src_dir})))))

(rule
 (targets protocol.ml)
 (deps
   misc.mli misc.ml
   storage_description.mli storage_description.ml
   state_hash.ml
   nonce_hash.ml
   script_expr_hash.ml
   contract_hash.ml
   blinded_public_key_hash.mli blinded_public_key_hash.ml
   qty_repr.ml
   tez_repr.mli tez_repr.ml
   period_repr.mli period_repr.ml
   time_repr.mli time_repr.ml
   constants_repr.ml
   fitness_repr.ml
   raw_level_repr.mli raw_level_repr.ml
   voting_period_repr.mli voting_period_repr.ml
   cycle_repr.mli cycle_repr.ml
   level_repr.mli level_repr.ml
   seed_repr.mli seed_repr.ml
   gas_limit_repr.mli gas_limit_repr.ml
   script_int_repr.mli script_int_repr.ml
   script_timestamp_repr.mli script_timestamp_repr.ml
   michelson_v1_primitives.mli michelson_v1_primitives.ml
   script_repr.mli script_repr.ml
   legacy_script_support_repr.mli legacy_script_support_repr.ml
   contract_repr.mli contract_repr.ml
   roll_repr.mli roll_repr.ml
   vote_repr.mli vote_repr.ml
   block_header_repr.mli block_header_repr.ml
   operation_repr.mli operation_repr.ml
   manager_repr.mli manager_repr.ml
   commitment_repr.mli commitment_repr.ml
   parameters_repr.mli parameters_repr.ml
   raw_context.mli raw_context.ml
   storage_sigs.ml
   storage_functors.mli storage_functors.ml
   storage.mli storage.ml
   constants_storage.ml
   level_storage.mli level_storage.ml
   nonce_storage.mli nonce_storage.ml
   seed_storage.mli seed_storage.ml
   roll_storage.mli roll_storage.ml
   delegate_storage.mli delegate_storage.ml
   contract_storage.mli contract_storage.ml
   bootstrap_storage.mli bootstrap_storage.ml
   fitness_storage.ml
   vote_storage.mli vote_storage.ml
   commitment_storage.mli commitment_storage.ml
   init_storage.ml
   fees_storage.mli fees_storage.ml
   alpha_context.mli alpha_context.ml
   script_typed_ir.ml
   script_tc_errors.ml
   michelson_v1_gas.mli michelson_v1_gas.ml
   script_ir_annot.mli script_ir_annot.ml
   script_ir_translator.mli script_ir_translator.ml
   script_tc_errors_registration.ml
   script_interpreter.mli script_interpreter.ml
   baking.mli baking.ml
   amendment.mli amendment.ml
   apply_results.mli apply_results.ml
   apply.ml
   services_registration.ml
   constants_services.mli constants_services.ml
   contract_services.mli contract_services.ml
   delegate_services.mli delegate_services.ml
   helpers_services.mli helpers_services.ml
   voting_services.mli voting_services.ml
   alpha_services.mli alpha_services.ml
   main.mli main.ml)
 (action
  (write-file %{targets}
    "module Environment = Tezos_protocol_environment_005_PsBABY5H.Environment
let hash = Tezos_crypto.Protocol_hash.of_b58check_exn \"PsBABY5HQTSkA4297zNHfsZNKtxULfL18y95qb3m53QJiXGmrbU\"
let name = Environment.Name.name
include Tezos_raw_protocol_005_PsBABY5H
include Tezos_raw_protocol_005_PsBABY5H.Main
")))

(library
 (name tezos_protocol_environment_005_PsBABY5H)
 (instrumentation (backend bisect_ppx))
 (public_name tezos-protocol-005-PsBABY5H.environment)
 (library_flags (:standard -linkall))
 (libraries tezos-protocol-environment)
 (modules Environment))

(library
 (name tezos_raw_protocol_005_PsBABY5H)
 (instrumentation (backend bisect_ppx))
 (public_name tezos-protocol-005-PsBABY5H.raw)
 (libraries tezos_protocol_environment_005_PsBABY5H)
 (library_flags (:standard -linkall))
 (flags (:standard -nopervasives -nostdlib
                   -w +a-4-6-7-9-16-29-32-40..42-44-45-48-60-67-68
                   -warn-error +a
                   -open Tezos_protocol_environment_005_PsBABY5H__Environment
                   -open Pervasives
                   -open Error_monad))
 (modules
   Misc
   Storage_description
   State_hash
   Nonce_hash
   Script_expr_hash
   Contract_hash
   Blinded_public_key_hash
   Qty_repr
   Tez_repr
   Period_repr
   Time_repr
   Constants_repr
   Fitness_repr
   Raw_level_repr
   Voting_period_repr
   Cycle_repr
   Level_repr
   Seed_repr
   Gas_limit_repr
   Script_int_repr
   Script_timestamp_repr
   Michelson_v1_primitives
   Script_repr
   Legacy_script_support_repr
   Contract_repr
   Roll_repr
   Vote_repr
   Block_header_repr
   Operation_repr
   Manager_repr
   Commitment_repr
   Parameters_repr
   Raw_context
   Storage_sigs
   Storage_functors
   Storage
   Constants_storage
   Level_storage
   Nonce_storage
   Seed_storage
   Roll_storage
   Delegate_storage
   Contract_storage
   Bootstrap_storage
   Fitness_storage
   Vote_storage
   Commitment_storage
   Init_storage
   Fees_storage
   Alpha_context
   Script_typed_ir
   Script_tc_errors
   Michelson_v1_gas
   Script_ir_annot
   Script_ir_translator
   Script_tc_errors_registration
   Script_interpreter
   Baking
   Amendment
   Apply_results
   Apply
   Services_registration
   Constants_services
   Contract_services
   Delegate_services
   Helpers_services
   Voting_services
   Alpha_services
   Main))

(install
 (section lib)
 (package tezos-protocol-005-PsBABY5H)
 (files (TEZOS_PROTOCOL as raw/TEZOS_PROTOCOL)))

(library
 (name tezos_protocol_005_PsBABY5H)
 (instrumentation (backend bisect_ppx))
 (public_name tezos-protocol-005-PsBABY5H)
 (libraries
      tezos-protocol-environment
      tezos-protocol-environment-sigs
      tezos_raw_protocol_005_PsBABY5H)
 (flags -w "+a-4-6-7-9-16-29-40..42-44-45-48-60-67-68"
        -warn-error "-A"
        -nopervasives)
 (modules Protocol))

(library
 (name tezos_protocol_005_PsBABY5H_functor)
 (instrumentation (backend bisect_ppx))
 (public_name tezos-protocol-functor-005-PsBABY5H)
 (libraries
      tezos-protocol-environment
      tezos-protocol-environment-sigs
      tezos-protocol-005-PsBABY5H.raw)
 (flags -w "+a-4-6-7-9-16-29-40..42-44-45-48-60-67-68"
        -warn-error "-A"
        -nopervasives)
 (modules Functor))

(library
 (name tezos_embedded_protocol_005_PsBABY5H)
 (instrumentation (backend bisect_ppx))
 (public_name tezos-embedded-protocol-005-PsBABY5H)
 (library_flags (:standard -linkall))
 (libraries tezos-protocol-005-PsBABY5H
            tezos-protocol-updater
            tezos-protocol-environment)
 (flags (:standard -w +a-4-6-7-9-16-29-32-40..42-44-45-48-60-67
                   -warn-error +a))
 (modules Registerer))

(rule
 (alias runtest_compile_protocol)
 (deps
   misc.mli misc.ml
   storage_description.mli storage_description.ml
   state_hash.ml
   nonce_hash.ml
   script_expr_hash.ml
   contract_hash.ml
   blinded_public_key_hash.mli blinded_public_key_hash.ml
   qty_repr.ml
   tez_repr.mli tez_repr.ml
   period_repr.mli period_repr.ml
   time_repr.mli time_repr.ml
   constants_repr.ml
   fitness_repr.ml
   raw_level_repr.mli raw_level_repr.ml
   voting_period_repr.mli voting_period_repr.ml
   cycle_repr.mli cycle_repr.ml
   level_repr.mli level_repr.ml
   seed_repr.mli seed_repr.ml
   gas_limit_repr.mli gas_limit_repr.ml
   script_int_repr.mli script_int_repr.ml
   script_timestamp_repr.mli script_timestamp_repr.ml
   michelson_v1_primitives.mli michelson_v1_primitives.ml
   script_repr.mli script_repr.ml
   legacy_script_support_repr.mli legacy_script_support_repr.ml
   contract_repr.mli contract_repr.ml
   roll_repr.mli roll_repr.ml
   vote_repr.mli vote_repr.ml
   block_header_repr.mli block_header_repr.ml
   operation_repr.mli operation_repr.ml
   manager_repr.mli manager_repr.ml
   commitment_repr.mli commitment_repr.ml
   parameters_repr.mli parameters_repr.ml
   raw_context.mli raw_context.ml
   storage_sigs.ml
   storage_functors.mli storage_functors.ml
   storage.mli storage.ml
   constants_storage.ml
   level_storage.mli level_storage.ml
   nonce_storage.mli nonce_storage.ml
   seed_storage.mli seed_storage.ml
   roll_storage.mli roll_storage.ml
   delegate_storage.mli delegate_storage.ml
   contract_storage.mli contract_storage.ml
   bootstrap_storage.mli bootstrap_storage.ml
   fitness_storage.ml
   vote_storage.mli vote_storage.ml
   commitment_storage.mli commitment_storage.ml
   init_storage.ml
   fees_storage.mli fees_storage.ml
   alpha_context.mli alpha_context.ml
   script_typed_ir.ml
   script_tc_errors.ml
   michelson_v1_gas.mli michelson_v1_gas.ml
   script_ir_annot.mli script_ir_annot.ml
   script_ir_translator.mli script_ir_translator.ml
   script_tc_errors_registration.ml
   script_interpreter.mli script_interpreter.ml
   baking.mli baking.ml
   amendment.mli amendment.ml
   apply_results.mli apply_results.ml
   apply.ml
   services_registration.ml
   constants_services.mli constants_services.ml
   contract_services.mli contract_services.ml
   delegate_services.mli delegate_services.ml
   helpers_services.mli helpers_services.ml
   voting_services.mli voting_services.ml
   alpha_services.mli alpha_services.ml
   main.mli main.ml
  (:src_dir TEZOS_PROTOCOL))
 (action (run %{bin:tezos-protocol-compiler}  .)))

(rule
 (alias runtest_sandbox)
 (deps .tezos_protocol_005_PsBABY5H.objs/native/tezos_protocol_005_PsBABY5H.cmx)
 (action (progn)))

(rule
 (alias runtest)
 (package tezos-protocol-005-PsBABY5H)
 (deps (alias runtest_sandbox))
 (action (progn)))
