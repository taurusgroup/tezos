(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2020 Nomadic Labs <contact@nomadic-labs.com>                *)
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

open Base

let reset_functions = ref []

let declare_reset_function f = reset_functions := f :: !reset_functions

(* Prepare a promise that will resolve on SIGINT
   (e.g. when the user presses Ctrl+C).

   We need a new promise everytime because they get canceled. *)
let sigint =
  let received_sigint = ref false in
  fun () ->
    if !received_sigint then unit
    else
      let (promise, resolver) = Lwt.task () in
      Sys.(set_signal sigint)
        (Signal_handle
           (fun _ ->
             (* If the user presses Ctrl+C again, let the program die immediately. *)
             received_sigint := true ;
             Sys.(set_signal sigint) Signal_default ;
             Lwt.wakeup_later resolver ())) ;
      promise

exception Failed of string

let () =
  Printexc.register_printer
  @@ function Failed message -> Some message | _ -> None

let fail x = Printf.ksprintf (fun message -> raise (Failed message)) x

let global_starting_time = Unix.gettimeofday ()

(* Field [id] is used to be able to iterate on tests in order of registration.
   Field [time] contains the cumulated time taken by all successful runs of this test.
   Field [result] contains the result of the last time the test was run.
   If the test was not run, it contains [None]. *)
type test = {
  id : int;
  file : string;
  title : string;
  tags : string list;
  body : unit -> unit Lwt.t;
  mutable time : float;
  mutable run_count : int;
  mutable result : Log.test_result option;
}

let really_run ~progress_state ~iteration test =
  Log.info "Starting test: %s" test.title ;
  List.iter (fun reset -> reset ()) !reset_functions ;
  Lwt_main.run
  @@
  let (fail_promise, fail_awakener) = Lwt.task () in
  (* Ensure that errors raised from background promises are logged
     and cause the test to fail immediately. *)
  let already_woke_up_fail_promise = ref false in
  let handle_background_exception exn =
    let message = Printexc.to_string exn in
    Log.error "%s" message ;
    ( match test.result with
    | Some _ ->
        ()
    | None ->
        test.result <- Some (Log.Failed message) ) ;
    if not !already_woke_up_fail_promise then (
      already_woke_up_fail_promise := true ;
      Lwt.wakeup_later fail_awakener () )
  in
  Background.start handle_background_exception ;
  (* It may happen that the promise of the function resolves successfully
     at the same time as a background promise is rejected or that we
     receive SIGINT. To handle those race conditions, setting the value
     of [test.result] is done through [set_test_result], which makes sure that:
     - if the test was aborted, [test.result] is [Aborted];
     - otherwise, if anything went wrong, [test.result] is [Failed];
     - the error message in [Failed] is the first error that was encountered. *)
  let set_test_result new_result =
    match test.result with
    | None ->
        test.result <- Some new_result
    | Some old_result -> (
      match (old_result, new_result) with
      | (Successful, _) | (Failed _, Aborted) ->
          test.result <- Some new_result
      | (Failed _, (Successful | Failed _)) | (Aborted, _) ->
          () )
  in
  (* Run the test until it succeeds, fails, or we receive SIGINT. *)
  let main_temporary_directory = Temp.start () in
  let* () =
    let run_test () =
      let* () = test.body () in
      set_test_result Successful ; unit
    in
    let handle_exception = function
      | Lwt.Canceled ->
          (* Aborted with SIGINT, or [fail_promise] resolved (possibly because of
             an [async] promise). So we already logged what happened. *)
          unit
      | exn ->
          let message = Printexc.to_string exn in
          set_test_result (Failed message) ;
          Log.error "%s" message ;
          unit
    in
    let handle_sigint () =
      let* () = sigint () in
      Log.debug "Received SIGINT." ;
      set_test_result Aborted ;
      unit
    in
    let global_timeout =
      match Cli.options.global_timeout with
      | None ->
          []
      | Some delay ->
          let local_starting_time = Unix.gettimeofday () in
          let remaining_delay =
            max 0. (delay -. local_starting_time +. global_starting_time)
          in
          [ let* () = Lwt_unix.sleep remaining_delay in
            fail
              "the set of tests took more than specified global timeout (%gs) \
               to run"
              delay ]
    in
    let test_timeout =
      match Cli.options.test_timeout with
      | None ->
          []
      | Some delay ->
          [ let* () = Lwt_unix.sleep delay in
            fail "test took more than specified timeout (%gs) to run" delay ]
    in
    Lwt.catch
      (fun () ->
        Lwt.pick
          ( (run_test () :: handle_sigint () :: fail_promise :: global_timeout)
          @ test_timeout ))
      handle_exception
  in
  (* Terminate all remaining processes. *)
  let* () =
    Lwt.catch Process.clean_up
    @@ fun exn ->
    Log.warn "Failed to clean up processes: %s" (Printexc.to_string exn) ;
    unit
  in
  (* Remove temporary files. *)
  let kept_temp =
    try
      match Cli.options.temporary_file_mode with
      | Delete ->
          Temp.clean_up () ; false
      | Delete_if_successful ->
          if test.result = Some Successful then (Temp.clean_up () ; false)
          else (Temp.stop () ; true)
      | Keep ->
          Temp.stop () ; true
    with exn ->
      Log.warn "Failed to clean up: %s" (Printexc.to_string exn) ;
      true
  in
  if kept_temp then
    Log.report "Temporary files can be found in: %s" main_temporary_directory ;
  (* Resolve all pending promises so that they won't do anything
     (like raise [Canceled]) during the next test. *)
  let* () = Background.stop () in
  (* Update progress indicators. *)
  let test_result =
    match test.result with
    | None ->
        (* Should not happen: after the test ends we always set [result] to [Some].
           But if it does happen we assume that it failed and that we failed to
           maintain this invariant. *)
        Log.Failed "unknown error"
    | Some result ->
        result
  in
  let has_failed =
    match test_result with Successful -> false | Failed _ | Aborted -> true
  in
  Progress.update ~has_failed progress_state ;
  (* Display test result. *)
  Log.test_result ~progress_state ~iteration test_result test.title ;
  match test_result with
  | Successful ->
      return true
  | Failed _ ->
      Log.report
        "Try again with: %s --verbose --test %s"
        Sys.argv.(0)
        (Log.quote_shell test.title) ;
      return false
  | Aborted ->
      exit 2

let test_should_be_run ~file ~title ~tags =
  List.for_all (fun tag -> List.mem tag tags) Cli.options.tags_to_run
  && (not
        (List.exists (fun tag -> List.mem tag tags) Cli.options.tags_not_to_run))
  && ( match Cli.options.tests_to_run with
     | [] ->
         true
     | titles ->
         List.mem title titles )
  && (not (List.mem title Cli.options.tests_not_to_run))
  &&
  match Cli.options.files_to_run with
  | [] ->
      true
  | files ->
      List.mem file files

let tag_rex = rex "^[a-z0-9_]{1,32}$"

let check_tags tags =
  match List.filter (fun tag -> tag =~! tag_rex) tags with
  | [] ->
      ()
  | invalid_tags ->
      List.iter (Printf.eprintf "Invalid tag: %S\n") invalid_tags ;
      Printf.eprintf
        "Tags may only use lowercase letters, digits and underscores, and \
         must be at most 32 character long.\n" ;
      exit 1

let known_files = ref String_set.empty

let known_titles = ref String_set.empty

let known_tags = ref String_set.empty

let register_file file = known_files := String_set.add file !known_files

let register_title title = known_titles := String_set.add title !known_titles

let register_tag tag = known_tags := String_set.add tag !known_tags

(* Check that all [specified] values are in [!known]. *)
let check_existence kind known specified =
  String_set.iter
    (Log.warn "Unknown %s: %s" kind)
    (String_set.diff (String_set.of_list specified) !known)

(* Tests added using [register] and that match command-line filters. *)
let registered : test String_map.t ref = ref String_map.empty

(* Using [iter_registered] instead of [String_map.iter] allows to more easily
   change the representation of [registered] in the future if needed. *)
let iter_registered f =
  let list = ref [] in
  String_map.iter (fun _ test -> list := test :: !list) !registered ;
  let by_id {id = a; _} {id = b; _} = Int.compare a b in
  list := List.sort by_id !list ;
  List.iter (fun test -> f test) !list

let fold_registered acc f =
  String_map.fold (fun _ test acc -> f acc test) !registered acc

(* Map [register] as if it was a list, to obtain a list. *)
let map_registered_list f =
  let list = ref [] in
  (* By using [iter_registered] we ensure the resulting list is
     in order of registration. *)
  (iter_registered @@ fun test -> list := f test :: !list) ;
  List.rev !list

let list_tests format =
  match format with
  | `Tsv ->
      iter_registered
      @@ fun {file; title; tags; _} ->
      Printf.printf "%s\t%s\t%s\n%!" file title (String.concat " " tags)
  | `Ascii_art ->
      let file_header = "FILE" in
      let title_header = "TITLE" in
      let tags_header = "TAGS" in
      let list =
        map_registered_list
        @@ fun {file; title; tags; _} -> (file, title, String.concat ", " tags)
      in
      (* Compute the size of each column. *)
      let (file_size, title_size, tags_size) =
        List.fold_left
          (fun (max_file, max_title, max_tags) (file, title, tags) ->
            ( max max_file (String.length file),
              max max_title (String.length title),
              max max_tags (String.length tags) ))
          ( String.length file_header,
            String.length title_header,
            String.length tags_header )
          list
      in
      (* Prepare the line separator. *)
      let line =
        "+"
        ^ String.make (file_size + 2) '-'
        ^ "+"
        ^ String.make (title_size + 2) '-'
        ^ "+"
        ^ String.make (tags_size + 2) '-'
        ^ "+\n"
      in
      (* Print the header row. *)
      print_string line ;
      let center size header =
        let padding = size - String.length header in
        let left_padding = padding / 2 in
        let right_padding = padding - left_padding in
        String.make left_padding ' ' ^ header ^ String.make right_padding ' '
      in
      Printf.printf
        "| %s | %s | %s |\n"
        (center file_size file_header)
        (center title_size title_header)
        (center tags_size tags_header) ;
      print_string line ;
      (* Print rows. *)
      let pad size text =
        let padding = size - String.length text in
        text ^ String.make padding ' '
      in
      List.iter
        (fun (file, title, tags) ->
          Printf.printf
            "| %s | %s | %s |\n"
            (pad file_size file)
            (pad title_size title)
            (pad tags_size tags))
        list ;
      if list <> [] then print_string line ;
      ()

let display_time_summary () =
  let total_time = fold_registered 0. @@ fun acc {time; _} -> acc +. time in
  let tests_by_file =
    fold_registered String_map.empty
    @@ fun acc test ->
    String_map.add
      test.file
      (test :: (String_map.find_opt test.file acc |> Option.value ~default:[]))
      acc
  in
  let show_time seconds =
    let seconds = int_of_float seconds in
    if seconds < 60 then Printf.sprintf "%ds" seconds
    else Printf.sprintf "%dmin %ds" (seconds / 60) (seconds mod 60)
  in
  let print_time prefix title time =
    Printf.printf
      "%s[%d%% - %s] %s\n"
      prefix
      (int_of_float (time *. 100. /. total_time))
      (show_time time)
      title
  in
  let print_time_for_file file tests =
    print_time
      ""
      file
      (List.fold_left (fun acc {time; _} -> acc +. time) 0. tests) ;
    List.iter (fun {title; time; _} -> print_time "- " title time) tests
  in
  String_map.iter print_time_for_file tests_by_file ;
  ()

type marshaled_test = {
  file : string;
  title : string;
  tags : string list;
  time : float;
}

let record_results filename =
  (* Remove the closure ([body]). *)
  let marshaled_tests =
    map_registered_list
    @@ fun {id = _; file; title; tags; body = _; time; run_count; result = _} ->
    {file; title; tags; time = time /. float (max 1 run_count)}
  in
  (* Write to file using Marshal.
     This is not very robust but enough for the purposes of this file. *)
  try
    with_open_out filename
    @@ fun file ->
    Marshal.to_channel file (marshaled_tests : marshaled_test list) []
  with Sys_error error -> Log.warn "Failed to write record: %s\n%!" error

let read_recorded_results filename : marshaled_test list =
  with_open_in filename Marshal.from_channel

let suggest_jobs (tests : marshaled_test list) =
  let job_count = max 1 Cli.options.job_count in
  (* [jobs] is an array of pairs where the first value is the total time of the job
     and the second value is the list of tests that are currently allocated to this job. *)
  let jobs = Array.make job_count (0., []) in
  let allocate test =
    let smallest_job =
      let best_index = ref 0 in
      let best_time = ref max_float in
      for i = 0 to job_count - 1 do
        let (job_time, _) = jobs.(i) in
        if job_time < !best_time then (
          best_index := i ;
          best_time := job_time )
      done ;
      !best_index
    in
    let (job_time, job_tests) = jobs.(smallest_job) in
    jobs.(smallest_job) <- (job_time +. test.time, test :: job_tests)
  in
  (* Finding the optimal partition is NP-complete.
     We use a heuristic to find an approximation: allocate longest tests first,
     then fill the gaps with smaller tests. *)
  let longest_first {time = a; _} {time = b; _} = Float.compare b a in
  List.iter allocate (List.sort longest_first tests) ;
  (* Jobs are allocated, now display them. *)
  let display_job ~negate (total_job_time, job_tests) =
    print_endline
      ( String.concat
          " "
          (List.map
             (fun test ->
               Printf.sprintf
                 "%s %s"
                 (if negate then "--not-test" else "--test")
                 (Log.quote_shell test.title))
             job_tests)
      ^ " # "
      ^ string_of_float total_job_time
      ^ "s" )
  in
  let all_other_tests = ref [] in
  for i = 0 to job_count - 2 do
    display_job ~negate:false jobs.(i) ;
    List.iter
      (fun test -> all_other_tests := test :: !all_other_tests)
      (snd jobs.(i))
  done ;
  (* The last job uses --not-test so that if a test is added and the job list is not
     updated, the new test is automatically added to the last job.
     Note: if [job_count] is 1, this actually outputs no --not-test at all
     since [all_other_tests] is empty, which is consistent
     because it means to run all tests. *)
  display_job ~negate:true (fst jobs.(job_count - 1), !all_other_tests)

let output_junit filename =
  with_open_out filename
  @@ fun ch ->
  let echo x =
    Printf.ksprintf (fun s -> output_string ch s ; output_char ch '\n') x
  in
  let (count, fail_count, skipped_count, total_time) =
    fold_registered (0, 0, 0, 0.)
    @@ fun (count, fail_count, skipped_count, total_time) test ->
    ( count + 1,
      (fail_count + match test.result with Some (Failed _) -> 1 | _ -> 0),
      ( skipped_count
      + match test.result with None | Some Aborted -> 1 | _ -> 0 ),
      total_time +. test.time )
  in
  echo {|<?xml version="1.0" encoding="UTF-8" ?>|} ;
  echo
    {|<testsuites id="tezt" name="Tezt" tests="%d" failures="%d" skipped="%d" time="%f">|}
    count
    fail_count
    skipped_count
    total_time ;
  echo
    {|  <testsuite id="tezt" name="Tezt" tests="%d" failures="%d" skipped="%d" time="%f">|}
    count
    fail_count
    skipped_count
    total_time ;
  ( iter_registered
  @@ fun test ->
  match test.result with
  | None | Some Aborted ->
      (* Skipped test, do not output. *)
      ()
  | Some (Successful | Failed _) ->
      let replace_entities s =
        let buffer = Buffer.create (String.length s * 2) in
        for i = 0 to String.length s - 1 do
          match s.[i] with
          | '"' ->
              Buffer.add_string buffer "&quot;"
          | '&' ->
              Buffer.add_string buffer "&amp;"
          | '\'' ->
              Buffer.add_string buffer "&apos;"
          | '<' ->
              Buffer.add_string buffer "&lt;"
          | '>' ->
              Buffer.add_string buffer "&gt;"
          | c ->
              Buffer.add_char buffer c
        done ;
        Buffer.contents buffer
      in
      let title = replace_entities test.title in
      echo
        {|    <testcase id="%s" name="%s: %s" time="%f">|}
        title
        (replace_entities test.file)
        title
        test.time ;
      ( match test.result with
      | None | Some Successful | Some Aborted ->
          ()
      | Some (Failed message) ->
          echo
            {|      <failure message="test failed" type="ERROR">%s</failure>|}
            (replace_entities message) ) ;
      echo "    </testcase>" ) ;
  echo "  </testsuite>" ; echo "</testsuites>" ; ()

let next_id = ref 0

let register ~__FILE__ ~title ~tags body =
  let file = Filename.basename __FILE__ in
  ( match String_map.find_opt title !registered with
  | None ->
      ()
  | Some {file = other_file; tags = other_tags; _} ->
      Printf.eprintf "Error: there are several tests with title: %S\n" title ;
      Printf.eprintf
        "- first seen in: %s with tags: %s\n"
        other_file
        (String.concat ", " other_tags) ;
      Printf.eprintf
        "- also seen in: %s with tags: %s\n%!"
        file
        (String.concat ", " tags) ;
      exit 1 ) ;
  check_tags tags ;
  register_file file ;
  register_title title ;
  List.iter register_tag tags ;
  let id = !next_id in
  incr next_id ;
  if test_should_be_run ~file ~title ~tags then
    let test =
      {id; file; title; tags; body; time = 0.; run_count = 0; result = None}
    in
    registered := String_map.add title test !registered

let run () =
  (* Check command-line options. *)
  check_existence "--file" known_files Cli.options.files_to_run ;
  check_existence "--test" known_titles Cli.options.tests_to_run ;
  check_existence
    "tag"
    known_tags
    (Cli.options.tags_to_run @ Cli.options.tags_not_to_run) ;
  (* Print a warning if no test was selected. *)
  if String_map.is_empty !registered then (
    Printf.eprintf
      "No test found for filters: %s\n%!"
      (String.concat
         " "
         ( List.map
             (fun x -> "--file " ^ Log.quote_shell x)
             Cli.options.files_to_run
         @ List.map
             (fun x -> "--test " ^ Log.quote_shell x)
             Cli.options.tests_to_run
         @ Cli.options.tags_to_run
         @ List.map (sf "/%s") Cli.options.tags_not_to_run )) ;
    if Cli.options.list = None then
      prerr_endline
        "You can use --list to get the list of tests and their tags." ) ;
  (* Actually run the tests (or list them). *)
  match (Cli.options.list, Cli.options.suggest_jobs) with
  | (Some format, None) ->
      list_tests format
  | (None, Some record_file) -> (
    match read_recorded_results record_file with
    | exception Sys_error error ->
        Printf.eprintf "Failed to read record: %s\n%!" error ;
        exit 1
    | record ->
        suggest_jobs record )
  | (Some _, Some _) ->
      prerr_endline
        "Cannot use both --list and --suggest-jobs at the same time."
  | (None, None) ->
      let exception Stop in
      let a_test_failed = ref false in
      let rec run iteration =
        match Cli.options.loop_mode with
        | Count n when n < iteration ->
            ()
        | _ ->
            let progress_state =
              Progress.create ~total:(String_map.cardinal !registered)
            in
            let run_and_measure_time (test : test) =
              let start = Unix.gettimeofday () in
              let success = really_run ~progress_state ~iteration test in
              let time = Unix.gettimeofday () -. start in
              test.run_count <- test.run_count + 1 ;
              test.time <- test.time +. time ;
              if not success then (
                a_test_failed := true ;
                if not Cli.options.keep_going then raise Stop )
            in
            iter_registered run_and_measure_time ;
            run (iteration + 1)
      in
      (try run 1 with Stop -> ()) ;
      Option.iter output_junit Cli.options.junit ;
      Option.iter record_results Cli.options.record ;
      if Cli.options.time then display_time_summary () ;
      if !a_test_failed then exit 1
