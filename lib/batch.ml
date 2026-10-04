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
    | Invalid of Refusal.t

  type t = prepared array

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
    | Invalid e -> Error (Invalid_input e)
    | Bsm_price (a, side, sigma) -> finish (Black.Bsm.price a side sigma)
    | Black76_price (a, side, sigma) ->
        finish (Black.Black76.price a side sigma)
    | Displaced_price (a, side, sigma) ->
        finish (Black.Displaced.price a side sigma)
    | Bachelier_price (a, side, sigma) -> finish (Bachelier.price a side sigma)

  let evaluate request = price (prepare request)
  let run requests = Array.map evaluate requests
  let compile requests = Array.map prepare requests
  let length = Array.length
  let execute batch = Array.map price batch
end
