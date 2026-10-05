// Original canonical adapter. QuantLib is an optional research dependency only.
#include "american_runner_io.hpp"
#include <ql/exercise.hpp>
#include <ql/instruments/vanillaoption.hpp>
#include <ql/pricingengines/vanilla/fdblackscholesvanillaengine.hpp>
#include <ql/quotes/simplequote.hpp>
#include <ql/termstructures/yield/flatforward.hpp>
#include <ql/termstructures/volatility/equityfx/blackconstantvol.hpp>
#include <ql/time/calendars/nullcalendar.hpp>
#include <ql/time/daycounters/actual360.hpp>
using namespace QuantLib;

int main(int argc, char** argv) {
    if (int result = cli(argc, argv, "american-quantlib 1"); result != -1) return result;
    const Date today(1, January, 2025);
    const Actual360 dc;
    SavedSettings saved;
    Settings::instance().evaluationDate() = today;
    unsigned count = 0;
    try {
        for (std::string line; std::getline(std::cin, line);) {
            if (++count > 512) throw std::runtime_error("row budget exceeded");
            const Row x = parse_row(line);
            std::cout << x.id << '\t' << x.n << '\t';
            try {
                auto date = [&](double t) {
                    const double days = std::round(t*360.);
                    if (days < 0 || days > 36000) throw std::runtime_error("date range excluded");
                    const Date d = today + static_cast<Integer>(days);
                    if (dc.yearFraction(today, d) != t) throw std::runtime_error("time mapping excluded");
                    return d;
                };
                const Date expiry = date(x.t), opening = date(x.opens);
                auto process = ext::make_shared<BlackScholesMertonProcess>(
                    Handle<Quote>(ext::make_shared<SimpleQuote>(x.s)),
                    Handle<YieldTermStructure>(ext::make_shared<FlatForward>(today,x.q,dc)),
                    Handle<YieldTermStructure>(ext::make_shared<FlatForward>(today,x.r,dc)),
                    Handle<BlackVolTermStructure>(ext::make_shared<BlackConstantVol>(today,NullCalendar(),x.sigma,dc)));
                VanillaOption option(ext::make_shared<PlainVanillaPayoff>(
                        x.side == "call" ? Option::Call : Option::Put, x.k),
                    ext::make_shared<AmericanExercise>(opening,expiry,false));
                option.setPricingEngine(ext::make_shared<FdBlackScholesVanillaEngine>(
                    process,x.n,x.n,2,FdmSchemeDesc::CrankNicolson()));
                const double value = option.NPV();
                if (!std::isfinite(value)) throw std::runtime_error("nonfinite canonical price");
                std::cout << (x.t == 0 ? "incompatible" : "finite") << '\t'
                    << std::hexfloat << value << "\t-\t-\t"
                    << (x.t == 0 ? "Instrument expiry convention" : "exact word time mapping") << '\n';
            } catch (const std::exception& error) {
                std::cout << "exception\t-\t-\t-\t" << clean(error.what()) << '\n';
            }
        }
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n'; return 2;
    }
}
