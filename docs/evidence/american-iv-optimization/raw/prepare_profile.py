from pathlib import Path
root=Path('/tmp/morphiq-american-iv-opt');out=Path(__file__).resolve().parent
s=(root/'bench/american_iv.ml').read_text().replace('external monotonic : unit -> float = "morphiq_bench_monotonic"','let monotonic = Unix.gettimeofday')
a=s.index('let sample name');b=s.index('let run fields');s=s[:a]+'''let sample _ _ _ = ()
let profile operation =
  if Sys.argv.(3)="cpu" then (
    print_endline "READY";
    flush stdout;
    for _=1 to 16 do ignore (Sys.opaque_identity(operation ())) done
  ) else (
    let sites=Hashtbl.create 128 in
    let alloc (a:Gc.Memprof.allocation) =
      let key=Printexc.raw_backtrace_to_string a.callstack in
      let n=Option.value ~default:0 (Hashtbl.find_opt sites key) in
      Hashtbl.replace sites key (n+a.n_samples); None in
    let p=Gc.Memprof.start ~sampling_rate:0.0001 ~callstack_size:32
      {Gc.Memprof.null_tracker with alloc_minor=alloc;alloc_major=alloc} in
    for _=1 to 3 do ignore (Sys.opaque_identity(operation ())) done;
    Gc.Memprof.stop (); Gc.Memprof.discard p;
    Hashtbl.to_seq sites |> List.of_seq |> List.sort(fun (_,a) (_,b)->compare b a)
    |> List.iter(fun (stack,n)->Printf.printf "SAMPLES %d\\n%s\\n" n stack)
  )

'''+s[b:]
s=s.replace('let result = solve () in','let result = solve () in\n      profile solve;')
s=s[:s.index('let () =')]+'''let () =
 let ch=open_in Sys.argv.(1) in
 let rec find ()=let line=input_line ch in
  let fields=String.split_on_char ' ' line in
  if List.hd fields=Sys.argv.(2) then fields else find () in
 let fields=find () in close_in ch;run fields
'''
(out/'profile.ml').write_text(s)
