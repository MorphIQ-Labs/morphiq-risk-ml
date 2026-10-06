// Original fixed-quote inverse adapter. Existing independent lattice and pinned
// QuantLib are research comparators, never runtime dependencies.
// Renaming the unused historical main removes C++'s implicit return-0 rule.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wreturn-type"
#define main morphiq_unused_lattice_main
#include "american_lattice.cpp"
#undef main
#pragma clang diagnostic pop
#ifdef MORPHIQ_QUANTLIB
#include <ql/exercise.hpp>
#include <ql/instruments/vanillaoption.hpp>
#include <ql/pricingengines/vanilla/fdblackscholesvanillaengine.hpp>
#include <ql/quotes/simplequote.hpp>
#include <ql/termstructures/yield/flatforward.hpp>
#include <ql/termstructures/volatility/equityfx/blackconstantvol.hpp>
#include <ql/time/calendars/nullcalendar.hpp>
#include <ql/time/daycounters/actual360.hpp>
#endif

static double evaluate(Row x, bool bermudan, double sigma) {
    x.sigma=sigma;
#ifdef MORPHIQ_QUANTLIB
    using namespace QuantLib;
    const Date today(1,January,2025); const Actual360 dc;
    auto date=[&](double t) { Date d=today+static_cast<Integer>(std::round(t*360.));
        if(dc.yearFraction(today,d)!=t) throw std::runtime_error("time mapping excluded"); return d; };
    auto process=ext::make_shared<BlackScholesMertonProcess>(
        Handle<Quote>(ext::make_shared<SimpleQuote>(x.s)),
        Handle<YieldTermStructure>(ext::make_shared<FlatForward>(today,x.q,dc)),
        Handle<YieldTermStructure>(ext::make_shared<FlatForward>(today,x.r,dc)),
        Handle<BlackVolTermStructure>(ext::make_shared<BlackConstantVol>(today,NullCalendar(),sigma,dc)));
    ext::shared_ptr<Exercise> exercise;
    if(bermudan) { std::vector<Date> dates;for(int i=0;i<=4;++i) if(i*.25>=x.opens)dates.push_back(date(i*.25));
        if(x.t!=1.)throw std::runtime_error("Bermudan reference horizon");
        exercise=ext::make_shared<BermudanExercise>(dates,false);
    } else exercise=ext::make_shared<AmericanExercise>(date(x.opens),date(x.t),false);
    VanillaOption option(ext::make_shared<PlainVanillaPayoff>(x.side=="call"?Option::Call:Option::Put,x.k),exercise);
    option.setPricingEngine(ext::make_shared<FdBlackScholesVanillaEngine>(process,x.n,x.n,2,FdmSchemeDesc::CrankNicolson()));
    return option.NPV();
#else
    if(bermudan && x.n%4)throw std::runtime_error("unmatched exercise grid");
    return price(x)[bermudan?2:0];
#endif
}
int main(int argc,char** argv) {
    bool price_only=false;
    if(argc==2 && std::string(argv[1])=="--price") price_only=true;
    else if(argc==2 && std::string(argv[1])=="--version") {std::cout<<"american-iv-reference 1\n";return 0;}
    else if(argc==2 && std::string(argv[1])=="--help") {std::cout<<"[--price|--] stdin: style plus existing American row; volatility field is exact quote in inverse mode.\n";return 0;}
    else if(argc!=1 && !(argc==2 && std::string(argv[1])=="--"))return 2;
#ifdef MORPHIQ_QUANTLIB
    QuantLib::SavedSettings saved; QuantLib::Settings::instance().evaluationDate()=QuantLib::Date(1,QuantLib::January,2025);
#endif
    unsigned count=0;
    try { for(std::string line;std::getline(std::cin,line);) {
        if(++count>512)throw std::runtime_error("row budget");
        const auto split=line.find(' ');const auto style=line.substr(0,split);
        if(split==std::string::npos || (style!="american" && style!="bermudan"))throw std::runtime_error("invalid style");
        Row x=parse_row(line.substr(split+1));const bool bermudan=style=="bermudan";
        std::cout<<x.id<<'\t'<<x.n<<'\t';
        try {
            double lo=.05,hi=.6;unsigned calls=0;
            auto f=[&](double s) {++calls;double p=evaluate(x,bermudan,s);if(!std::isfinite(p))throw std::runtime_error("nonfinite price");return p;};
            if(price_only){double v=f(x.sigma);std::cout<<"finite\t"<<std::hexfloat<<v<<'\t'<<v<<'\t'<<calls<<'\n';continue;}
            if(!(f(lo)<x.sigma && f(hi)>x.sigma))throw std::runtime_error("unresolved initial bracket");
            for(unsigned i=0;i<32;++i){double m=lo+(hi-lo)/2;double v=f(m);if(v<x.sigma)lo=m;else hi=m;}
            std::cout<<"finite\t"<<std::hexfloat<<lo<<'\t'<<hi<<'\t'<<calls<<'\n';
        } catch(const std::exception& e){std::cout<<"unresolved\t-\t-\t"<<clean(e.what())<<'\n';}
    }}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 2;}
}
