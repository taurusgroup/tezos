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

(** Generic interface for a datatype with comparison, pretty-printer
    and serialization functions. *)
module type T = sig
  type t

  include Compare.S with type t := t

  val pp : Format.formatter -> t -> unit

  val encoding : t Data_encoding.t

  val to_bytes : t -> bytes

  val of_bytes : bytes -> t option
end

(** Generic interface for a datatype with comparison, pretty-printer,
    serialization functions and a hashing function. *)
module type HASHABLE = sig
  include T

  type hash

  val hash : t -> hash

  val hash_raw : bytes -> hash
end

(** {2 Hash Types} *)

(** The signature of an abstract hash type, as produced by functor
    {!Make_SHA256}. The {!t} type is abstracted for separating the
    various kinds of hashes in the system at typing time. Each type is
    equipped with functions to use it as is of as keys in the database
    or in memory sets and maps. *)

module type MINIMAL_HASH = sig
  type t

  val name : string

  val title : string

  val pp : Format.formatter -> t -> unit

  val pp_short : Format.formatter -> t -> unit

  include Compare.S with type t := t

  val hash_bytes : ?key:bytes -> bytes list -> t

  val hash_string : ?key:string -> string list -> t

  val zero : t
end

module type RAW_DATA = sig
  type t

  val size : int (* in bytes *)

  val to_bytes : t -> bytes

  val of_bytes_opt : bytes -> t option

  val of_bytes_exn : bytes -> t
end

module type B58_DATA = sig
  type t

  val to_b58check : t -> string

  val to_short_b58check : t -> string

  val of_b58check_exn : string -> t

  val of_b58check_opt : string -> t option

  type Base58.data += Data of t

  val b58check_encoding : t Base58.encoding
end

module type ENCODER = sig
  type t

  val encoding : t Data_encoding.t

  val rpc_arg : t RPC_arg.t
end

module type INDEXES_SET = sig
  include Set.S

  val random_elt : t -> elt

  val encoding : t Data_encoding.t
end

module type INDEXES_MAP = sig
  include Map.S

  val encoding : 'a Data_encoding.t -> 'a t Data_encoding.t
end

module type INDEXES = sig
  type t

  val to_path : t -> string list -> string list

  val of_path : string list -> t option

  val of_path_exn : string list -> t

  val prefix_path : string -> string list

  val path_length : int

  module Set : INDEXES_SET with type elt = t

  module Map : INDEXES_MAP with type key = t
end

module type HASH = sig
  include MINIMAL_HASH

  include RAW_DATA with type t := t

  include B58_DATA with type t := t

  include ENCODER with type t := t

  include INDEXES with type t := t
end

module type MERKLE_TREE = sig
  type elt

  include HASH

  val compute : elt list -> t

  val empty : t

  type path = Left of path * t | Right of t * path | Op

  val compute_path : elt list -> int -> path

  val check_path : path -> elt -> t * int

  val path_encoding : path Data_encoding.t
end

module type SIGNATURE_PUBLIC_KEY_HASH = sig
  type t

  val pp : Format.formatter -> t -> unit

  val pp_short : Format.formatter -> t -> unit

  include Compare.S with type t := t

  include RAW_DATA with type t := t

  include B58_DATA with type t := t

  include ENCODER with type t := t

  include INDEXES with type t := t

  val zero : t
end

module type SIGNATURE_PUBLIC_KEY = sig
  type t

  val pp : Format.formatter -> t -> unit

  include Compare.S with type t := t

  include B58_DATA with type t := t

  include ENCODER with type t := t

  type public_key_hash_t

  val hash : t -> public_key_hash_t

  val size : t -> int (* in bytes *)

  val of_bytes_without_validation : bytes -> t option
end

module type SIGNATURE = sig
  module Public_key_hash : SIGNATURE_PUBLIC_KEY_HASH

  module Public_key :
    SIGNATURE_PUBLIC_KEY with type public_key_hash_t := Public_key_hash.t

  type t

  val pp : Format.formatter -> t -> unit

  include RAW_DATA with type t := t

  include Compare.S with type t := t

  include B58_DATA with type t := t

  include ENCODER with type t := t

  val zero : t

  type watermark

  (** Check a signature *)
  val check : ?watermark:watermark -> Public_key.t -> t -> bytes -> bool
end

module type FIELD = sig
  type t

  (** The order of the finite field *)
  val order : Z.t

  (** minimal number of bytes required to encode a value of the field. *)
  val size_in_bytes : int

  (** [check_bytes bs] returns [true] if [bs] is a correct byte
      representation of a field element *)
  val check_bytes : Bytes.t -> bool

  (** The neutral element for the addition *)
  val zero : t

  (** The neutral element for the multiplication *)
  val one : t

  (** [add a b] returns [a + b mod order] *)
  val add : t -> t -> t

  (** [mul a b] returns [a * b mod order] *)
  val mul : t -> t -> t

  (** [eq a b] returns [true] if [a = b mod order], else [false] *)
  val eq : t -> t -> bool

  (** [negate x] returns [-x mod order]. Equivalently, [negate x] returns the
      unique [y] such that [x + y mod order = 0]
  *)
  val negate : t -> t

  (** [inverse_opt x] returns [x^-1] if [x] is not [0] as an option, else [None] *)
  val inverse_opt : t -> t option

  (** [pow x n] returns [x^n] *)
  val pow : t -> Z.t -> t

  (** From a predefined bytes representation, construct a value t. It is not
      required that to_bytes [(Option.get (of_bytes_opt t)) = t]. By default,
      little endian encoding is used and the given element is modulo the prime
      order *)
  val of_bytes_opt : Bytes.t -> t option

  (** Convert the value t to a bytes representation which can be used for
      hashing for instance. It is not required that [to_bytes (Option.get
      (of_bytes_opt t)) = t]. By default, little endian encoding is used, and
      length of the resulting bytes may vary depending on the order.
  *)
  val to_bytes : t -> Bytes.t
end

(** Module type for the prime fields GF(p) *)
module type PRIME_FIELD = sig
  include FIELD

  (** [of_z x] builds an element t from the Zarith element [x]. [mod order] is
      applied if [x >= order] or [x < 0]. *)
  val of_z : Z.t -> t

  (** [to_z x] builds a Zarith element, using the decimal representation.
      Arithmetic on the result can be done using the modular functions on
      integers *)
  val to_z : t -> Z.t
end

module type CURVE = sig
  (** The type of the element in the elliptic curve *)
  type t

  (** The size of a point representation, in bytes *)
  val size_in_bytes : int

  module Scalar : FIELD

  (** Check if a point, represented as a byte array, is on the curve **)
  val check_bytes : Bytes.t -> bool

  (** Attempt to construct a point from a byte array *)
  val of_bytes_opt : Bytes.t -> t option

  (** Return a representation in bytes *)
  val to_bytes : t -> Bytes.t

  (** Zero of the elliptic curve *)
  val zero : t

  (** A fixed generator of the elliptic curve *)
  val one : t

  (** Return the addition of two element *)
  val add : t -> t -> t

  (** Double the element *)
  val double : t -> t

  (** Return the opposite of the element *)
  val negate : t -> t

  (** Return [true] if the two elements are algebraically the same *)
  val eq : t -> t -> bool

  (** Multiply an element by a scalar *)
  val mul : t -> Scalar.t -> t
end

module type PAIRING = sig
  module Gt : FIELD

  module G1 : CURVE

  module G2 : CURVE

  val miller_loop : (G1.t * G2.t) list -> Gt.t

  val final_exponentiation_opt : Gt.t -> Gt.t option

  val pairing : G1.t -> G2.t -> Gt.t
end

module type PVSS_ELEMENT = sig
   type t

   include B58_DATA with type t := t

   include ENCODER with type t := t
end

module type PVSS_PUBLIC_KEY = sig
   type t

   val pp : Format.formatter -> t -> unit

   include Compare.S with type t := t

   include RAW_DATA with type t := t

   include B58_DATA with type t := t

   include ENCODER with type t := t
end

module type PVSS_SECRET_KEY = sig
   type public_key

   type t

    include ENCODER with type t := t

    val to_public_key : t -> public_key
end

module type PVSS = sig
  type proof

  module Clear_share : PVSS_ELEMENT

  module Commitment : PVSS_ELEMENT

  module Encrypted_share : PVSS_ELEMENT

  module Public_key : PVSS_PUBLIC_KEY

  module Secret_key : PVSS_SECRET_KEY with type public_key := Public_key.t

  val proof_encoding : proof Data_encoding.t

  val check_dealer_proof :
    Encrypted_share.t list ->
    Commitment.t list ->
    proof:proof ->
    public_keys:Public_key.t list ->
    bool

  val check_revealed_share :
    Encrypted_share.t ->
    Clear_share.t ->
    public_key:Public_key.t ->
    proof ->
    bool

  val reconstruct : Clear_share.t list -> int list -> Public_key.t
end
