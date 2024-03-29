(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(* Copyright (c) 2020 Metastate AG <hello@metastate.dev>                     *)
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

open Alpha_context

type info = {
  balance : Tez.t;
  frozen_balance : Tez.t;
  frozen_balance_by_cycle : Delegate.frozen_balance Cycle.Map.t;
  staking_balance : Tez.t;
  delegated_contracts : Contract.t list;
  delegated_balance : Tez.t;
  deactivated : bool;
  grace_period : Cycle.t;
  voting_power : int32;
}

let info_encoding =
  let open Data_encoding in
  conv
    (fun {
           balance;
           frozen_balance;
           frozen_balance_by_cycle;
           staking_balance;
           delegated_contracts;
           delegated_balance;
           deactivated;
           grace_period;
           voting_power;
         } ->
      ( balance,
        frozen_balance,
        frozen_balance_by_cycle,
        staking_balance,
        delegated_contracts,
        delegated_balance,
        deactivated,
        grace_period,
        voting_power ))
    (fun ( balance,
           frozen_balance,
           frozen_balance_by_cycle,
           staking_balance,
           delegated_contracts,
           delegated_balance,
           deactivated,
           grace_period,
           voting_power ) ->
      {
        balance;
        frozen_balance;
        frozen_balance_by_cycle;
        staking_balance;
        delegated_contracts;
        delegated_balance;
        deactivated;
        grace_period;
        voting_power;
      })
    (obj9
       (req "balance" Tez.encoding)
       (req "frozen_balance" Tez.encoding)
       (req "frozen_balance_by_cycle" Delegate.frozen_balance_by_cycle_encoding)
       (req "staking_balance" Tez.encoding)
       (req "delegated_contracts" (list Contract.encoding))
       (req "delegated_balance" Tez.encoding)
       (req "deactivated" bool)
       (req "grace_period" Cycle.encoding)
       (req "voting_power" int32))

module S = struct
  let raw_path = RPC_path.(open_root / "context" / "delegates")

  open Data_encoding

  type list_query = {active : bool; inactive : bool}

  let list_query : list_query RPC_query.t =
    let open RPC_query in
    query (fun active inactive -> {active; inactive})
    |+ flag "active" (fun t -> t.active)
    |+ flag "inactive" (fun t -> t.inactive)
    |> seal

  let list_delegate =
    RPC_service.get_service
      ~description:"Lists all registered delegates."
      ~query:list_query
      ~output:(list Signature.Public_key_hash.encoding)
      raw_path

  let path = RPC_path.(raw_path /: Signature.Public_key_hash.rpc_arg)

  let info =
    RPC_service.get_service
      ~description:"Everything about a delegate."
      ~query:RPC_query.empty
      ~output:info_encoding
      path

  let balance =
    RPC_service.get_service
      ~description:
        "Returns the full balance of a given delegate, including the frozen \
         balances."
      ~query:RPC_query.empty
      ~output:Tez.encoding
      RPC_path.(path / "balance")

  let frozen_balance =
    RPC_service.get_service
      ~description:
        "Returns the total frozen balances of a given delegate, this includes \
         the frozen deposits, rewards and fees."
      ~query:RPC_query.empty
      ~output:Tez.encoding
      RPC_path.(path / "frozen_balance")

  let frozen_balance_by_cycle =
    RPC_service.get_service
      ~description:
        "Returns the frozen balances of a given delegate, indexed by the cycle \
         by which it will be unfrozen"
      ~query:RPC_query.empty
      ~output:Delegate.frozen_balance_by_cycle_encoding
      RPC_path.(path / "frozen_balance_by_cycle")

  let staking_balance =
    RPC_service.get_service
      ~description:
        "Returns the total amount of tokens delegated to a given delegate. \
         This includes the balances of all the contracts that delegate to it, \
         but also the balance of the delegate itself and its frozen fees and \
         deposits. The rewards do not count in the delegated balance until \
         they are unfrozen."
      ~query:RPC_query.empty
      ~output:Tez.encoding
      RPC_path.(path / "staking_balance")

  let delegated_contracts =
    RPC_service.get_service
      ~description:
        "Returns the list of contracts that delegate to a given delegate."
      ~query:RPC_query.empty
      ~output:(list Contract.encoding)
      RPC_path.(path / "delegated_contracts")

  let delegated_balance =
    RPC_service.get_service
      ~description:
        "Returns the balances of all the contracts that delegate to a given \
         delegate. This excludes the delegate's own balance and its frozen \
         balances."
      ~query:RPC_query.empty
      ~output:Tez.encoding
      RPC_path.(path / "delegated_balance")

  let deactivated =
    RPC_service.get_service
      ~description:
        "Tells whether the delegate is currently tagged as deactivated or not."
      ~query:RPC_query.empty
      ~output:bool
      RPC_path.(path / "deactivated")

  let grace_period =
    RPC_service.get_service
      ~description:
        "Returns the cycle by the end of which the delegate might be \
         deactivated if she fails to execute any delegate action. A \
         deactivated delegate might be reactivated (without loosing any rolls) \
         by simply re-registering as a delegate. For deactivated delegates, \
         this value contains the cycle by which they were deactivated."
      ~query:RPC_query.empty
      ~output:Cycle.encoding
      RPC_path.(path / "grace_period")

  let voting_power =
    RPC_service.get_service
      ~description:
        "The number of rolls in the vote listings for a given delegate"
      ~query:RPC_query.empty
      ~output:Data_encoding.int32
      RPC_path.(path / "voting_power")
end

let delegate_register () =
  let open Services_registration in
  register0 ~chunked:true S.list_delegate (fun ctxt q () ->
      Delegate.list ctxt >>= fun delegates ->
      match q with
      | {active = true; inactive = false} ->
          List.filter_es
            (fun pkh -> Delegate.deactivated ctxt pkh >|=? not)
            delegates
      | {active = false; inactive = true} ->
          List.filter_es (fun pkh -> Delegate.deactivated ctxt pkh) delegates
      | _ -> return delegates) ;
  register1 ~chunked:false S.info (fun ctxt pkh () () ->
      Delegate.full_balance ctxt pkh >>=? fun balance ->
      Delegate.frozen_balance ctxt pkh >>=? fun frozen_balance ->
      Delegate.frozen_balance_by_cycle ctxt pkh
      >>= fun frozen_balance_by_cycle ->
      Delegate.staking_balance ctxt pkh >>=? fun staking_balance ->
      Delegate.delegated_contracts ctxt pkh >>= fun delegated_contracts ->
      Delegate.delegated_balance ctxt pkh >>=? fun delegated_balance ->
      Delegate.deactivated ctxt pkh >>=? fun deactivated ->
      Delegate.grace_period ctxt pkh >>=? fun grace_period ->
      Vote.get_voting_power_free ctxt pkh >|=? fun voting_power ->
      {
        balance;
        frozen_balance;
        frozen_balance_by_cycle;
        staking_balance;
        delegated_contracts;
        delegated_balance;
        deactivated;
        grace_period;
        voting_power;
      }) ;
  register1 ~chunked:false S.balance (fun ctxt pkh () () ->
      Delegate.full_balance ctxt pkh) ;
  register1 ~chunked:false S.frozen_balance (fun ctxt pkh () () ->
      Delegate.frozen_balance ctxt pkh) ;
  register1 ~chunked:true S.frozen_balance_by_cycle (fun ctxt pkh () () ->
      Delegate.frozen_balance_by_cycle ctxt pkh >|= ok) ;
  register1 ~chunked:false S.staking_balance (fun ctxt pkh () () ->
      Delegate.staking_balance ctxt pkh) ;
  register1 ~chunked:true S.delegated_contracts (fun ctxt pkh () () ->
      Delegate.delegated_contracts ctxt pkh >|= ok) ;
  register1 ~chunked:false S.delegated_balance (fun ctxt pkh () () ->
      Delegate.delegated_balance ctxt pkh) ;
  register1 ~chunked:false S.deactivated (fun ctxt pkh () () ->
      Delegate.deactivated ctxt pkh) ;
  register1 ~chunked:false S.grace_period (fun ctxt pkh () () ->
      Delegate.grace_period ctxt pkh) ;
  register1 ~chunked:false S.voting_power (fun ctxt pkh () () ->
      Vote.get_voting_power_free ctxt pkh)

let list ctxt block ?(active = true) ?(inactive = false) () =
  RPC_context.make_call0 S.list_delegate ctxt block {active; inactive} ()

let info ctxt block pkh = RPC_context.make_call1 S.info ctxt block pkh () ()

let balance ctxt block pkh =
  RPC_context.make_call1 S.balance ctxt block pkh () ()

let frozen_balance ctxt block pkh =
  RPC_context.make_call1 S.frozen_balance ctxt block pkh () ()

let frozen_balance_by_cycle ctxt block pkh =
  RPC_context.make_call1 S.frozen_balance_by_cycle ctxt block pkh () ()

let staking_balance ctxt block pkh =
  RPC_context.make_call1 S.staking_balance ctxt block pkh () ()

let delegated_contracts ctxt block pkh =
  RPC_context.make_call1 S.delegated_contracts ctxt block pkh () ()

let delegated_balance ctxt block pkh =
  RPC_context.make_call1 S.delegated_balance ctxt block pkh () ()

let deactivated ctxt block pkh =
  RPC_context.make_call1 S.deactivated ctxt block pkh () ()

let grace_period ctxt block pkh =
  RPC_context.make_call1 S.grace_period ctxt block pkh () ()

let voting_power ctxt block pkh =
  RPC_context.make_call1 S.voting_power ctxt block pkh () ()

let requested_levels ~default ctxt cycles levels =
  match (levels, cycles) with
  | ([], []) -> ok [default]
  | (levels, cycles) ->
      (* explicitly fail when requested levels or cycle are in the past...
         or too far in the future... *)
      let levels =
        List.sort_uniq
          Level.compare
          (List.concat
             (List.map (Level.from_raw ctxt) levels
              :: List.map (Level.levels_in_cycle ctxt) cycles))
      in
      List.map_e
        (fun level ->
          let current_level = Level.current ctxt in
          if Level.(level <= current_level) then ok (level, None)
          else
            Baking.earlier_predecessor_timestamp ctxt level >|? fun timestamp ->
            (level, Some timestamp))
        levels

module Baking_rights = struct
  type t = {
    level : Raw_level.t;
    delegate : Signature.Public_key_hash.t;
    priority : int;
    timestamp : Timestamp.t option;
  }

  let encoding =
    let open Data_encoding in
    conv
      (fun {level; delegate; priority; timestamp} ->
        (level, delegate, priority, timestamp))
      (fun (level, delegate, priority, timestamp) ->
        {level; delegate; priority; timestamp})
      (obj4
         (req "level" Raw_level.encoding)
         (req "delegate" Signature.Public_key_hash.encoding)
         (req "priority" uint16)
         (opt "estimated_time" Timestamp.encoding))

  module S = struct
    open Data_encoding

    let custom_root = RPC_path.(open_root / "helpers" / "baking_rights")

    type baking_rights_query = {
      levels : Raw_level.t list;
      cycles : Cycle.t list;
      delegates : Signature.Public_key_hash.t list;
      max_priority : int option;
      all : bool;
    }

    let baking_rights_query =
      let open RPC_query in
      query (fun levels cycles delegates max_priority all ->
          {levels; cycles; delegates; max_priority; all})
      |+ multi_field "level" Raw_level.rpc_arg (fun t -> t.levels)
      |+ multi_field "cycle" Cycle.rpc_arg (fun t -> t.cycles)
      |+ multi_field "delegate" Signature.Public_key_hash.rpc_arg (fun t ->
             t.delegates)
      |+ opt_field "max_priority" RPC_arg.int (fun t -> t.max_priority)
      |+ flag "all" (fun t -> t.all)
      |> seal

    let baking_rights =
      RPC_service.get_service
        ~description:
          "Retrieves the list of delegates allowed to bake a block.\n\
           By default, it gives the best baking priorities for bakers that \
           have at least one opportunity below the 64th priority for the next \
           block.\n\
           Parameters `level` and `cycle` can be used to specify the (valid) \
           level(s) in the past or future at which the baking rights have to \
           be returned. When asked for (a) whole cycle(s), baking \
           opportunities are given by default up to the priority 8.\n\
           Parameter `delegate` can be used to restrict the results to the \
           given delegates. If parameter `all` is set, all the baking \
           opportunities for each baker at each level are returned, instead of \
           just the first one.\n\
           Returns the list of baking slots. Also returns the minimal \
           timestamps that correspond to these slots. The timestamps are \
           omitted for levels in the past, and are only estimates for levels \
           later that the next block, based on the hypothesis that all \
           predecessor blocks were baked at the first priority."
        ~query:baking_rights_query
        ~output:(list encoding)
        custom_root
  end

  let baking_priorities ctxt max_prio (level, pred_timestamp) =
    Baking.baking_priorities ctxt level >>=? fun contract_list ->
    let rec loop l acc priority =
      if Compare.Int.(priority > max_prio) then return (List.rev acc)
      else
        let (Misc.LCons (pk, next)) = l in
        let delegate = Signature.Public_key.hash pk in
        (match pred_timestamp with
        | None -> ok_none
        | Some pred_timestamp ->
            Baking.minimal_time
              (Constants.parametric ctxt)
              ~priority
              pred_timestamp
            >|? fun t -> Some t)
        >>?= fun timestamp ->
        let acc = {level = level.level; delegate; priority; timestamp} :: acc in
        next () >>=? fun l -> loop l acc (priority + 1)
    in
    loop contract_list [] 0

  let baking_priorities_of_delegates ctxt ~all ~max_prio delegates
      (level, pred_timestamp) =
    Baking.baking_priorities ctxt level >>=? fun contract_list ->
    let rec loop l acc priority delegates =
      match delegates with
      | [] -> return (List.rev acc)
      | _ :: _ -> (
          if Compare.Int.(priority > max_prio) then return (List.rev acc)
          else
            let (Misc.LCons (pk, next)) = l in
            next () >>=? fun l ->
            match
              List.partition
                (fun (pk', _) -> Signature.Public_key.equal pk pk')
                delegates
            with
            | ([], _) -> loop l acc (priority + 1) delegates
            | ((_, delegate) :: _, delegates') ->
                (match pred_timestamp with
                | None -> ok_none
                | Some pred_timestamp ->
                    Baking.minimal_time
                      (Constants.parametric ctxt)
                      ~priority
                      pred_timestamp
                    >|? fun t -> Some t)
                >>?= fun timestamp ->
                let acc =
                  {level = level.level; delegate; priority; timestamp} :: acc
                in
                let delegates'' = if all then delegates else delegates' in
                loop l acc (priority + 1) delegates'')
    in
    loop contract_list [] 0 delegates

  let remove_duplicated_delegates rights =
    List.rev @@ fst
    @@ List.fold_left
         (fun (acc, previous) r ->
           if Signature.Public_key_hash.Set.mem r.delegate previous then
             (acc, previous)
           else (r :: acc, Signature.Public_key_hash.Set.add r.delegate previous))
         ([], Signature.Public_key_hash.Set.empty)
         rights

  let register () =
    let open Services_registration in
    register0 ~chunked:true S.baking_rights (fun ctxt q () ->
        requested_levels
          ~default:
            (Level.succ ctxt (Level.current ctxt), Some (Timestamp.current ctxt))
          ctxt
          q.cycles
          q.levels
        >>?= fun levels ->
        let max_priority =
          match q.max_priority with
          | Some max -> max
          | None -> ( match q.cycles with [] -> 64 | _ :: _ -> 8)
        in
        match q.delegates with
        | [] ->
            List.map_es (baking_priorities ctxt max_priority) levels
            >|=? fun rights ->
            let rights =
              if q.all then rights
              else List.map remove_duplicated_delegates rights
            in
            List.concat rights
        | _ :: _ as delegates ->
            List.filter_map_s
              (fun delegate ->
                Contract.get_manager_key ctxt delegate >>= function
                | Ok pk -> Lwt.return (Some (pk, delegate))
                | Error _ -> Lwt.return_none)
              delegates
            >>= fun delegates ->
            List.map_es
              (fun level ->
                baking_priorities_of_delegates
                  ctxt
                  ~all:q.all
                  ~max_prio:max_priority
                  delegates
                  level)
              levels
            >|=? List.concat)

  let get ctxt ?(levels = []) ?(cycles = []) ?(delegates = []) ?(all = false)
      ?max_priority block =
    RPC_context.make_call0
      S.baking_rights
      ctxt
      block
      {levels; cycles; delegates; max_priority; all}
      ()
end

module Endorsing_rights = struct
  type t = {
    level : Raw_level.t;
    delegate : Signature.Public_key_hash.t;
    slots : int list;
    estimated_time : Time.t option;
  }

  let encoding =
    let open Data_encoding in
    conv
      (fun {level; delegate; slots; estimated_time} ->
        (level, delegate, slots, estimated_time))
      (fun (level, delegate, slots, estimated_time) ->
        {level; delegate; slots; estimated_time})
      (obj4
         (req "level" Raw_level.encoding)
         (req "delegate" Signature.Public_key_hash.encoding)
         (req "slots" (list uint16))
         (opt "estimated_time" Timestamp.encoding))

  module S = struct
    open Data_encoding

    let custom_root = RPC_path.(open_root / "helpers" / "endorsing_rights")

    type endorsing_rights_query = {
      levels : Raw_level.t list;
      cycles : Cycle.t list;
      delegates : Signature.Public_key_hash.t list;
    }

    let endorsing_rights_query =
      let open RPC_query in
      query (fun levels cycles delegates -> {levels; cycles; delegates})
      |+ multi_field "level" Raw_level.rpc_arg (fun t -> t.levels)
      |+ multi_field "cycle" Cycle.rpc_arg (fun t -> t.cycles)
      |+ multi_field "delegate" Signature.Public_key_hash.rpc_arg (fun t ->
             t.delegates)
      |> seal

    let endorsing_rights =
      RPC_service.get_service
        ~description:
          "Retrieves the delegates allowed to endorse a block.\n\
           By default, it gives the endorsement slots for delegates that have \
           at least one in the next block.\n\
           Parameters `level` and `cycle` can be used to specify the (valid) \
           level(s) in the past or future at which the endorsement rights have \
           to be returned. Parameter `delegate` can be used to restrict the \
           results to the given delegates.\n\
           Returns the list of endorsement slots. Also returns the minimal \
           timestamps that correspond to these slots. The timestamps are \
           omitted for levels in the past, and are only estimates for levels \
           later that the next block, based on the hypothesis that all \
           predecessor blocks were baked at the first priority."
        ~query:endorsing_rights_query
        ~output:(list encoding)
        custom_root
  end

  let endorsement_slots ctxt (level, estimated_time) =
    Baking.endorsement_rights ctxt level >|=? fun rights ->
    Signature.Public_key_hash.Map.fold
      (fun delegate (_, slots, _) acc ->
        {level = level.level; delegate; slots; estimated_time} :: acc)
      rights
      []

  let register () =
    let open Services_registration in
    register0 ~chunked:true S.endorsing_rights (fun ctxt q () ->
        requested_levels
          ~default:(Level.current ctxt, Some (Timestamp.current ctxt))
          ctxt
          q.cycles
          q.levels
        >>?= fun levels ->
        List.map_es (endorsement_slots ctxt) levels >|=? fun rights ->
        let rights = List.concat rights in
        match q.delegates with
        | [] -> rights
        | _ :: _ as delegates ->
            let is_requested p =
              List.exists (Signature.Public_key_hash.equal p.delegate) delegates
            in
            List.filter is_requested rights)

  let get ctxt ?(levels = []) ?(cycles = []) ?(delegates = []) block =
    RPC_context.make_call0
      S.endorsing_rights
      ctxt
      block
      {levels; cycles; delegates}
      ()
end

module Endorsing_power = struct
  let endorsing_power ctxt (operation, chain_id) =
    let (Operation_data data) = operation.protocol_data in
    match data.contents with
    | Single (Endorsement_with_slot {endorsement; slot}) ->
        Baking.check_endorsement_rights ctxt chain_id endorsement ~slot
        >|=? fun (_, slots, _) -> List.length slots
    | _ -> failwith "Operation is not a wrapped endorsement"

  module S = struct
    let endorsing_power =
      let open Data_encoding in
      RPC_service.post_service
        ~description:
          "Get the endorsing power of an endorsement, that is, the number of \
           slots that the endorser has"
        ~query:RPC_query.empty
        ~input:
          (obj2
             (req "endorsement_operation" Operation.encoding)
             (req "chain_id" Chain_id.encoding))
        ~output:int31
        RPC_path.(open_root / "endorsing_power")
  end

  let register () =
    let open Services_registration in
    register0 ~chunked:false S.endorsing_power (fun ctxt () (op, chain_id) ->
        endorsing_power ctxt (op, chain_id))

  let get ctxt block op chain_id =
    RPC_context.make_call0 S.endorsing_power ctxt block () (op, chain_id)
end

module Minimal_valid_time = struct
  let minimal_valid_time ctxt ~priority ~endorsing_power ~predecessor_timestamp
      =
    Baking.minimal_valid_time
      (Constants.parametric ctxt)
      ~priority
      ~endorsing_power
      ~predecessor_timestamp

  module S = struct
    type t = {priority : int; endorsing_power : int}

    let minimal_valid_time_query =
      let open RPC_query in
      query (fun priority endorsing_power -> {priority; endorsing_power})
      |+ field "priority" RPC_arg.int 0 (fun t -> t.priority)
      |+ field "endorsing_power" RPC_arg.int 0 (fun t -> t.endorsing_power)
      |> seal

    let minimal_valid_time =
      RPC_service.get_service
        ~description:
          "Minimal valid time for a block given a priority and an endorsing \
           power."
        ~query:minimal_valid_time_query
        ~output:Time.encoding
        RPC_path.(open_root / "minimal_valid_time")
  end

  let register () =
    let open Services_registration in
    register0
      ~chunked:false
      S.minimal_valid_time
      (fun ctxt {priority; endorsing_power} () ->
        let predecessor_timestamp = Timestamp.predecessor ctxt in
        Lwt.return
        @@ minimal_valid_time
             ctxt
             ~priority
             ~endorsing_power
             ~predecessor_timestamp)

  let get ctxt block priority endorsing_power =
    RPC_context.make_call0
      S.minimal_valid_time
      ctxt
      block
      {priority; endorsing_power}
      ()
end

let register () =
  delegate_register () ;
  Baking_rights.register () ;
  Endorsing_rights.register () ;
  Endorsing_power.register () ;
  Minimal_valid_time.register ()

let endorsement_rights ctxt level =
  Endorsing_rights.endorsement_slots ctxt (level, None) >|=? fun l ->
  List.map (fun {Endorsing_rights.delegate; _} -> delegate) l

let baking_rights ctxt max_priority =
  let max = match max_priority with None -> 64 | Some m -> m in
  let level = Level.current ctxt in
  Baking_rights.baking_priorities ctxt max (level, None) >|=? fun l ->
  ( level.level,
    List.map
      (fun {Baking_rights.delegate; timestamp; _} -> (delegate, timestamp))
      l )

let endorsing_power ctxt operation =
  Endorsing_power.endorsing_power ctxt operation

let minimal_valid_time ctxt priority endorsing_power predecessor_timestamp =
  Minimal_valid_time.minimal_valid_time
    ctxt
    ~priority
    ~endorsing_power
    ~predecessor_timestamp
