let hash data = Digest.BLAKE256.to_hex (Digest.BLAKE256.string data)

let validate ~columns ~expected data =
  let rows =
    String.split_on_char '\n' data
    |> List.filter (fun line ->
           String.trim line <> "" && not (String.starts_with ~prefix:"#" line))
  in
  if rows = [] then Error "empty reference data"
  else if
    not
      (List.for_all
         (fun row ->
           let fields =
             String.split_on_char ' ' row |> List.filter (( <> ) "")
           in
           List.mem (List.length fields) columns)
         rows)
  then Error "malformed reference row"
  else
    match expected with
    | Some (count, _) when count <> List.length rows ->
        Error "reference row count mismatch"
    | Some (_, digest) when hash data <> digest ->
        Error "reference content/order/multiplicity mismatch"
    | _ -> Ok rows

let lines ?(external_reference = false) ~columns ~names path =
  let reject why =
    Printf.eprintf "REFERENCE INPUT ERROR: %s: %s\n" path why;
    exit 3
  in
  let data =
    try In_channel.with_open_bin path In_channel.input_all
    with Sys_error why -> reject why
  in
  let expected =
    if external_reference then (
      Printf.eprintf
        "EXTERNAL REFERENCE: %s, blake2b256=%s; completeness and provenance \
         not certified\n"
        path (hash data);
      None)
    else
      let digest = hash data in
      let matches =
        List.filter_map
          (fun name ->
            match List.assoc_opt name Fixture_catalog.records with
            | Some ((_, h) as record) when h = digest -> Some record
            | _ -> None)
          names
      in
      match matches with
      | record :: _ -> Some record
      | [] -> reject "bytes do not match the declared committed fixture"
  in
  match validate ~columns ~expected data with
  | Ok rows -> rows
  | Error why -> reject why
