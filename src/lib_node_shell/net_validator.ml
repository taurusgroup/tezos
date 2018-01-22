(**************************************************************************)
(*                                                                        *)
(*    Copyright (c) 2014 - 2017.                                          *)
(*    Dynamic Ledger Solutions, Inc. <contact@tezos.com>                  *)
(*                                                                        *)
(*    All rights reserved. No warranty, explicit or implicit, provided.   *)
(*                                                                        *)
(**************************************************************************)

open Net_validator_worker_state

module Name = struct
  type t = Net_id.t
  let encoding = Net_id.encoding
  let base = [ "net_validator" ]
  let pp = Net_id.pp_short
end

module Request = struct
  include Request
  type _ t = Validated : State.Block.t -> Event.update t
  let view (type a) (Validated block : a t) : view =
    State.Block.hash block
end

type limits = {
  bootstrap_threshold: int ;
  worker_limits: Worker_types.limits
}

module Types = struct
  include Worker_state

  type parameters = {
    parent: Name.t option ;
    db: Distributed_db.t ;
    net_state: State.Net.t ;
    net_db: Distributed_db.net_db ;
    block_validator: Block_validator.t ;
    global_valid_block_input: State.Block.t Lwt_watcher.input ;

    prevalidator_limits: Prevalidator.limits ;
    peer_validator_limits: Peer_validator.limits ;
    max_child_ttl: int option ;
    limits: limits;
  }

  type state = {
    parameters: parameters ;

    mutable bootstrapped: bool ;
    bootstrapped_waiter: unit Lwt.t ;
    bootstrapped_wakener: unit Lwt.u ;
    valid_block_input: State.Block.t Lwt_watcher.input ;
    new_head_input: State.Block.t Lwt_watcher.input ;

    mutable child:
      (state * (unit -> unit Lwt.t (* shutdown *))) option ;
    prevalidator: Prevalidator.t ;
    active_peers: Peer_validator.t Lwt.t P2p.Peer_id.Table.t ;
    bootstrapped_peers: unit P2p.Peer_id.Table.t ;
  }

  let view (state : state) _ : view =
    let { bootstrapped ; active_peers ; bootstrapped_peers } = state in
    { bootstrapped ;
      active_peers =
        P2p.Peer_id.Table.fold (fun id _ l -> id :: l) active_peers [] ;
      bootstrapped_peers =
        P2p.Peer_id.Table.fold (fun id _ l -> id :: l) bootstrapped_peers [] }
end

module Worker = Worker.Make (Name) (Event) (Request) (Types)

open Types

type t = Worker.infinite Worker.queue Worker.t

let table = Worker.create_table Queue

let shutdown w =
  Worker.shutdown w

let shutdown_child nv =
  Lwt_utils.may ~f:(fun (_, shutdown) -> shutdown ()) nv.child

let notify_new_block w block =
  let nv = Worker.state w in
  Option.iter nv.parameters.parent
    ~f:(fun id -> try
           let w = List.assoc id (Worker.list table) in
           let nv = Worker.state w in
           Lwt_watcher.notify nv.valid_block_input block
         with Not_found -> ()) ;
  Lwt_watcher.notify nv.valid_block_input block ;
  Lwt_watcher.notify nv.parameters.global_valid_block_input block ;
  Worker.push_request_now w (Validated block)

let may_toggle_bootstrapped_network w =
  let nv = Worker.state w in
  if not nv.bootstrapped &&
     P2p.Peer_id.Table.length nv.bootstrapped_peers >= nv.parameters.limits.bootstrap_threshold
  then begin
    nv.bootstrapped <- true ;
    Lwt.wakeup_later nv.bootstrapped_wakener () ;
  end

let may_activate_peer_validator w peer_id =
  let nv = Worker.state w in
  try P2p.Peer_id.Table.find nv.active_peers peer_id
  with Not_found ->
    let pv =
      Peer_validator.create
        ~notify_new_block:(notify_new_block w)
        ~notify_bootstrapped: begin fun () ->
          P2p.Peer_id.Table.add nv.bootstrapped_peers peer_id () ;
          may_toggle_bootstrapped_network w
        end
        ~notify_termination: begin fun _pv ->
          P2p.Peer_id.Table.remove nv.active_peers peer_id ;
          P2p.Peer_id.Table.remove nv.bootstrapped_peers peer_id ;
        end
        nv.parameters.peer_validator_limits
        nv.parameters.block_validator
        nv.parameters.net_db
        peer_id in
    P2p.Peer_id.Table.add nv.active_peers peer_id pv ;
    pv

let may_switch_test_network w spawn_child block =
  let nv = Worker.state w in
  let create_child genesis protocol expiration =
    if State.Net.allow_forked_network nv.parameters.net_state then begin
      shutdown_child nv >>= fun () ->
      begin
        let net_id = Net_id.of_block_hash (State.Block.hash genesis) in
        State.Net.get
          (State.Net.global_state nv.parameters.net_state) net_id >>= function
        | Ok net_state -> return net_state
        | Error _ ->
            State.fork_testnet
              genesis protocol expiration >>=? fun net_state ->
            Chain.head net_state >>= fun new_genesis_block ->
            Lwt_watcher.notify nv.parameters.global_valid_block_input new_genesis_block ;
            Lwt_watcher.notify nv.valid_block_input new_genesis_block ;
            return net_state
      end >>=? fun net_state ->
      spawn_child
        ~parent:(State.Net.id net_state)
        nv.parameters.peer_validator_limits
        nv.parameters.prevalidator_limits
        nv.parameters.block_validator
        nv.parameters.global_valid_block_input
        nv.parameters.db net_state
        nv.parameters.limits (* TODO: different limits main/test ? *) >>= fun child ->
      nv.child <- Some child ;
      return ()
    end else begin
      (* Ignoring request... *)
      return ()
    end in

  let check_child genesis protocol expiration current_time =
    let activated =
      match nv.child with
      | None -> false
      | Some (child , _) ->
          Block_hash.equal
            (State.Net.genesis child.parameters.net_state).block
            genesis in
    State.Block.read nv.parameters.net_state genesis >>=? fun genesis ->
    begin
      match nv.parameters.max_child_ttl with
      | None -> Lwt.return expiration
      | Some ttl ->
          Lwt.return
            (Time.min expiration
               (Time.add (State.Block.timestamp genesis) (Int64.of_int ttl)))
    end >>= fun local_expiration ->
    let expired = Time.(local_expiration <= current_time) in
    if expired && activated then
      shutdown_child nv >>= return
    else if not activated && not expired then
      create_child genesis protocol expiration
    else
      return () in

  begin
    let block_header = State.Block.header block in
    State.Block.test_network block >>= function
    | Not_running -> shutdown_child nv >>= return
    | Running { genesis ; protocol ; expiration } ->
        check_child genesis protocol expiration
          block_header.shell.timestamp
    | Forking { protocol ; expiration } ->
        create_child block protocol expiration
  end >>= function
  | Ok () -> Lwt.return_unit
  | Error err ->
      Worker.record_event w (Could_not_switch_testnet err) ;
      Lwt.return_unit

let broadcast_head w ~previous block =
  let nv = Worker.state w in
  if not nv.bootstrapped then
    Lwt.return_unit
  else begin
    begin
      State.Block.predecessor block >>= function
      | None -> Lwt.return_true
      | Some predecessor ->
          Lwt.return (State.Block.equal predecessor previous)
    end >>= fun successor ->
    if successor then begin
      Distributed_db.Advertise.current_head
        nv.parameters.net_db block ;
      Lwt.return_unit
    end else begin
      let net_state = Distributed_db.net_state nv.parameters.net_db in
      Chain.locator net_state >>= fun locator ->
      Distributed_db.Advertise.current_branch
        nv.parameters.net_db locator
    end
  end

let on_request (type a) w spawn_child (req : a Request.t) : a tzresult Lwt.t =
  let Request.Validated block = req in
  let nv = Worker.state w in
  Chain.head nv.parameters.net_state >>= fun head ->
  let head_header = State.Block.header head
  and head_hash = State.Block.hash head
  and block_header = State.Block.header block
  and block_hash = State.Block.hash block in
  if
    Fitness.(block_header.shell.fitness <= head_header.shell.fitness)
  then
    return Event.Ignored_head
  else begin
    Chain.set_head nv.parameters.net_state block >>= fun previous ->
    broadcast_head w ~previous block >>= fun () ->
    Prevalidator.flush nv.prevalidator block_hash >>=? fun () ->
    may_switch_test_network w spawn_child block >>= fun () ->
    Lwt_watcher.notify nv.new_head_input block ;
    if Block_hash.equal head_hash block_header.shell.predecessor then
      return Event.Head_incrememt
    else
      return Event.Branch_switch
  end

let on_completion (type a) w  (req : a Request.t) (update : a) request_status =
  let Request.Validated block = req in
  let fitness = State.Block.fitness block in
  let request = State.Block.hash block in
  Worker.record_event w (Processed_block { request ; request_status ; update ; fitness }) ;
  Lwt.return ()

let on_close w =
  let nv = Worker.state w in
  Distributed_db.deactivate nv.parameters.net_db >>= fun () ->
  Lwt.join
    (Prevalidator.shutdown nv.prevalidator ::
     Lwt_utils.may ~f:(fun (_, shutdown) -> shutdown ()) nv.child ::
     P2p.Peer_id.Table.fold
       (fun _ pv acc -> (pv >>= Peer_validator.shutdown) :: acc)
       nv.active_peers []) >>= fun () ->
  Lwt.return_unit

let on_launch w _ parameters =
  Chain.init_head parameters.net_state >>= fun () ->
  Prevalidator.create
    parameters.prevalidator_limits parameters.net_db >>= fun prevalidator ->
  let valid_block_input = Lwt_watcher.create_input () in
  let new_head_input = Lwt_watcher.create_input () in
  let bootstrapped_waiter, bootstrapped_wakener = Lwt.wait () in
  let nv =
    { parameters ;
      valid_block_input ;
      new_head_input ;
      bootstrapped_wakener ;
      bootstrapped_waiter ;
      bootstrapped = (parameters.limits.bootstrap_threshold <= 0) ;
      active_peers =
        P2p.Peer_id.Table.create 50 ; (* TODO use `2 * max_connection` *)
      bootstrapped_peers =
        P2p.Peer_id.Table.create 50 ; (* TODO use `2 * max_connection` *)
      child = None ;
      prevalidator } in
  if nv.bootstrapped then Lwt.wakeup_later bootstrapped_wakener () ;
  Distributed_db.set_callback parameters.net_db {
    notify_branch = begin fun peer_id locator ->
      Lwt.async begin fun () ->
        may_activate_peer_validator w peer_id >>= fun pv ->
        Peer_validator.notify_branch pv locator ;
        Lwt.return_unit
      end
    end ;
    notify_head = begin fun peer_id block ops ->
      Lwt.async begin fun () ->
        may_activate_peer_validator w peer_id >>= fun pv ->
        Peer_validator.notify_head pv block ;
        (* TODO notify prevalidator only if head is known ??? *)
        Prevalidator.notify_operations nv.prevalidator peer_id ops ;
        Lwt.return_unit
      end;
    end ;
    disconnection = begin fun peer_id ->
      Lwt.async begin fun () ->
        may_activate_peer_validator w peer_id >>= fun pv ->
        Peer_validator.shutdown pv >>= fun () ->
        Lwt.return_unit
      end
    end ;
  } ;
  Lwt.return nv

let rec create
    ?max_child_ttl ?parent
    peer_validator_limits prevalidator_limits block_validator
    global_valid_block_input db net_state limits =
  let spawn_child ~parent pvl pl bl gvbi db n l =
    create ~parent pvl pl bl gvbi db n l >>= fun w ->
    Lwt.return (Worker.state w, (fun () -> Worker.shutdown w)) in
  let module Handlers = struct
    type self = t
    let on_launch = on_launch
    let on_request w = on_request w spawn_child
    let on_close = on_close
    let on_error _ _ _ errs = Lwt.return (Error errs)
    let on_completion = on_completion
    let on_no_request _ = return ()
  end in
  let parameters =
    { max_child_ttl ;
      parent ;
      peer_validator_limits ;
      prevalidator_limits ;
      block_validator ;
      global_valid_block_input ;
      db ;
      net_db = Distributed_db.activate db net_state ;
      net_state ;
      limits } in
  Worker.launch table
    prevalidator_limits.worker_limits
    (State.Net.id net_state)
    parameters
    (module Handlers)

(** Current block computation *)

let create
    ?max_child_ttl
    peer_validator_limits prevalidator_limits
    block_validator global_valid_block_input global_db state limits =
  (* hide the optional ?parent *)
  create
    ?max_child_ttl
    peer_validator_limits prevalidator_limits
    block_validator global_valid_block_input global_db state limits

let net_id w =
  let { parameters = { net_state } } = Worker.state w in
  State.Net.id net_state

let net_state w =
  let { parameters = { net_state } } = Worker.state w in
  net_state

let prevalidator w =
  let { prevalidator } = Worker.state w in
  prevalidator

let net_db w =
  let { parameters = { net_db } } = Worker.state w in
  net_db

let child w =
  match (Worker.state w).child with
  | None -> None
  | Some ({ parameters = { net_state } }, _) ->
      try Some (List.assoc (State.Net.id net_state) (Worker.list table))
      with Not_found -> None

let validate_block w ?(force = false) hash block operations =
  let nv = Worker.state w in
  assert (Block_hash.equal hash (Block_header.hash block)) ;
  Chain.head nv.parameters.net_state >>= fun head ->
  let head = State.Block.header head in
  if
    force || Fitness.(head.shell.fitness <= block.shell.fitness)
  then
    Block_validator.validate
      ~canceler:(Worker.canceler w)
      ~notify_new_block:(notify_new_block w)
      nv.parameters.block_validator
      nv.parameters.net_db
      hash block operations
  else
    failwith "Fitness too low"

let bootstrapped w =
  let { bootstrapped_waiter } = Worker.state w in
  Lwt.protected bootstrapped_waiter

let valid_block_watcher w =
  let{ valid_block_input } = Worker.state w in
  Lwt_watcher.create_stream valid_block_input

let new_head_watcher w =
  let { new_head_input } = Worker.state w in
  Lwt_watcher.create_stream new_head_input

let status = Worker.status

let running_workers () = Worker.list table

let pending_requests t = Worker.pending_requests t

let current_request t = Worker.current_request t

let last_events = Worker.last_events
