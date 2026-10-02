type per_year
type per_calendar_day
type 'unit time_rate = float
type 'coordinate per_volatility = float
type 'coordinate per_volatility_squared = float
type ('unit, 'coordinate) volatility_time_rate = float

let days_per_year = 365.0
let per_calendar_day annual = annual /. days_per_year
let annualise daily = daily *. days_per_year
let time_rate v = v
let per_volatility v = v
let per_volatility_squared v = v
let volatility_time_rate v = v
let annualise_volatility daily = daily *. days_per_year
