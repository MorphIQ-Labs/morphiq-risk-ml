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
