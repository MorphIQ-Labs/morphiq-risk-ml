type (_, _) model =
  | Bsm : (Black.Bsm.inputs, Vol.lognormal) model
  | Black76 : (Black.Black76.inputs, Vol.lognormal) model
  | Displaced : (Black.Displaced.inputs, Vol.lognormal) model
  | Bachelier : (Bachelier.inputs, Vol.normal) model

type (_, _) operation =
  | Evaluate :
      'c Vol.t * ('c, 'a) Production.quantity * 'a
      -> ('c, 'a Production.certified) operation
  | Implied : float -> ('c, 'c Iv.t) operation

type 'a request =
  | Request : ('i, 'c) model * 'i * Side.t * ('c, 'a) operation -> 'a request

let execute (type i c a)
    (module M : Production.MODEL with type inputs = i and type coordinate = c)
    (inputs : i) side (operation : (c, a) operation) :
    (a, Production.error) result =
  match M.admit inputs with
  | Error e -> Error e
  | Ok admitted -> (
      match operation with
      | Evaluate (sigma, quantity, max_error) ->
          M.evaluate admitted side sigma quantity ~max_error
      | Implied quote -> M.implied admitted side quote)

let evaluate : type a. a request -> (a, Production.error) result =
 fun (Request (model, inputs, side, operation)) ->
  match model with
  | Bsm -> execute (module Production.Bsm) inputs side operation
  | Black76 -> execute (module Production.Black76) inputs side operation
  | Displaced -> execute (module Production.Displaced) inputs side operation
  | Bachelier -> execute (module Production.Bachelier) inputs side operation

let run requests = Array.map evaluate requests

let evaluate_many (type i c) (model : (i, c) model) (inputs : i) side
    (sigma : c Vol.t) (requests : c Production.request list) =
  let run
      (module M : Production.MULTI_OUTPUT_MODEL
        with type inputs = i
         and type coordinate = c) =
    match requests with
    | [] -> []
    | _ -> (
        match M.admit inputs with
        | Error e ->
            List.map
              (fun (Production.Request (q, _)) ->
                Production.Outcome (q, Error e))
              requests
        | Ok admitted -> M.evaluate_many admitted side sigma requests)
  in
  match model with
  | Bsm -> run (module Production.Bsm)
  | Black76 -> run (module Production.Black76)
  | Displaced -> run (module Production.Displaced)
  | Bachelier -> run (module Production.Bachelier)

module Fast = struct
  type request = Price : ('i, 'c) model * 'i * Side.t * 'c Vol.t -> request
  type error = Invalid_input of Refusal.t | Numerical_failure
  type outcome = (float, error) result

  type prepared =
    | Bsm_price of Black.Bsm.admitted * Side.t * Vol.lognormal Vol.t
    | Black76_price of Black.Black76.admitted * Side.t * Vol.lognormal Vol.t
    | Displaced_price of Black.Displaced.admitted * Side.t * Vol.lognormal Vol.t
    | Bachelier_price of Bachelier.admitted * Side.t * Vol.normal Vol.t
    | Middle_price of Bachelier.Fast_middle.t
    | Invalid of Refusal.t

  type slot = Scalar of prepared | Native of int

  type t =
    | Scalar_batch of prepared array
    | Native_batch of { slots : slot array; kernel : Bachelier_native.t }

  let prepare (Price (model, inputs, side, sigma)) =
    match model with
    | Bsm -> (
        match Black.Bsm.admit inputs with
        | Ok a -> Bsm_price (a, side, sigma)
        | Error e -> Invalid e)
    | Black76 -> (
        match Black.Black76.admit inputs with
        | Ok a -> Black76_price (a, side, sigma)
        | Error e -> Invalid e)
    | Displaced -> (
        match Black.Displaced.admit inputs with
        | Ok a -> Displaced_price (a, side, sigma)
        | Error e -> Invalid e)
    | Bachelier -> (
        match Bachelier.admit inputs with
        | Ok a -> Bachelier_price (a, side, sigma)
        | Error e -> Invalid e)

  let finish value =
    if Float.is_finite value && value >= 0.0 then Ok value
    else Error Numerical_failure

  let price = function
    | Middle_price p -> finish (Bachelier.Fast_middle.price p)
    | Invalid e -> Error (Invalid_input e)
    | Bsm_price (a, side, sigma) -> finish (Black.Bsm.price a side sigma)
    | Black76_price (a, side, sigma) ->
        finish (Black.Black76.price a side sigma)
    | Displaced_price (a, side, sigma) ->
        finish (Black.Displaced.price a side sigma)
    | Bachelier_price (a, side, sigma) -> finish (Bachelier.price a side sigma)

  let evaluate request = price (prepare request)
  let run requests = Array.map evaluate requests

  let compile requests =
    let n = Array.length requests in
    (* Performance dispatch is separate from numerical selection. Count model
       identities before admission, so selected rows can discard admitted
       temporaries immediately instead of retaining them through packing. *)
    let bachelier_count =
      if n >= 32 && Bachelier_native.default_enabled then
        Array.fold_left
          (fun n (Price (model, _, _, _)) ->
            match model with Bachelier -> n + 1 | _ -> n)
          0 requests
      else 0
    in
    if bachelier_count < 32 || bachelier_count < n - bachelier_count then
      Scalar_batch (Array.map prepare requests)
    else
      let entries =
        Array.map
          (fun request ->
            match prepare request with
            | Bachelier_price (a, side, sigma) as entry -> (
                match Bachelier.Fast_middle.prepare a side sigma with
                | Some p -> Middle_price p
                | None -> entry)
            | entry -> entry)
          requests
      in
      let count =
        Array.fold_left
          (fun n -> function Middle_price _ -> n + 1 | _ -> n)
          0 entries
      in
      (* Even if there are too few native rows, keep their typed preparation
         for scalar evaluation: do not throw away work or cache prices. *)
      if count < 32 || count < n - count then Scalar_batch entries
      else
        let cursor = ref 0 in
        let rec next_value () =
          let entry = entries.(!cursor) in
          incr cursor;
          match entry with Middle_price p -> p | _ -> next_value ()
        in
        let values = Array.init count (fun _ -> next_value ()) in
        let next = ref 0 in
        let slots =
          Array.map
            (function
              | Middle_price _ ->
                  let slot = Native !next in
                  incr next;
                  slot
              | entry -> Scalar entry)
            entries
        in
        Native_batch { slots; kernel = Bachelier_native.compile values }

  let length = function
    | Scalar_batch entries -> Array.length entries
    | Native_batch p -> Array.length p.slots

  let execute = function
    | Scalar_batch entries -> Array.map price entries
    | Native_batch p ->
        let values = Bachelier_native.execute p.kernel in
        Array.map
          (function
            | Scalar entry -> price entry | Native i -> finish values.(i))
          p.slots
end
