open Morphiq_risk
module A=Early_exercise.Bsm
module I=A.Implied_volatility
let get=function Ok x->x|Error _->failwith "refusal"
let v x=get(Vol.lognormal x)
let () =
 let p=A.{spot=100.;strike=100.;rate=0.05;dividend_yield=0.02;time_to_expiry=1.;opens_at=0.;volatility=v 0.77} in
 let limits=A.{max_nodes=8192;max_steps=2*131072;max_policy_solves=2*1048576;max_row_visits=2*1000000000;max_workspace_bytes=8388608;policy_iterations=64} in
 let pricing=get(A.configure ~tolerance:100. ~space_cells:32 ~time_steps:32 ~domain_expansions:3 ~limits) in
 let cfg=get(I.configure ~pricing ~lower:(v 0.05) ~upper:(v 0.6) ~width:1. ~max_evaluations:2) in
 let dates=Array.map(fun time->A.{time;side=Regular})[|0.;0.5;1.|] in
 let a=get(A.admit_bermudan p dates) in
 let out=get(I.solve cfg a Side.Put (get(I.quote 10.))) in
 Printf.printf "%s %s %h %h\n" out.lower.price.method_name out.upper.price.method_name out.lower.price.value out.upper.price.value
