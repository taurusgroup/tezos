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

type t = {
  level : Raw_level_repr.t;
  level_position : int32;
  cycle : Cycle_repr.t;
  cycle_position : int32;
  expected_commitment : bool;
}

include Compare.Make (struct
  type nonrec t = t

  let compare {level = l1; _} {level = l2; _} = Raw_level_repr.compare l1 l2
end)

type level = t

let pp ppf {level; _} = Raw_level_repr.pp ppf level

let pp_full ppf l =
  Format.fprintf
    ppf
    "%a.%ld (cycle %a.%ld)"
    Raw_level_repr.pp
    l.level
    l.level_position
    Cycle_repr.pp
    l.cycle
    l.cycle_position

let encoding =
  let open Data_encoding in
  conv
    (fun {level; level_position; cycle; cycle_position; expected_commitment} ->
      (level, level_position, cycle, cycle_position, expected_commitment))
    (fun (level, level_position, cycle, cycle_position, expected_commitment) ->
      {level; level_position; cycle; cycle_position; expected_commitment})
    (obj5
       (req
          "level"
          ~description:
            "The level of the block relative to genesis. This is also the \
             Shell's notion of level"
          Raw_level_repr.encoding)
       (req
          "level_position"
          ~description:
            "The level of the block relative to the block that starts protocol \
             alpha. This is specific to the protocol alpha. Other protocols \
             might or might not include a similar notion."
          int32)
       (req
          "cycle"
          ~description:
            "The current cycle's number. Note that cycles are a \
             protocol-specific notion. As a result, the cycle number starts at \
             0 with the first block of protocol alpha."
          Cycle_repr.encoding)
       (req
          "cycle_position"
          ~description:
            "The current level of the block relative to the first block of the \
             current cycle."
          int32)
       (req
          "expected_commitment"
          ~description:
            "Tells whether the baker of this block has to commit a seed nonce \
             hash."
          bool))

let diff {level = l1; _} {level = l2; _} =
  Int32.sub (Raw_level_repr.to_int32 l1) (Raw_level_repr.to_int32 l2)

type cycle_era = {
  first_level : Raw_level_repr.t;
  first_cycle : Cycle_repr.t;
  blocks_per_cycle : int32;
  blocks_per_commitment : int32;
}

type cycle_eras = cycle_era list

type error += Invalid_cycle_eras

let () =
  register_error_kind
    `Temporary
    ~id:"level_repr.invalid_cycle_eras"
    ~title:"Invalid cycle eras"
    ~description:
      "The cycles eras are not valid: empty list or non-decreasing first \
       levels or first cycles."
    ~pp:(fun ppf () ->
      Format.fprintf
        ppf
        "The cycles eras are not valid: empty list or non-decreasing first \
         levels or first cycles.")
    Data_encoding.empty
    (function Invalid_cycle_eras -> Some () | _ -> None)
    (fun () -> Invalid_cycle_eras)

let create_cycle_eras cycle_eras =
  match cycle_eras with
  | [] -> error Invalid_cycle_eras
  | newest_era :: older_eras ->
      let rec aux {first_level; first_cycle; _} older_eras =
        match older_eras with
        | ({
             first_level = first_level_of_previous_era;
             first_cycle = first_cycle_of_previous_era;
             _;
           } as previous_era)
          :: even_older_eras ->
            if
              Raw_level_repr.(first_level > first_level_of_previous_era)
              && Cycle_repr.(first_cycle > first_cycle_of_previous_era)
            then aux previous_era even_older_eras
            else error Invalid_cycle_eras
        | [] -> ok ()
      in
      aux newest_era older_eras >>? fun () -> ok cycle_eras

let cycle_era_encoding =
  let open Data_encoding in
  conv
    (fun {first_level; first_cycle; blocks_per_cycle; blocks_per_commitment} ->
      (first_level, first_cycle, blocks_per_cycle, blocks_per_commitment))
    (fun (first_level, first_cycle, blocks_per_cycle, blocks_per_commitment) ->
      {first_level; first_cycle; blocks_per_cycle; blocks_per_commitment})
    (obj4
       (req
          "first_level"
          ~description:"The first level of a new cycle era."
          Raw_level_repr.encoding)
       (req
          "first_cycle"
          ~description:"The first cycle of a new cycle era."
          Cycle_repr.encoding)
       (req
          "blocks_per_cycle"
          ~description:
            "The value of the blocks_per_cycle constant used during the cycle \
             era starting with first_level."
          int32)
       (req
          "blocks_per_commitment"
          ~description:
            "The value of the blocks_per_commitment constant used during the \
             cycle era starting with first_level."
          int32))

let cycle_eras_encoding =
  Data_encoding.conv_with_guard
    (fun eras -> eras)
    (fun eras ->
      match create_cycle_eras eras with
      | Ok eras -> Ok eras
      | Error _ -> Error "Invalid cycle eras")
    (Data_encoding.list cycle_era_encoding)

let current_era = function [] -> assert false | cycle_era :: _ -> cycle_era

let root_level cycle_eras =
  let first_era = List.last_opt cycle_eras in
  let first_era =
    match first_era with
    | Some first_era -> first_era
    | None ->
        (* {!create_cycle_eras} fails if the list is empty.
           {!cycle_eras_encoding} uses {!create_cycle_eras} and so fails on empty
           lists too. *)
        assert false
  in
  {
    level = first_era.first_level;
    level_position = 0l;
    cycle = Cycle_repr.root;
    cycle_position = 0l;
    expected_commitment = false;
  }

(* This function returns the cycle era to which [level] belongs. *)
let era_of_level ~cycle_eras level =
  let rec aux = function
    | ({first_level; _} as era) :: previous_eras ->
        if Raw_level_repr.(level >= first_level) then era else aux previous_eras
    | [] -> assert false
  in
  aux cycle_eras

(* This function returns the cycle era to which [cycle] belongs. *)
let era_of_cycle ~cycle_eras cycle =
  let rec aux = function
    | ({first_cycle; _} as era) :: previous_eras ->
        if Cycle_repr.(cycle >= first_cycle) then era else aux previous_eras
    | [] -> assert false
  in
  aux cycle_eras

(* precondition: level belong to era *)
let level_from_raw_with_era era ~first_level_in_alpha_family level =
  let {first_level; first_cycle; blocks_per_cycle; blocks_per_commitment} =
    era
  in
  let level_position_in_era = Raw_level_repr.diff level first_level in
  assert (Compare.Int32.(level_position_in_era >= 0l)) ;
  let cycles_since_era_start =
    Int32.div level_position_in_era blocks_per_cycle
  in
  let cycle =
    Cycle_repr.add first_cycle (Int32.to_int cycles_since_era_start)
  in
  let cycle_position = Int32.rem level_position_in_era blocks_per_cycle in
  let level_position = Raw_level_repr.diff level first_level_in_alpha_family in
  let expected_commitment =
    Compare.Int32.(
      Int32.rem cycle_position blocks_per_commitment
      = Int32.pred blocks_per_commitment)
  in
  {level; level_position; cycle; cycle_position; expected_commitment}

let level_from_raw_aux ~cycle_eras level =
  let first_level_in_alpha_family =
    match List.rev cycle_eras with
    | [] -> assert false
    | {first_level; _} :: _ -> first_level
  in
  let era = era_of_level ~cycle_eras level in
  level_from_raw_with_era era ~first_level_in_alpha_family level

let level_from_raw ~cycle_eras ?offset l =
  let l =
    match offset with
    | None -> l
    | Some o -> Raw_level_repr.(of_int32_exn (Int32.add (to_int32 l) o))
  in
  level_from_raw_aux ~cycle_eras l

let first_level_in_cycle_from_eras ~cycle_eras cycle =
  let first_level_in_alpha_family =
    match List.rev cycle_eras with
    | [] -> assert false
    | {first_level; _} :: _ -> first_level
  in
  let era = era_of_cycle ~cycle_eras cycle in
  let cycle_position = Cycle_repr.diff cycle era.first_cycle in
  let offset = Int32.mul era.blocks_per_cycle cycle_position in
  let first_level_in_cycle =
    Raw_level_repr.(of_int32_exn (Int32.add (to_int32 era.first_level) offset))
  in
  level_from_raw_with_era era ~first_level_in_alpha_family first_level_in_cycle

let last_of_cycle ~cycle_eras level =
  let era = era_of_level ~cycle_eras level.level in
  Compare.Int32.(Int32.succ level.cycle_position = era.blocks_per_cycle)
