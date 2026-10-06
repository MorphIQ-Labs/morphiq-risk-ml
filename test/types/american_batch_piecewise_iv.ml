open Morphiq_risk

let invalid a settings quote =
  Batch.American.Request
    {
      id = "bad";
      model = Piecewise a;
      side = Side.Call;
      outputs = [ Output (Implied (settings, quote)) ];
    }
