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

let check_client_node_proto_agree (rpc_context : #RPC_context.simple)
    (proto_hash : Protocol_hash.t)
    (chain : Tezos_shell_services.Block_services.chain)
    (block : Tezos_shell_services.Block_services.block) : unit tzresult Lwt.t =
  Tezos_shell_services.Block_services.protocols rpc_context ~chain ~block ()
  >>=? fun {current_protocol; _} ->
  if Protocol_hash.equal current_protocol proto_hash then return_unit
  else
    failwith
      "Protocol passed to the proxy (%a) and protocol of the node (%a) differ."
      Protocol_hash.pp
      proto_hash
      Protocol_hash.pp
      current_protocol

let get_node_protocol (rpc_context : #RPC_context.simple)
    (chain : Tezos_shell_services.Block_services.chain)
    (block : Tezos_shell_services.Block_services.block) :
    Protocol_hash.t tzresult Lwt.t =
  Tezos_shell_services.Block_services.protocols rpc_context ~chain ~block ()
  >>=? fun {current_protocol; _} -> return current_protocol

module type Proxy_sig = sig
  val protocol_hash : Protocol_hash.t

  (** RPCs provided by the protocol *)
  val directory : Tezos_protocol_environment.rpc_context RPC_directory.t

  (** How to build the context to execute RPCs on *)
  val init_env_rpc_context :
    Tezos_client_base.Client_context.printer ->
    RPC_context.json ->
    Tezos_shell_services.Block_services.chain ->
    Tezos_shell_services.Block_services.block ->
    Tezos_protocol_environment.rpc_context tzresult Lwt.t
end

type proxy_environment = (module Proxy_sig)

let registered : proxy_environment list ref = ref []

let register_proxy_context m =
  let (module INCOMING_P : Proxy_sig) = m in
  if
    List.exists
      (fun (module P : Proxy_sig) ->
        Protocol_hash.(P.protocol_hash = INCOMING_P.protocol_hash))
      !registered
  then
    raise
    @@ Invalid_argument
         (Format.asprintf
            "A proxy environment for protocol %a is registered already"
            Protocol_hash.pp
            INCOMING_P.protocol_hash)
  else registered := m :: !registered

let get_registered_proxy (printer : Tezos_client_base.Client_context.printer)
    (rpc_context : #RPC_context.simple)
    (protocol_hash_opt : Protocol_hash.t option)
    (chain : Tezos_shell_services.Block_services.chain)
    (block : Tezos_shell_services.Block_services.block) :
    proxy_environment tzresult Lwt.t =
  ( match protocol_hash_opt with
  | None ->
      get_node_protocol rpc_context chain block
      >>=? fun protocol_hash ->
      printer#warning
        "protocol of proxy unspecified, using the node's protocol: %a"
        Protocol_hash.pp
        protocol_hash
      >>= fun _ -> return protocol_hash
  | Some protocol_hash ->
      return protocol_hash )
  >>=? fun protocol_hash ->
  check_client_node_proto_agree rpc_context protocol_hash chain block
  >>=? fun _ ->
  let available = !registered in
  let proxy_opt =
    List.find_opt
      (fun (module Proxy : Proxy_sig) ->
        Protocol_hash.equal protocol_hash Proxy.protocol_hash)
      available
  in
  match proxy_opt with
  | Some proxy ->
      return proxy
  | None -> (
    match available with
    | [] ->
        failwith
          "There are no proxy environments registered. --mode proxy cannot be \
           honored."
    | fst_available :: _ ->
        let (module Proxy : Proxy_sig) = fst_available in
        let fst_available_proto = Proxy.protocol_hash in
        printer#warning
          "requested protocol (%a) not found in available proxy environments: \
           %a@;\
           Proceeding with the first available protocol (%a). This will work \
           if the mismatch is harmless, otherwise deserialization is the \
           failure most likely to happen."
          Protocol_hash.pp
          protocol_hash
          (Format.pp_print_list ~pp_sep:Format.pp_print_space Protocol_hash.pp)
          ((List.map (fun (module P : Proxy_sig) -> P.protocol_hash)) available)
          Protocol_hash.pp
          fst_available_proto
        >>= fun () -> return fst_available )