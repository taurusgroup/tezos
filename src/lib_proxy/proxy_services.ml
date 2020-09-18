(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2020 Nomadic Labs, <contact@nomadic-labs.com>               *)
(*                                                                           *)
(* Permission is hereby granted, free of charge, to any person obtaining a   *)
(* copy of this software and associated documentation files (the "Software"),*)
(* to deal in the Software without restriction, including without limitation *)
(* the rights to use, copy, modify, merge, publish, distribute, sublicense,  *)
(* and/or sell copies of the Software, and to permit persons to whom the     *)
(* Software is furnished to do so, subject to the following conditions:      *)
(*                                                                           *)
(* The above copyright notice and this permission notice shall be included   *)
(* in all copies or substantial portions of the Software.                    *)
(*                                                                           *)
(* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR*)
(* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,  *)
(* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL   *)
(* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER*)
(* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING   *)
(* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER       *)
(* DEALINGS IN THE SOFTWARE.                                                 *)
(*                                                                           *)
(*****************************************************************************)

module type BLOCK_TO_HASH = sig
  val hash_of_block :
    #RPC_context.simple ->
    Tezos_shell_services.Shell_services.chain ->
    Tezos_shell_services.Block_services.block ->
    Block_hash.t tzresult Lwt.t
end

module Hashtbl = Stdlib.Hashtbl

module BlockToHash (S : Registration.Proxy_sig) : BLOCK_TO_HASH = struct
  let raw_hash_of_block (block : Tezos_shell_services.Block_services.block) :
      Block_hash.t option =
    match block with
    | `Hash (h, 0) ->
        Some h
    | `Alias (_, _) | `Genesis | `Head _ | `Level _ | `Hash (_, _) ->
        None

  let table = Hashtbl.create 17

  let hash_of_block (rpc_context : #RPC_context.simple)
      (chain : Tezos_shell_services.Shell_services.chain)
      (block : Tezos_shell_services.Block_services.block) =
    match raw_hash_of_block block with
    | Some h ->
        (* Block is defined by its hash *)
        return h
    | None -> (
      match Hashtbl.find_opt table (chain, block) with
      | Some hash ->
          (* Result is in cache *)
          return hash
      | None ->
          (* Need to do an RPC call to get the hash *)
          S.hash rpc_context ~chain ~block ()
          >>=? fun hash ->
          (* Fill cache with result *)
          Hashtbl.add table (chain, block) hash ;
          return hash )
end

let build_directory (printer : Tezos_client_base.Client_context.printer)
    (rpc_context : RPC_context.json)
    (proxy_env : Registration.proxy_environment) : unit RPC_directory.t =
  let (module Proxy_environment) = proxy_env in
  let module B2H = BlockToHash (Proxy_environment) in
  let envs_cache = Hashtbl.create 17 in
  let get_env_rpc_context chain block =
    B2H.hash_of_block rpc_context chain block
    >>=? fun block_hash ->
    let key = (chain, block_hash) in
    match Hashtbl.find_opt envs_cache key with
    | None ->
        Proxy_environment.init_env_rpc_context
          printer
          rpc_context
          chain
          (`Hash (block_hash, 0))
        >>=? fun rpc_context ->
        Hashtbl.add envs_cache key rpc_context ;
        return rpc_context
    | Some cached ->
        return cached
  in
  let get_env_rpc_context' chain block =
    get_env_rpc_context chain block
    >>= fun result ->
    match result with
    | Ok x ->
        Lwt.return x
    | Error err ->
        Error_monad.pp_print_error Format.err_formatter err ;
        (* Is there something better we can do!? I'm asking because
           proto_directory expects a unit Directory.t Lwt.t,
           we can't give it a unit tzresult Directory.t Lwt.t *)
        assert false
  in
  let proto_directory =
    let ( // ) = RPC_directory.prefix in
    (* register protocol-specific RPCs *)
    Tezos_shell_services.Chain_services.path
    // ( Tezos_shell_services.Block_services.path
       // (* The Tezos_protocol_environment.rpc_context values returned
            by init_env_rpc_context contain proxy_getter's RPC
            cache. We wanna keep it in between RPC calls, hence
            the use of get_env_rpc_context' to cache init_env_rpc_context
            values. *)
          RPC_directory.map
            (fun ((_, chain), block) -> get_env_rpc_context' chain block)
            Proxy_environment.directory )
  in
  RPC_directory.register_describe_directory_service
    proto_directory
    RPC_service.description_service
