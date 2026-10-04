// Optional canonical comparator; QuantLib is not a runtime dependency.
#include <ql/exercise.hpp>
#include <ql/instruments/margrabeoption.hpp>
#include <ql/pricingengines/exotic/analyticeuropeanmargrabeengine.hpp>
#include <ql/quotes/simplequote.hpp>
#include <ql/termstructures/yield/flatforward.hpp>
#include <ql/termstructures/volatility/equityfx/blackconstantvol.hpp>
#include <ql/time/calendars/nullcalendar.hpp>
#include <ql/time/daycounters/actual360.hpp>
#include <cmath>
#include <cstring>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <string>
using namespace QuantLib;
static double decode(const std::string& word) {
    const auto bits = std::stoull(word, nullptr, 16);
    double x;
    static_assert(sizeof(x) == sizeof(bits));
    std::memcpy(&x, &bits, sizeof(x));
    return x;
}
int main() {
    const Date today(1, January, 2025);
    Settings::instance().evaluationDate() = today;
    const Actual360 dc;
    std::string id, words[9];
    while (std::cin >> id) {
        for (auto& word : words) if (!(std::cin >> word)) return 2;
        double p[9];
        for (int i=0; i<9; ++i) p[i]=decode(words[i]);
        for (double rate : {0.0, 0.05, -0.05}) {
            std::cout << id << '\t' << std::hexfloat << rate << '\t';
            const double days = p[7]*360.;
            if (!std::isfinite(days) || days < 0 || days > 36000 || std::floor(days) != days ||
                p[0] < 0 || p[1] < 0 || p[4] < 0 || p[5] < 0 || std::abs(p[6]) > 1 ||
                !std::isfinite(p[0]+p[1]+p[2]+p[3]+p[4]+p[5]+p[6])) {
                std::cout << "excluded\tinput-or-date-mapping\n";
                continue;
            }
            const Date maturity=today+static_cast<Integer>(days);
            const Time time=dc.yearFraction(today,maturity);
            if (time != p[7]) { std::cout << "excluded\ttime-not-exact\n"; continue; }
            try {
                auto risk=Handle<YieldTermStructure>(ext::make_shared<FlatForward>(today,rate,dc));
                auto process=[&](int i) {
                    auto spot=Handle<Quote>(ext::make_shared<SimpleQuote>(p[i]));
                    auto yield=Handle<YieldTermStructure>(ext::make_shared<FlatForward>(today,p[2+i],dc));
                    auto vol=Handle<BlackVolTermStructure>(ext::make_shared<BlackConstantVol>(today,NullCalendar(),p[4+i],dc));
                    return ext::make_shared<BlackScholesMertonProcess>(spot,yield,risk,vol);
                };
                MargrabeOption option(1,1,ext::make_shared<EuropeanExercise>(maturity));
                option.setPricingEngine(ext::make_shared<AnalyticEuropeanMargrabeEngine>(process(0),process(1),p[6]));
                const double result=option.NPV();
                std::cout << (std::isfinite(result)?"finite":"nonfinite") << '\t' << result << '\t' << time << '\n';
            } catch (const std::exception& e) {
                std::cout << "exception\t" << e.what() << '\n';
            }
        }
    }
}
