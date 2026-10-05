// Original cash-event research protocol. Binary64 words denote original inputs.
#ifndef MORPHIQ_AMERICAN_CASH_IO_HPP
#define MORPHIQ_AMERICAN_CASH_IO_HPP
#include "american_runner_io.hpp"
#include <algorithm>
struct CashRow { Row p; unsigned valuation, opening, expiry; std::vector<std::pair<double,double>> cash; };
inline CashRow cash_row(const std::string& line) {
    std::istringstream in(line); std::string base, token;
    for (int i=0;i<11;++i) { if (!(in>>token)) throw std::runtime_error("truncated base"); base+=token+" "; }
    CashRow x{parse_row(base),0,0,0,{}};
    auto number=[&]() { if (!(in>>token)) throw std::runtime_error("truncated cash metadata"); return integer(token); };
    x.valuation=number(); x.opening=number(); x.expiry=number(); const auto count=number();
    if (count>16 || x.valuation>2 || x.opening>2 || x.expiry>2) throw std::runtime_error("cash research budget/side");
    for (unsigned i=0;i<count;++i) {
        if (!(in>>token)) throw std::runtime_error("truncated cash time"); const double t=word(token);
        if (!(in>>token)) throw std::runtime_error("truncated cash amount"); const double d=word(token);
        if(t<0 || t>x.p.t || d<0 || (!x.cash.empty() && t<x.cash.back().first)) throw std::runtime_error("cash schedule");
        x.cash.emplace_back(t,d);
    }
    if(in>>token) throw std::runtime_error("extra cash fields");
    auto check=[&](double t,unsigned side) { bool event=false; for(auto e:x.cash) event|=e.first==t; if(event!=(side!=0)) throw std::runtime_error("cash side without matching event"); };
    check(0,x.valuation); check(x.p.opens,x.opening); check(x.p.t,x.expiry);
    if((x.p.opens==0 && x.valuation>x.opening)||(x.p.opens==x.p.t && x.opening>x.expiry)) throw std::runtime_error("instant ordering");
    return x;
}
inline bool eligible(const CashRow& x,double t,unsigned phase) { return (t>x.p.opens || (t==x.p.opens && phase>=x.opening)) && (t<x.p.t || (t==x.p.t && phase<=x.expiry)); }
inline std::vector<std::pair<double,long double>> joint_cash(const CashRow& x) {
    std::vector<std::pair<double,long double>> out;
    for(auto e:x.cash) { if(!out.empty() && out.back().first==e.first) out.back().second+=e.second; else out.emplace_back(e.first,e.second); }
    return out;
}
#endif
