// Original research adapter. QuantLib remains an external, pinned comparator.
#include <ql/exercise.hpp>
#include <ql/instruments/vanillaoption.hpp>
#include <ql/pricingengines/blackcalculator.hpp>
#include <ql/pricingengines/vanilla/qdfpamericanengine.hpp>
#include <ql/quotes/simplequote.hpp>
#include <ql/termstructures/yield/flatforward.hpp>
#include <ql/termstructures/volatility/equityfx/blackconstantvol.hpp>
#include <ql/time/calendars/nullcalendar.hpp>
#include <ql/time/daycounters/actual360.hpp>
#include <chrono>
#include <cmath>
#include <iostream>
#include <string>
using namespace QuantLib;
int main(int argc, char** argv) {
    if (argc==2 && std::string(argv[1])=="--help") {
        std::cout << "stdin: id kind side spot strike rate yield sigma time repetitions; kind european/accurate/high/fast\n"; return 0;
    }
    if (argc==2 && std::string(argv[1])=="--version") {std::cout<<"american-acceleration-reference 1\n";return 0;}
    if (argc!=1 && !(argc==2 && std::string(argv[1])=="--")) return 2;
    SavedSettings saved; const Date today(1, January, 2025);Settings::instance().evaluationDate()=today;
    std::string id,kind,side;double s,k,r,q,sigma,t;unsigned n;
    while (std::cin >> id >> kind >> side >> s >> k >> r >> q >> sigma >> t >> n) {
        try {
            if(n==0 || n>100000 || (side!="call" && side!="put") || s<=0 || k<0 || sigma<=0 || t<=0 || !std::isfinite(s+k+r+q+sigma+t))throw std::runtime_error("input bound");
            const auto type=side=="call"?Option::Call:Option::Put;
            auto european=[&]() {return BlackCalculator(type,k,s*std::exp((r-q)*t),sigma*std::sqrt(t),std::exp(-r*t)).value();};
            ext::shared_ptr<VanillaOption> option;
            if(kind!="european") {
                // Evaluation scope excludes dividends, delayed/Bermudan rights and negative rates.
                if(r<0 || t!=1.)throw std::runtime_error("specialized evaluation scope");
                const Actual360 dc;
                auto process=ext::make_shared<BlackScholesMertonProcess>(
                    Handle<Quote>(ext::make_shared<SimpleQuote>(s)),
                    Handle<YieldTermStructure>(ext::make_shared<FlatForward>(today,q,dc)),
                    Handle<YieldTermStructure>(ext::make_shared<FlatForward>(today,r,dc)),
                    Handle<BlackVolTermStructure>(ext::make_shared<BlackConstantVol>(today,NullCalendar(),sigma,dc)));
                auto scheme=kind=="high"?QdFpAmericanEngine::highPrecisionScheme():
                    kind=="accurate"?QdFpAmericanEngine::accurateScheme():QdFpAmericanEngine::fastScheme();
                if(kind!="high" && kind!="accurate" && kind!="fast")throw std::runtime_error("unknown scheme");
                option=ext::make_shared<VanillaOption>(ext::make_shared<PlainVanillaPayoff>(type,k),
                    ext::make_shared<AmericanExercise>(today,today+360,false));
                option->setPricingEngine(ext::make_shared<QdFpAmericanEngine>(process,scheme));
            }
            auto evaluate=[&]() {if(option){option->recalculate();return option->NPV();}return european();};
            const double expected=evaluate();if(!std::isfinite(expected))throw std::runtime_error("nonfinite result");
            for(unsigned round=0;round<3;++round) {
                const auto start=std::chrono::steady_clock::now();
                for(unsigned i=0;i<n;++i)if(evaluate()!=expected)throw std::runtime_error("changed replay");
                const auto elapsed=std::chrono::duration<double,std::nano>(std::chrono::steady_clock::now()-start).count()/n;
                std::cout<<id<<' '<<kind<<' '<<round<<' '<<std::hexfloat<<expected<<std::defaultfloat<<' '<<elapsed<<'\n';
            }
        } catch(const std::exception& e) {std::cout<<id<<" error "<<e.what()<<'\n';}
    }
    if(!std::cin.eof())return 2;
}
