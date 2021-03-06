(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
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

type t =
  | Unaccounted
  | Limited of { remaining : Z.t }

type internal_gas = Z.t

type cost =
  { allocations : Z.t ;
    steps : Z.t ;
    reads : Z.t ;
    writes : Z.t  ;
    bytes_read : Z.t ;
    bytes_written : Z.t }

let encoding =
  let open Data_encoding in
  union
    [ case (Tag 0)
        ~title:"Limited"
        z
        (function Limited { remaining } -> Some remaining | _ -> None)
        (fun remaining -> Limited { remaining }) ;
      case (Tag 1)
        ~title:"Unaccounted"
        (constant "unaccounted")
        (function Unaccounted -> Some () | _ -> None)
        (fun () -> Unaccounted) ]

let pp ppf = function
  | Unaccounted ->
      Format.fprintf ppf "unaccounted"
  | Limited { remaining } ->
      Format.fprintf ppf "%s units remaining" (Z.to_string remaining)

let cost_encoding =
  let open Data_encoding in
  conv
    (fun { allocations ; steps ; reads ; writes ; bytes_read ; bytes_written } ->
       (allocations, steps, reads, writes, bytes_read, bytes_written))
    (fun (allocations, steps, reads, writes, bytes_read, bytes_written) ->
       { allocations ; steps ; reads ; writes ; bytes_read ; bytes_written })
    (obj6
       (req "allocations" z)
       (req "steps" z)
       (req "reads" z)
       (req "writes" z)
       (req "bytes_read" z)
       (req "bytes_written" z))

let pp_cost ppf { allocations ; steps ; reads ; writes ; bytes_read ; bytes_written } =
  Format.fprintf ppf
    "(steps: %s, allocs: %s, reads: %s (%s bytes), writes: %s (%s bytes))"
    (Z.to_string steps)
    (Z.to_string allocations)
    (Z.to_string reads)
    (Z.to_string bytes_read)
    (Z.to_string writes)
    (Z.to_string bytes_written)

type error += Block_quota_exceeded (* `Temporary *)
type error += Operation_quota_exceeded (* `Temporary *)

let allocation_weight = Z.of_int 2
let step_weight = Z.of_int 1
let read_base_weight = Z.of_int 100
let write_base_weight = Z.of_int 160
let byte_read_weight = Z.of_int 10
let byte_written_weight = Z.of_int 15

let rescaling_bits = 7
let rescaling_mask =
  Z.sub (Z.shift_left Z.one rescaling_bits) Z.one

let scale (z : Z.t) = Z.shift_left z rescaling_bits
let rescale (z : Z.t) = Z.shift_right z rescaling_bits

let cost_to_internal_gas (cost : cost) : internal_gas =
  Z.add
    (Z.add
       (Z.mul cost.allocations allocation_weight)
       (Z.mul cost.steps step_weight))
    (Z.add
       (Z.add
          (Z.mul cost.reads read_base_weight)
          (Z.mul cost.writes write_base_weight))
       (Z.add
          (Z.mul cost.bytes_read byte_read_weight)
          (Z.mul cost.bytes_written byte_written_weight)))

let internal_gas_to_gas internal_gas : Z.t * internal_gas =
  let gas  = rescale internal_gas in
  let rest = Z.logand internal_gas rescaling_mask in
  (gas, rest)

let consume block_gas operation_gas internal_gas cost =
  match operation_gas with
  | Unaccounted -> ok (block_gas, Unaccounted, internal_gas)
  | Limited { remaining } ->
      let cost_internal_gas  = cost_to_internal_gas cost in
      let total_internal_gas =
        Z.add cost_internal_gas internal_gas in
      let gas, rest = internal_gas_to_gas total_internal_gas in
      if Compare.Z.(gas > Z.zero) then
        let remaining =
          Z.sub remaining gas in
        let block_remaining =
          Z.sub block_gas gas in
        if Compare.Z.(remaining < Z.zero)
        then error Operation_quota_exceeded
        else if Compare.Z.(block_remaining < Z.zero)
        then error Block_quota_exceeded
        else ok (block_remaining, Limited { remaining }, rest)
      else
        ok (block_gas, operation_gas, total_internal_gas)

let check_enough block_gas operation_gas internal_gas cost =
  consume block_gas operation_gas internal_gas cost
  >|? fun (_block_remainig, _remaining, _internal_gas) -> ()

let internal_gas_zero : internal_gas = Z.zero

let alloc_cost n =
  { allocations = scale (Z.of_int (n + 1)) ;
    steps = Z.zero ;
    reads = Z.zero ;
    writes = Z.zero ;
    bytes_read = Z.zero ;
    bytes_written = Z.zero }

let alloc_bytes_cost n =
  alloc_cost ((n + 7) / 8)

let alloc_bits_cost n =
  alloc_cost ((n + 63) / 64)

let atomic_step_cost n =
  { allocations = Z.zero ;
    steps = Z.of_int (2 * n) ;
    reads = Z.zero ;
    writes = Z.zero ;
    bytes_read = Z.zero ;
    bytes_written = Z.zero }

let step_cost n =
  { allocations = Z.zero ;
    steps = scale (Z.of_int n) ;
    reads = Z.zero ;
    writes = Z.zero ;
    bytes_read = Z.zero ;
    bytes_written = Z.zero }

let free =
  { allocations = Z.zero ;
    steps = Z.zero ;
    reads = Z.zero ;
    writes = Z.zero ;
    bytes_read = Z.zero ;
    bytes_written = Z.zero }

let read_bytes_cost n =
  { allocations = Z.zero ;
    steps = Z.zero ;
    reads = scale Z.one ;
    writes = Z.zero ;
    bytes_read = scale n ;
    bytes_written = Z.zero }

let write_bytes_cost n =
  { allocations = Z.zero ;
    steps = Z.zero ;
    reads = Z.zero ;
    writes = Z.one ;
    bytes_read = Z.zero ;
    bytes_written = scale n }

let ( +@ ) x y =
  { allocations = Z.add x.allocations y.allocations ;
    steps = Z.add x.steps y.steps ;
    reads = Z.add x.reads y.reads ;
    writes = Z.add x.writes y.writes ;
    bytes_read = Z.add x.bytes_read y.bytes_read ;
    bytes_written = Z.add x.bytes_written y.bytes_written }

let ( *@ ) x y =
  { allocations = Z.mul (Z.of_int x) y.allocations ;
    steps = Z.mul (Z.of_int x) y.steps ;
    reads = Z.mul (Z.of_int x) y.reads ;
    writes = Z.mul (Z.of_int x) y.writes ;
    bytes_read = Z.mul (Z.of_int x) y.bytes_read ;
    bytes_written = Z.mul (Z.of_int x) y.bytes_written }

let alloc_mbytes_cost n =
  alloc_cost 12 +@ alloc_bytes_cost n

let () =
  let open Data_encoding in
  register_error_kind
    `Temporary
    ~id:"gas_exhausted.operation"
    ~title: "Gas quota exceeded for the operation"
    ~description:
      "A script or one of its callee took more \
       time than the operation said it would"
    empty
    (function Operation_quota_exceeded -> Some () | _ -> None)
    (fun () -> Operation_quota_exceeded) ;
  register_error_kind
    `Temporary
    ~id:"gas_exhausted.block"
    ~title: "Gas quota exceeded for the block"
    ~description:
      "The sum of gas consumed by all the operations in the block \
       exceeds the hard gas limit per block"
    empty
    (function Block_quota_exceeded -> Some () | _ -> None)
    (fun () -> Block_quota_exceeded) ;
