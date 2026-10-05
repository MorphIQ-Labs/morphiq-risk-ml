// Original piecewise-coefficient research protocol; no upstream source copied.
#ifndef MORPHIQ_AMERICAN_PIECEWISE_IO_HPP
#define MORPHIQ_AMERICAN_PIECEWISE_IO_HPP
#include "bermudan_io.hpp"
struct Curve { double initial; std::vector<std::pair<double,double>> changes; };
struct PiecewiseRow { BermudanRow option; bool american; Curve r,q,v; };
inline PiecewiseRow piecewise_row(const std::string& line) {
    std::vector<std::string> parts;std::istringstream split(line);
    for(std::string s;std::getline(split,s,'|');)parts.push_back(s);
    if(parts.size()!=5)throw std::runtime_error("five piecewise fields required");
    auto cash=cash_row(parts[0]);std::istringstream rights(parts[1]);std::string tok;
    if(!(rights>>tok))throw std::runtime_error("missing exercise count");
    bool american=integer(tok)==0;
    BermudanRow option{cash,{}};
    if(american) {if(rights>>tok)throw std::runtime_error("extra American exercise fields");}
    else option=bermudan_row(parts[0]+"|"+parts[1]);
    auto curve=[&](const std::string& part,double initial,bool volatility) {
        Curve c{initial,{}};std::istringstream in(part);
        if(!(in>>tok))throw std::runtime_error("missing curve count");
        auto n=integer(tok);if(n>64)throw std::runtime_error("curve research budget");
        for(unsigned i=0;i<n;++i) {
            if(!(in>>tok))throw std::runtime_error("truncated curve time");double t=word(tok);
            if(!(in>>tok))throw std::runtime_error("truncated curve level");double a=word(tok);
            if(t<=0 || t>=cash.p.t || (!c.changes.empty() && t<=c.changes.back().first) || (volatility && a<0))throw std::runtime_error("curve order/domain");
            c.changes.emplace_back(t,a);
        }
        if(in>>tok)throw std::runtime_error("extra curve fields");return c;
    };
    return {option,american,curve(parts[2],cash.p.r,false),curve(parts[3],cash.p.q,false),curve(parts[4],cash.p.sigma,true)};
}
inline double level(const Curve& c,double t) {
    auto it=std::upper_bound(c.changes.begin(),c.changes.end(),t,[](double t,const auto& e){return t<e.first;});
    return it==c.changes.begin()?c.initial:std::prev(it)->second;
}
inline long double integral(const Curve& c,double a,double b,int mode=0) {
    long double sum=0;double lo=a,value=level(c,a);
    auto term=[&](double hi){long double x=value; if(mode==1)x*=x;else if(mode==2)x=std::max(-x,0.L);sum+=x*(static_cast<long double>(hi)-lo);lo=hi;};
    for(auto e:c.changes)if(e.first>a && e.first<b){term(e.first);value=e.second;}
    term(b);return sum;
}
inline bool zero_volatility(const PiecewiseRow& x) {if(x.v.initial!=0)return false;for(auto e:x.v.changes)if(e.second!=0)return false;return true;}
inline bool right_at(const PiecewiseRow& x,double t,unsigned phase) {
    return x.american?eligible(x.option.model,t,phase):right_at(x.option,t,phase);
}
inline std::vector<double> union_times(const PiecewiseRow& x) {
    const auto& row=x.option.model;std::vector<double> times{0,row.p.opens,row.p.t};
    for(auto e:row.cash)times.push_back(e.first);for(auto e:x.option.exercise)times.push_back(e.first);
    for(const Curve* c:{&x.r,&x.q,&x.v})for(auto e:c->changes)times.push_back(e.first);
    std::sort(times.begin(),times.end());times.erase(std::unique(times.begin(),times.end()),times.end());return times;
}
inline double absorbing_put(const PiecewiseRow& x,double t) {
    const auto& p=x.option.model.p;long double best=0;
    auto add=[&](double u){if(u>=t && u>=p.opens)best=std::max(best,std::exp(-integral(x.r,t,u)));};
    if(x.american){add(std::max(t,p.opens));add(p.t);for(auto e:x.r.changes)add(e.first);}
    else for(auto e:x.option.exercise)add(e.first);
    return static_cast<double>(p.k*best);
}
inline int piecewise_cli(int argc,char** argv,const char* version) {
    if(argc==2 && std::string(argv[1])=="--help") {std::cout<<"Cash protocol | exercise count (0=American) and time/side pairs | rate change count and time/level pairs | yield changes | volatility changes. All numbers are original binary64 words; base levels and horizon are in the cash protocol.\n";return 0;}
    return cli(argc,argv,version);
}
#endif
