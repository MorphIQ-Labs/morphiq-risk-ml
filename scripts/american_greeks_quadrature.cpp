// Original independent derivative route over discounted Gaussian quadrature.
#define MORPHIQ_GREEK_REFERENCE
#include "american_piecewise_quadrature.cpp"
int main(int argc,char** argv) {
    if(int r=piecewise_cli(argc,argv,"greeks-quadrature 1");r!=-1)return r;
    try {unsigned count=0;for(std::string line;std::getline(std::cin,line);) {
        if(++count>512)throw std::runtime_error("row budget");
        auto spec=piecewise_row(line);const auto& p=spec.option.model.p;
        std::cout<<p.id<<'\t'<<p.n<<'\t';
        try {
            std::array<double,4> lo,hi;
            const double lv=solve(spec,false,&lo),hv=solve(spec,true,&hi);
            std::cout<<"finite\t"<<std::hexfloat<<lv<<'\t'<<hv;
            for(double a:lo) {if(!std::isfinite(a))throw std::runtime_error("nonfinite derivative");std::cout<<'\t'<<a;}
            for(double a:hi) {if(!std::isfinite(a))throw std::runtime_error("nonfinite derivative");std::cout<<'\t'<<a;}
            std::cout<<'\n';
        }catch(const std::exception& e){std::cout<<"unavailable\t"<<clean(e.what())<<'\n';}
    }}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 2;}
}
