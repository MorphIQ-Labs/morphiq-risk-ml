// Original independent discounted Gaussian quadrature; no PDE or policy solver.
#include "american_piecewise_io.hpp"
static double solve(const PiecewiseRow& spec, bool upper) {
    const auto& row=spec.option.model; const auto& p=row.p;
    if(p.t==0 || p.s==0 || p.k==0 || zero_volatility(spec)) throw std::runtime_error("analytical reference row");
    const auto cash=joint_cash(row);
    const double scale=std::max(p.s,p.k), top=32*scale;
    std::vector<double> x{0,p.s,p.k};
    for(unsigned i=0;i<=16*p.n;++i) x.push_back(scale*std::exp2(-14.+19.*i/(16*p.n)));
    std::sort(x.begin(),x.end()); x.erase(std::unique(x.begin(),x.end()),x.end());
    const auto payoff=[&](double s) {return std::max(p.side=="call"?s-p.k:p.k-s,0.);};
    std::vector<double> v(x.size()),next(v.size()); for(size_t i=0;i<x.size();++i) v[i]=payoff(x[i]);
    auto outside=[&](double s,double t) {
        if(upper) return (p.side=="call"?s:p.k)*std::exp(static_cast<double>(integral(p.side=="call"?spec.q:spec.r,t,p.t,2)));
        return 0.; // universal lower exterior envelope, not an extra exercise right
    };
    auto interpolate=[&](double s,double t) {
        if(s>=top) return outside(s,t);
        const auto j=std::upper_bound(x.begin(),x.end(),s)-x.begin();
        if(j==0) return v[0];
        const double w=(s-x[j-1])/(x[j]-x[j-1]); return (1-w)*v[j-1]+w*v[j];
    };
    const auto times=union_times(spec);
    double later=p.t;
    for(auto it=times.rbegin();it!=times.rend();++it) {
        const double t=*it;
        if(t<later) {
            const double r=level(spec.r,t),q=level(spec.q,t),sigma=level(spec.v,t);
            const double dt=(later-t)/p.n, discount=std::exp(-r*dt);
            const double a=std::exp((r-q-.5*sigma*sigma)*dt), b=std::exp(sigma*std::sqrt(3*dt));
            // Fixed transition stencils per slab; time-dependent exterior values stay explicit.
            struct Sample {size_t j; double w,s;}; std::vector<std::array<Sample,3>> map(x.size());
            for(size_t i=0;i<x.size();++i) for(unsigned z=0;z<3;++z) {
                double s=x[i]*a*(z==0?1/b:z==1?1:b); auto j=std::upper_bound(x.begin(),x.end(),s)-x.begin();
                map[i][z]={static_cast<size_t>(j),j>0 && static_cast<size_t>(j)<x.size()?(s-x[j-1])/(x[j]-x[j-1]):0.,s};
            }
            for(unsigned k=1;k<=p.n;++k) {
                const double now=k==p.n?t:later-k*dt, future=now+dt;
                for(size_t i=0;i<x.size();++i) {
                    double sum=0;
                    for(unsigned z=0;z<3;++z) {const auto m=map[i][z]; const double val=m.j==0?v[0]:m.j==x.size()?outside(m.s,future):(1-m.w)*v[m.j-1]+m.w*v[m.j]; sum+=(z==1?2./3:1./6)*val;}
                    next[i]=discount*sum;
                    // Coefficient knots confer no Bermudan exercise right.
                    if(spec.american && k<p.n && now>=p.opens)next[i]=std::max(next[i],payoff(x[i]));
                }
                v.swap(next);
            }
        }
        for(auto e:cash) if(e.first==t && !(t==p.t && row.expiry==1) && !(t==0 && row.valuation==2)) {
            if(right_at(spec,t,2)) for(size_t i=0;i<x.size();++i) v[i]=std::max(v[i],payoff(x[i]));
            for(size_t i=0;i<x.size();++i) { const double s=static_cast<double>(std::max(static_cast<long double>(x[i])-e.second,0.L)); next[i]=interpolate(s,t); if(right_at(spec,t,1)) next[i]=std::max(next[i],payoff(x[i])); }
            v.swap(next);
        }
        const bool cash_date=std::any_of(cash.begin(),cash.end(),[&](const auto& e){return e.first==t;});
        const unsigned phase=cash_date?(t==0 && row.valuation==2?2:t==p.t && row.expiry==1?1:99):0;
        if(phase!=99 && right_at(spec,t,phase)) for(size_t i=0;i<x.size();++i) v[i]=std::max(v[i],payoff(x[i]));
        later=t;
    }
    return v[std::lower_bound(x.begin(),x.end(),p.s)-x.begin()];
}
int main(int argc,char** argv) {
    if(int r=piecewise_cli(argc,argv,"piecewise-quadrature 1");r!=-1)return r;
    try {unsigned count=0; for(std::string line;std::getline(std::cin,line);) {if(++count>512) throw std::runtime_error("row budget"); auto x=piecewise_row(line); std::cout<<x.option.model.p.id<<'\t'<<x.option.model.p.n<<'\t'; try {auto lo=solve(x,false),hi=solve(x,true); if(!std::isfinite(lo)||!std::isfinite(hi)||hi<lo)throw std::runtime_error("invalid boundary pair"); std::cout<<"finite\t"<<std::hexfloat<<lo<<'\t'<<hi<<'\n';}catch(const std::exception& e){std::cout<<"unavailable\t-\t"<<clean(e.what())<<'\n';}} }
    catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 2;}
}
