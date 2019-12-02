(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(* Copyright (c) 2019 Nomadic Labs, <contact@nomadic-labs.com>               *)
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

(** Typed and encrypted connections to peers.

    This module defines:
    - primitive functions to implement a session-establishment protocol
      (set up an authentication/encryption symmetric session key,
       check proof of work target, authenticate hosts, exchange meta data),
    - a higher-level, authenticated and encrypted, type of connection.

    It is parametric in two (abstract data) types. ['msg] is the unit of
    communication. ['meta] is a type of message sent in session establishment.

    Connections defined in this module wrap a [P2p_io_scheduler.connection]
    (which is simply a file descriptor on which R/W are regulated.)

    Each connection has an associated internal read (resp. write) queue
    containing messages (of type ['msg]), whose size can be limited by
    providing corresponding arguments to [accept]. *)

(** {1 Types} *)

(** This defines an abstract data type ['meta]. Mainly a placeholder to be
    used by the calling layer. ['meta] objects are communicated at session
    initiation and both ends ['meta'] are known once session is set up. ['meta]
    object should at least contain the private status of the node. *)

(* TODO:
   - this type is duplicated at several places. Define it once for all in a
     separate module (with [msg_config] and [peer_config]).
   - the parameter [P2p_peer.Id.t] provides more control when constructing a
     ['meta] but may not be useful. *)
type 'meta metadata_config = {
  conn_meta_encoding : 'meta Data_encoding.t;
  conn_meta_value : P2p_peer.Id.t -> 'meta;
  private_node : 'meta -> bool;
}

(** Type of a connection that successfully passed the authentication
    phase, but has not been accepted yet. Parametrized by the type
    of expected parameter in the `ack` message. *)
type 'meta authenticated_connection

(** Type of an accepted connection, parametrized by the type of
    messages exchanged between peers. *)
type ('msg, 'meta) t

(** [equal t1 t2] returns true iff the identities of the underlying
    [P2p_io_scheduler.connection]s are equal. *)
val equal : ('mst, 'meta) t -> ('msg, 'meta) t -> bool

val pp : Format.formatter -> ('msg, 'meta) t -> unit

val info : ('msg, 'meta) t -> 'meta P2p_connection.Info.t

(** [local_metadata t] returns the metadata provided when calling
    [authenticate]. *)
val local_metadata : ('msg, 'meta) t -> 'meta

(** [local_metadata t] returns the remote metadata, communicated by the
    remote host when the session was established. *)
val remote_metadata : ('msg, 'meta) t -> 'meta

val private_node : ('msg, 'meta) t -> bool

(** {1 Session-establishment functions}

    These should be used together
    to implement the session establishment protocol. Session establishment
    proceeds in three synchronous, symmetric, steps. First two steps are
    implemented by [authenticate]. Third step is implemented by either [accept]
    or [kick].

    1. Hosts send each other an authentication message. The message contains
       notably a public key, a nonce, and proof of work stamp computed from
       the public key. PoW work is checked, and a session key is established
       (authenticated key exchange). The session key will be used to
       encrypt/authenticate all subsequent messages over this connection.

    2. Hosts send each other a ['meta] message.

    3. Each host send either an [Ack] message ([accept] function) or an [Nack]
       message ([kick] function). If both hosts send an [Ack], the connection
       is established and they can start to read/write ['msg].

    Note that [P2p_errors.Decipher_error] can be raised from all functions
    receiving messages after step 1, when a message can't be decrypted.

    Typically, the calling module will make additional checks after step 2 to
    decide what to do in step 3. For instance, based on network version or
    ['meta] information. *)

(** [authenticate canceler pow incoming conn point ?port identity version meta]
    returns a couple [(info, auth_conn)] tries to set up a session with
    the host connected via [conn].

    Can fail with
    - [P2p_errors.Not_enough_proof_of_work] if PoW target isn't reached
    - [P2p_errors.Myself] if both hosts are the same peer *)
val authenticate :
  canceler:Lwt_canceler.t ->
  proof_of_work_target:Crypto_box.target ->
  incoming:bool ->
  P2p_io_scheduler.connection ->
  P2p_point.Id.t ->
  ?listening_port:int ->
  P2p_identity.t ->
  Network_version.t ->
  'meta metadata_config ->
  ('meta P2p_connection.Info.t * 'meta authenticated_connection) tzresult Lwt.t

(** [kick ac] sends a [Nack] message to the remote peer, notifying it
    that its connection is rejected. It then closes the connection. *)
val kick : 'meta authenticated_connection -> unit Lwt.t

(** [Accepts] sends an [Ack message] to the remote peer and wait for an [Ack]
    from the remote peer to complete session set up. This can fail with errors:
    - [P2p_errors.Rejected_socket_connection] (connection closed or [Nack]
      received)
    - [P2p_errors.Invalid_auth] thrown if [P2p_error.Decipher_error]
      TODO why not let propagate [P2p_error.Decipher_error] *)
val accept :
  ?incoming_message_queue_size:int ->
  ?outgoing_message_queue_size:int ->
  ?binary_chunks_size:int ->
  canceler:Lwt_canceler.t ->
  'meta authenticated_connection ->
  'msg Data_encoding.t ->
  ('msg, 'meta) t tzresult Lwt.t

(** Check for the [?binary_chunks_size] parameter of [accept]. *)
val check_binary_chunks_size : int -> unit tzresult Lwt.t

(** {1 IO functions on connections} *)

(** {2 Output functions} *)

(** [write conn msg] returns when [msg] has successfully been added to
    [conn]'s internal write queue or fails with a corresponding
    error. *)
val write : ('msg, 'meta) t -> 'msg -> unit tzresult Lwt.t

(** [write_now conn msg] is [Ok true] if [msg] has been added to
    [conn]'s internal write queue, [Ok false] if [msg] has been
    dropped, or fails with a corresponding error otherwise. *)
val write_now : ('msg, 'meta) t -> 'msg -> bool tzresult

(** [write_sync conn msg] returns when [msg] has been successfully
    sent to the remote end of [conn], or fails accordingly. *)
val write_sync : ('msg, 'meta) t -> 'msg -> unit tzresult Lwt.t

(** {2 Input functions} *)

(** [is_readable conn] is [true] iff [conn] internal read queue is not
    empty. *)
val is_readable : ('msg, 'meta) t -> bool

(** (Cancelable) [wait_readable conn] returns when [conn]'s internal
    read queue becomes readable (i.e. not empty). *)
val wait_readable : ('msg, 'meta) t -> unit tzresult Lwt.t

(** [read conn msg] returns when [msg] has successfully been popped
    from [conn]'s internal read queue or fails with a corresponding
    error. *)
val read : ('msg, 'meta) t -> (int * 'msg) tzresult Lwt.t

(** [read_now conn msg] is [Some msg] if [conn]'s internal read queue
    is not empty, [None] if it is empty, or fails with a corresponding
    error otherwise. *)
val read_now : ('msg, 'meta) t -> (int * 'msg) tzresult option

(** [stat conn] is a snapshot of current bandwidth usage for
    [conn]. *)
val stat : ('msg, 'meta) t -> P2p_stat.t

val close : ?wait:bool -> ('msg, 'meta) t -> unit Lwt.t

(**/**)

(** for testing only *)
val raw_write_sync : ('msg, 'meta) t -> Bytes.t -> unit tzresult Lwt.t
