#include "bridge_contract.h"

#include <array>
#include <iomanip>
#include <sstream>

namespace djbridge {
namespace {

void fnv_append(std::uint64_t& hash, std::string_view value) {
    constexpr std::uint64_t kPrime = 1099511628211ULL;
    for (unsigned char c : value) {
        hash ^= c;
        hash *= kPrime;
    }
    hash ^= 0xFFu;
    hash *= kPrime;
}

std::string u32_to_string(std::uint32_t value) {
    return std::to_string(value);
}

} // namespace

std::string sanitize_tsv(std::string_view value) {
    std::string out;
    out.reserve(value.size());
    bool previous_space = false;
    for (unsigned char c : value) {
        if (c == '\t' || c == '\r' || c == '\n' || c == 0) {
            if (!previous_space) out.push_back(' ');
            previous_space = true;
        } else {
            out.push_back(static_cast<char>(c));
            previous_space = (c == ' ');
        }
    }
    while (!out.empty() && out.back() == ' ') out.pop_back();
    return out;
}

std::string identity_key(std::string_view path, std::uint32_t subsong) {
    std::string out(path);
    out.push_back('\n');
    out += std::to_string(subsong);
    return out;
}

std::string fingerprint_for(const Record& record) {
    std::uint64_t hash = 14695981039346656037ULL;
    const std::string subsong = u32_to_string(record.subsong);
    const std::array<std::string_view, 23> values = {
        record.path, subsong, record.artist, record.artists,
        record.title, record.original_title, record.remixed_by, record.album,
        record.album_artist, record.track_number, record.total_tracks,
        record.disc_number, record.total_discs, record.date, record.genre,
        record.style, record.bpm, record.label, record.catalog_number,
        record.duration_seconds, record.isrc, record.codec, record.bitrate
    };
    for (auto value : values) fnv_append(hash, value);

    std::ostringstream oss;
    oss << std::hex << std::setfill('0') << std::setw(16) << hash;
    return oss.str();
}

std::string to_tsv_line(const Record& record) {
    std::array<std::string, 24> values = {
        sanitize_tsv(record.path), std::to_string(record.subsong),
        sanitize_tsv(record.artist), sanitize_tsv(record.artists),
        sanitize_tsv(record.title), sanitize_tsv(record.original_title),
        sanitize_tsv(record.remixed_by), sanitize_tsv(record.album),
        sanitize_tsv(record.album_artist), sanitize_tsv(record.track_number),
        sanitize_tsv(record.total_tracks), sanitize_tsv(record.disc_number),
        sanitize_tsv(record.total_discs), sanitize_tsv(record.date),
        sanitize_tsv(record.genre), sanitize_tsv(record.style),
        sanitize_tsv(record.bpm), sanitize_tsv(record.label),
        sanitize_tsv(record.catalog_number), sanitize_tsv(record.duration_seconds),
        sanitize_tsv(record.isrc), sanitize_tsv(record.codec),
        sanitize_tsv(record.bitrate), sanitize_tsv(record.tag_fingerprint)
    };

    std::string out;
    for (std::size_t i = 0; i < values.size(); ++i) {
        if (i) out.push_back('\t');
        out += values[i];
    }
    return out;
}

std::size_t count_columns(std::string_view line) {
    std::size_t count = 1;
    for (char c : line) if (c == '\t') ++count;
    return count;
}

} // namespace djbridge
