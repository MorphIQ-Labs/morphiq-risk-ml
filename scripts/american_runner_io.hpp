// Original research adapter input protocol; no third-party implementation copied.
#ifndef MORPHIQ_AMERICAN_RUNNER_IO_HPP
#define MORPHIQ_AMERICAN_RUNNER_IO_HPP
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

struct Row {
    std::string id, side;
    unsigned n, first;
    double s, k, r, q, sigma, t, opens;
};
inline unsigned integer(const std::string& text) {
    if (text.empty() || text.find_first_not_of("0123456789") != std::string::npos)
        throw std::runtime_error("invalid integer");
    auto value = std::stoull(text);
    if (value > 16384) throw std::runtime_error("integer budget exceeded");
    return static_cast<unsigned>(value);
}
inline double word(const std::string& text) {
    if (text.size() != 16 || text.find_first_not_of("0123456789abcdef") != std::string::npos)
        throw std::runtime_error("invalid binary64 word");
    std::uint64_t bits = std::stoull(text, nullptr, 16);
    double value;
    static_assert(sizeof(value) == sizeof(bits));
    std::memcpy(&value, &bits, sizeof(value));
    if (!std::isfinite(value)) throw std::runtime_error("nonfinite input");
    return value;
}
inline Row parse_row(const std::string& line) {
    std::istringstream input(line);
    std::vector<std::string> tokens;
    for (std::string token; input >> token;) tokens.push_back(token);
    if (tokens.size() != 11) throw std::runtime_error("truncated or extra input fields");
    if (tokens[0].empty() || tokens[0].size() > 96 ||
        tokens[0].find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
            != std::string::npos) throw std::runtime_error("invalid case id");
    Row row{tokens[0], tokens[1], integer(tokens[2]), integer(tokens[3]),
            word(tokens[4]), word(tokens[5]), word(tokens[6]), word(tokens[7]),
            word(tokens[8]), word(tokens[9]), word(tokens[10])};
    if ((row.side != "call" && row.side != "put") || row.n < 2 || row.first > row.n ||
        row.s < 0 || row.k < 0 || row.sigma < 0 || row.t < 0 ||
        row.opens < 0 || row.opens > row.t) throw std::runtime_error("invalid model input");
    return row;
}
inline std::string clean(std::string value) {
    for (auto& c : value) if (c == '\t' || c == '\n' || c == '\r') c = ' ';
    return value;
}
inline int cli(int argc, char** argv, const char* version) {
    if (argc == 1 || (argc == 2 && std::string(argv[1]) == "--")) return -1;
    if (argc == 2 && std::string(argv[1]) == "--version") {
        std::cout << version << '\n'; return 0;
    }
    if (argc == 2 && std::string(argv[1]) == "--help") {
        std::cout << "Read stdin rows: id side steps first_exercise_index "
                     "spot strike rate yield volatility time opens (seven binary64 words).\n";
        return 0;
    }
    std::cerr << "unrecognized arguments\n"; return 2;
}
#endif
