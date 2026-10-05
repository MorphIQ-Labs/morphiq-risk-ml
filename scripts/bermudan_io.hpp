// Original research protocol for explicit exercise instants; no upstream code.
#ifndef MORPHIQ_BERMUDAN_IO_HPP
#define MORPHIQ_BERMUDAN_IO_HPP
#include "american_cash_io.hpp"
struct BermudanRow { CashRow model; std::vector<std::pair<double,unsigned>> exercise; };
inline BermudanRow bermudan_row(const std::string& line) {
    const auto split=line.find('|');
    if(split==std::string::npos) throw std::runtime_error("missing exercise separator");
    BermudanRow row{cash_row(line.substr(0,split)),{}};
    std::istringstream in(line.substr(split+1)); std::string token;
    if(!(in>>token)) throw std::runtime_error("missing exercise count");
    const unsigned n=integer(token); if(n==0 || n>64) throw std::runtime_error("exercise research budget");
    for(unsigned i=0;i<n;++i) {
        if(!(in>>token)) throw std::runtime_error("truncated exercise time"); const double t=word(token);
        if(!(in>>token)) throw std::runtime_error("truncated exercise side"); const unsigned phase=integer(token);
        bool event=false;for(auto e:row.model.cash)event|=e.first==t;
        const auto instant=std::make_pair(t,phase);
        if(t<0 || t>row.model.p.t || phase>2 || event!=(phase!=0) ||
           (!row.exercise.empty() && instant<=row.exercise.back())) throw std::runtime_error("exercise order/side");
        row.exercise.push_back(instant);
    }
    if(in>>token)throw std::runtime_error("extra exercise fields");
    if(row.exercise.front()!=std::make_pair(row.model.p.opens,row.model.opening) ||
       row.exercise.back()!=std::make_pair(row.model.p.t,row.model.expiry)) throw std::runtime_error("exercise endpoints");
    return row;
}
inline bool right_at(const BermudanRow& row,double t,unsigned side) {
    return std::find(row.exercise.begin(),row.exercise.end(),std::make_pair(t,side))!=row.exercise.end();
}
inline int bermudan_cli(int argc,char** argv,const char* version) {
    if(argc==2 && std::string(argv[1])=="--help") {
        std::cout<<"Read cash research protocol, then | count and exercise time-word/side pairs. Sides: 0=regular,1=before,2=after.\n";return 0;
    }
    return cli(argc,argv,version);
}
#endif
