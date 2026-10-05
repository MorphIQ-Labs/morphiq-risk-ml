// Original canonical adapter. QuantLib is an optional research dependency only.
#include "american_cash_io.hpp"
#include <ql/cashflows/dividend.hpp>
#include <ql/methods/finitedifferences/meshers/fdmmeshercomposite.hpp>
#include <ql/methods/finitedifferences/meshers/fdmblackscholesmesher.hpp>
#include <ql/methods/finitedifferences/solvers/fdmblackscholessolver.hpp>
#include <ql/methods/finitedifferences/utilities/fdminnervaluecalculator.hpp>
#include <ql/methods/finitedifferences/stepconditions/fdmstepconditioncomposite.hpp>
#include <ql/exercise.hpp>
#include <ql/instruments/vanillaoption.hpp>
#include <ql/pricingengines/vanilla/fdblackscholesvanillaengine.hpp>
#include <ql/quotes/simplequote.hpp>
#include <ql/termstructures/yield/flatforward.hpp>
#include <ql/termstructures/volatility/equityfx/blackconstantvol.hpp>
#include <ql/time/calendars/nullcalendar.hpp>
#include <ql/time/daycounters/actual360.hpp>
using namespace QuantLib;

// This original step condition adapts only the cash convention. QuantLib still
// supplies meshing, differential operator, rollback and value interpolation.
class Liquidator : public StepCondition<Array> {
    CashRow row; std::vector<double> stocks;
public:
    Liquidator(CashRow r, const Array& logs):row(std::move(r)) { for(auto x:logs) stocks.push_back(std::exp(x)); }
    void applyTo(Array& a,Time t) const override {
        const auto payoff=[&](double s) {return std::max(row.p.side=="call"?s-row.p.k:row.p.k-s,0.);};
        bool event=false;
        for(auto e:joint_cash(row)) if(e.first==t) {
            event=true;
            if(eligible(row,t,2)) for(Size i=0;i<a.size();++i) a[i]=std::max(a[i],payoff(stocks[i]));
            Array mapped(a.size());
            const double zero=row.p.side=="call"?0:row.p.k*std::exp(-row.p.r*(row.p.r<0?row.p.t-t:std::max(row.p.opens-t,0.)));
            for(Size i=0;i<a.size();++i) {
                const double s=static_cast<double>(std::max(static_cast<long double>(stocks[i])-e.second,0.L));
                const Size j=std::upper_bound(stocks.begin(),stocks.end(),s)-stocks.begin();
                if(j==0) mapped[i]=zero+(a[0]-zero)*s/stocks[0];
                else if(j==stocks.size()) mapped[i]=a.back();
                else {double w=(s-stocks[j-1])/(stocks[j]-stocks[j-1]);mapped[i]=(1-w)*a[j-1]+w*a[j];}
                if(eligible(row,t,1)) mapped[i]=std::max(mapped[i],payoff(stocks[i]));
            }
            a.swap(mapped);
        }
        if(!event && eligible(row,t,0)) for(Size i=0;i<a.size();++i) a[i]=std::max(a[i],payoff(stocks[i]));
    }
};
int main(int argc, char** argv) {
    if (int result = cli(argc, argv, "american-cash-quantlib 1"); result != -1) return result;
    const Date today(1, January, 2025);
    const Actual360 dc;
    SavedSettings saved;
    Settings::instance().evaluationDate() = today;
    unsigned count = 0;
    try {
        for (std::string line; std::getline(std::cin, line);) {
            if (++count > 512) throw std::runtime_error("row budget exceeded");
            const auto cash = cash_row(line); const Row x = cash.p;
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
                if(x.s==0 || x.k==0 || x.sigma==0 || x.t==0) throw std::runtime_error("analytical boundary excluded");
                DividendSchedule schedule; std::vector<Time> events{x.opens};
                for(auto e:cash.cash) {
                    if(e.first==0 || e.first==x.t) throw std::runtime_error("endpoint cash convention excluded");
                    schedule.push_back(ext::make_shared<FixedDividend>(e.second,date(e.first)));
                    events.push_back(e.first);
                }
                auto process = ext::make_shared<BlackScholesMertonProcess>(
                    Handle<Quote>(ext::make_shared<SimpleQuote>(x.s)),
                    Handle<YieldTermStructure>(ext::make_shared<FlatForward>(today,x.q,dc)),
                    Handle<YieldTermStructure>(ext::make_shared<FlatForward>(today,x.r,dc)),
                    Handle<BlackVolTermStructure>(ext::make_shared<BlackConstantVol>(today,NullCalendar(),x.sigma,dc)));
                VanillaOption option(ext::make_shared<PlainVanillaPayoff>(
                        x.side == "call" ? Option::Call : Option::Put, x.k),
                    ext::make_shared<AmericanExercise>(opening,expiry,false));
                option.setPricingEngine(ext::make_shared<FdBlackScholesVanillaEngine>(
                    process,schedule,x.n,x.n,2,FdmSchemeDesc::CrankNicolson()));
                const double baseline = option.NPV();
                auto mesh=ext::make_shared<FdmMesherComposite>(ext::make_shared<FdmBlackScholesMesher>(x.n,process,x.t,x.k));
                auto payoff=ext::make_shared<PlainVanillaPayoff>(x.side=="call"?Option::Call:Option::Put,x.k);
                auto calculator=ext::make_shared<FdmLogInnerValue>(payoff,mesh,0);
                auto condition=ext::make_shared<Liquidator>(cash,mesh->locations(0));
                auto composite=ext::make_shared<FdmStepConditionComposite>(std::list<std::vector<Time>>{events},FdmStepConditionComposite::Conditions{condition});
                FdmSolverDesc desc{mesh,{},composite,calculator,x.t,x.n,2};
                FdmBlackScholesSolver solver(Handle<GeneralizedBlackScholesProcess>(process),x.k,desc,FdmSchemeDesc::CrankNicolson());
                const double value = solver.valueAt(x.s);
                if (!std::isfinite(value)) throw std::runtime_error("nonfinite canonical price");
                std::cout << "finite\t" << std::hexfloat << value << "\t" << baseline
                    << "\t-\tmatched liquidator adapter; unmodified Spot baseline has different floor/coincident conventions\n";
            } catch (const std::exception& error) {
                std::cout << "exception\t-\t-\t-\t" << clean(error.what()) << '\n';
            }
        }
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n'; return 2;
    }
}
