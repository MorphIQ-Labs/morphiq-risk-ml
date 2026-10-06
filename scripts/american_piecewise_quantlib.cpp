// Original canonical adapter. QuantLib is an optional research dependency only.
#include "american_piecewise_io.hpp"
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

// Original curve adapters integrate the declared original words. No extrapolation.
class PiecewiseYield : public YieldTermStructure {
    Curve c; double horizon;
public:
    PiecewiseYield(Date d,DayCounter dc,Curve x,double t):YieldTermStructure(d,NullCalendar(),dc),c(std::move(x)),horizon(t){}
    Date maxDate() const override {return Date::maxDate();}
protected:
    DiscountFactor discountImpl(Time t) const override {
        QL_REQUIRE(t>=0 && t<=horizon,"curve query outside declared horizon");
        return std::exp(static_cast<double>(-integral(c,0,t)));
    }
};
class PiecewiseVariance : public BlackVarianceTermStructure {
    Curve c; double horizon;
public:
    PiecewiseVariance(Date d,DayCounter dc,Curve x,double t):BlackVarianceTermStructure(d,NullCalendar(),Following,dc),c(std::move(x)),horizon(t){}
    Date maxDate() const override {return Date::maxDate();}
    Real minStrike() const override {return 0;}
    Real maxStrike() const override {return QL_MAX_REAL;}
protected:
    Real blackVarianceImpl(Time t,Real) const override {
        QL_REQUIRE(t>=0 && t<=horizon,"variance query outside declared horizon");
        return static_cast<double>(integral(c,0,t,1));
    }
};

// This original step condition adapts only the cash convention. QuantLib still
// supplies meshing, differential operator, rollback and value interpolation.
class Liquidator : public StepCondition<Array> {
    PiecewiseRow spec; CashRow row; std::vector<double> stocks;
public:
    Liquidator(PiecewiseRow r, const Array& logs):spec(std::move(r)),row(spec.option.model) { for(auto x:logs) stocks.push_back(std::exp(x)); }
    void applyTo(Array& a,Time t) const override {
        const auto payoff=[&](double s) {return std::max(row.p.side=="call"?s-row.p.k:row.p.k-s,0.);};
        bool event=false;
        for(auto e:joint_cash(row)) if(e.first==t) {
            event=true;
            if(right_at(spec,t,2)) for(Size i=0;i<a.size();++i) a[i]=std::max(a[i],payoff(stocks[i]));
            Array mapped(a.size());
            const double zero=row.p.side=="call"?0:absorbing_put(spec,t);
            for(Size i=0;i<a.size();++i) {
                const double s=static_cast<double>(std::max(static_cast<long double>(stocks[i])-e.second,0.L));
                const Size j=std::upper_bound(stocks.begin(),stocks.end(),s)-stocks.begin();
                if(j==0) mapped[i]=zero+(a[0]-zero)*s/stocks[0];
                else if(j==stocks.size()) mapped[i]=a.back();
                else {double w=(s-stocks[j-1])/(stocks[j]-stocks[j-1]);mapped[i]=(1-w)*a[j-1]+w*a[j];}
                if(right_at(spec,t,1)) mapped[i]=std::max(mapped[i],payoff(stocks[i]));
            }
            a.swap(mapped);
        }
        if(!event && right_at(spec,t,0)) for(Size i=0;i<a.size();++i) a[i]=std::max(a[i],payoff(stocks[i]));
    }
};
int main(int argc, char** argv) {
    if (int result = piecewise_cli(argc, argv, "piecewise-quantlib 1"); result != -1) return result;
    const Date today(1, January, 2025);
    const Actual360 dc;
    SavedSettings saved;
    Settings::instance().evaluationDate() = today;
    unsigned count = 0;
    try {
        for (std::string line; std::getline(std::cin, line);) {
            if (++count > 512) throw std::runtime_error("row budget exceeded");
            const auto spec = piecewise_row(line); const auto& cash=spec.option.model; const Row x = cash.p;
            std::cout << x.id << '\t' << x.n << '\t';
            try {
                auto date = [&](double t) {
                    const double days = std::round(t*360.);
                    if (days < 0 || days > 36000) throw std::runtime_error("date range excluded");
                    const Date d = today + static_cast<Integer>(days);
#ifndef MORPHIQ_GREEK_REFERENCE
                    if (dc.yearFraction(today, d) != t) throw std::runtime_error("time mapping excluded");
#endif
                    // The Greek adapter's solver/curves/conditions consume the
                    // original Time values directly. Dates here belong only to
                    // the separate unmodified engine, which that adapter does
                    // not publish as a model-matched comparison.
                    return d;
                };
                std::vector<Date> rights; for(auto e:spec.option.exercise) rights.push_back(date(e.first));
                if(x.s==0 || x.k==0 || zero_volatility(spec) || x.t==0) throw std::runtime_error("analytical boundary excluded");
                DividendSchedule schedule; std::vector<Time> events=union_times(spec);
                for(auto e:cash.cash) {
                    if(e.first==0 || e.first==x.t) throw std::runtime_error("endpoint cash convention excluded");
                    schedule.push_back(ext::make_shared<FixedDividend>(e.second,date(e.first)));
                    events.push_back(e.first);
                }
                auto process = ext::make_shared<BlackScholesMertonProcess>(
                    Handle<Quote>(ext::make_shared<SimpleQuote>(x.s)),
                    Handle<YieldTermStructure>(ext::make_shared<PiecewiseYield>(today,dc,spec.q,x.t)),
                    Handle<YieldTermStructure>(ext::make_shared<PiecewiseYield>(today,dc,spec.r,x.t)),
                    Handle<BlackVolTermStructure>(ext::make_shared<PiecewiseVariance>(today,dc,spec.v,x.t)));
                ext::shared_ptr<Exercise> exercise;
                if(spec.american) exercise=ext::make_shared<AmericanExercise>(date(x.opens),date(x.t),false);
                else exercise=ext::make_shared<BermudanExercise>(rights,false);
                VanillaOption option(ext::make_shared<PlainVanillaPayoff>(
                        x.side == "call" ? Option::Call : Option::Put, x.k),
                    exercise);
                option.setPricingEngine(ext::make_shared<FdBlackScholesVanillaEngine>(
                    process,schedule,x.n,x.n,2,FdmSchemeDesc::CrankNicolson()));
                double baseline = 0.; bool baseline_ok = false; std::string baseline_reason;
                try {baseline = option.NPV(); baseline_ok = std::isfinite(baseline);}
                catch(const std::exception& error) {baseline_reason = clean(error.what());}
                auto mesh=ext::make_shared<FdmMesherComposite>(ext::make_shared<FdmBlackScholesMesher>(x.n,process,x.t,x.k));
                auto payoff=ext::make_shared<PlainVanillaPayoff>(x.side=="call"?Option::Call:Option::Put,x.k);
                auto calculator=ext::make_shared<FdmLogInnerValue>(payoff,mesh,0);
                auto condition=ext::make_shared<Liquidator>(spec,mesh->locations(0));
                auto composite=ext::make_shared<FdmStepConditionComposite>(std::list<std::vector<Time>>{events},FdmStepConditionComposite::Conditions{condition});
                FdmSolverDesc desc{mesh,{},composite,calculator,x.t,x.n,2};
                FdmBlackScholesSolver solver(Handle<GeneralizedBlackScholesProcess>(process),x.k,desc,FdmSchemeDesc::CrankNicolson());
                const double value = solver.valueAt(x.s);
                if (!std::isfinite(value)) throw std::runtime_error("nonfinite canonical price");
#ifdef MORPHIQ_GREEK_REFERENCE
                const double delta=solver.deltaAt(x.s),gamma=solver.gammaAt(x.s);
                std::cout << "finite\t" << std::hexfloat << value << '\t' << delta << '\t' << gamma << '\t';
                try {const double theta=solver.thetaAt(x.s);if(theta==Null<Real>())std::cout << "-";else std::cout << theta/365.;}
                catch(const std::exception&) {std::cout << "-";}
                std::cout << '\n';
#else
                std::cout << "finite\t" << std::hexfloat << value << "\t";
                if(baseline_ok) std::cout << baseline; else std::cout << "-";
                std::cout << "\t-\tpiecewise-coefficient exercise/liquidator adapter; unmodified cash Spot baseline has different floor/coincident/side conventions";
                if(!baseline_ok) std::cout << "; Spot unavailable: " << baseline_reason;
                std::cout << '\n';
#endif
            } catch (const std::exception& error) {
                std::cout << "exception\t-\t-\t-\t" << clean(error.what()) << '\n';
            }
        }
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n'; return 2;
    }
}
