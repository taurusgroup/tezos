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

open Level_repr

let from_raw c ?offset l =
  let cycle_eras = Raw_context.cycle_eras c in
  Level_repr.level_from_raw ~cycle_eras ?offset l

let root c = Raw_context.cycle_eras c |> Level_repr.root_level

let succ c (l : Level_repr.t) = from_raw c (Raw_level_repr.succ l.level)

let pred c (l : Level_repr.t) =
  match Raw_level_repr.pred l.Level_repr.level with
  | None -> None
  | Some l -> Some (from_raw c l)

let current ctxt = Raw_context.current_level ctxt

let previous ctxt =
  let l = current ctxt in
  match pred ctxt l with
  | None -> assert false (* We never validate the Genesis... *)
  | Some p -> p

let first_level_in_cycle ctxt cycle =
  let cycle_eras = Raw_context.cycle_eras ctxt in
  Level_repr.first_level_in_cycle_from_eras ~cycle_eras cycle

let last_level_in_cycle ctxt c =
  match pred ctxt (first_level_in_cycle ctxt (Cycle_repr.succ c)) with
  | None -> assert false
  | Some x -> x

let levels_in_cycle ctxt cycle =
  let first = first_level_in_cycle ctxt cycle in
  let[@coq_struct "n"] rec loop (n : Level_repr.t) acc =
    if Cycle_repr.(n.cycle = first.cycle) then loop (succ ctxt n) (n :: acc)
    else acc
  in
  loop first []

let levels_in_current_cycle ctxt ?(offset = 0l) () =
  let current_cycle = Cycle_repr.to_int32 (current ctxt).cycle in
  let cycle = Int32.add current_cycle offset in
  if Compare.Int32.(cycle < 0l) then []
  else
    let cycle = Cycle_repr.of_int32_exn cycle in
    levels_in_cycle ctxt cycle

let levels_with_commitments_in_cycle ctxt c =
  let first = first_level_in_cycle ctxt c in
  let[@coq_struct "n"] rec loop (n : Level_repr.t) acc =
    if Cycle_repr.(n.cycle = first.cycle) then
      if n.expected_commitment then loop (succ ctxt n) (n :: acc)
      else loop (succ ctxt n) acc
    else acc
  in
  loop first []

let last_allowed_fork_level c =
  let level = Raw_context.current_level c in
  let preserved_cycles = Constants_storage.preserved_cycles c in
  match Cycle_repr.sub level.cycle preserved_cycles with
  | None -> Raw_level_repr.root
  | Some cycle -> (first_level_in_cycle c cycle).level

let last_of_a_cycle ctxt level =
  let cycle_eras = Raw_context.cycle_eras ctxt in
  Level_repr.last_of_cycle ~cycle_eras level

let dawn_of_a_new_cycle ctxt =
  let level = current ctxt in
  if last_of_a_cycle ctxt level then Some level.cycle else None

let may_snapshot_rolls ctxt =
  let level = current ctxt in
  let blocks_per_roll_snapshot =
    Constants_storage.blocks_per_roll_snapshot ctxt
  in
  Compare.Int32.equal
    (Int32.rem level.cycle_position blocks_per_roll_snapshot)
    (Int32.pred blocks_per_roll_snapshot)
