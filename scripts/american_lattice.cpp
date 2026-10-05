// Original two-point moment-matched reference, independent of QuantLib and the runtime.
#include "american_runner_io.hpp"
#include <algorithm>
#include <limits>

static std::array<double, 3> price(const Row& x) {
    if (x.s == 0 || x.sigma == 0 || x.t == 0)
        throw std::runtime_error("boundary requires analytical route");
    const double dt = x.t / x.n;
    const double h = x.sigma * std::sqrt(dt);
    const double probability = std::expm1((x.r-x.q)*dt+h) / std::expm1(2*h);
    const double discount = std::exp(-x.r*dt), ratio = std::exp(2*h);
    if (!std::isfinite(probability) || probability < 0 || probability > 1)
        throw std::runtime_error("inadmissible probability");
    if (!std::isfinite(discount) || discount == 0 || !std::isfinite(ratio) || ratio <= 1)
        throw std::runtime_error("unresolved step arithmetic");
    const bool bermudan = x.n % 4 == 0;
    std::array<std::vector<double>, 3> values;
    for (auto& v : values) v.resize(x.n+1);
    auto payoff = [&](double s) { return std::max(x.side == "call" ? s-x.k : x.k-s, 0.0); };
    for (unsigned i = x.n;; --i) {
        double stock = x.s * std::exp(-static_cast<double>(i)*h);
        if (stock == 0 || !std::isfinite(stock)) throw std::runtime_error("unresolved stock grid");
        for (unsigned j = 0; j <= i; ++j) {
            if (!std::isfinite(stock)) throw std::runtime_error("stock overflow");
            const double g = payoff(stock);
            if (i == x.n) {
                for (auto& v : values) v[j] = g;
            } else {
                for (unsigned route = 0; route < 3; ++route) {
                    auto& v = values[route];
                    const double continuation = discount*((1-probability)*v[j]+probability*v[j+1]);
                    const bool exercise = i >= x.first &&
                        (route == 0 || (route == 2 && bermudan && i % (x.n/4) == 0));
                    v[j] = exercise ? std::max(g, continuation) : continuation;
                    if (!std::isfinite(v[j])) throw std::runtime_error("value overflow");
                }
            }
            if (j < i) stock *= ratio;
        }
        if (i == 0) break;
    }
    return {values[0][0], values[1][0], values[2][0]};
}
int main(int argc, char** argv) {
    if (int result = cli(argc, argv, "american-lattice 1"); result != -1) return result;
    unsigned count = 0;
    try {
        for (std::string line; std::getline(std::cin, line);) {
            if (++count > 512) throw std::runtime_error("row budget exceeded");
            const Row row = parse_row(line);
            std::cout << row.id << '\t' << row.n << '\t';
            try {
                const auto values = price(row);
                std::cout << "finite\t" << std::hexfloat << values[0] << '\t' << values[1] << '\t';
                if (row.n % 4 == 0) std::cout << values[2]; else std::cout << '-';
                std::cout << "\tcrr\n";
            } catch (const std::exception& error) {
                std::cout << "unavailable\t-\t-\t-\t" << clean(error.what()) << '\n';
            }
        }
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n'; return 2;
    }
}
