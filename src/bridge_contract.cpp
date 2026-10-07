#include "bridge_contract.h"

#include <algorithm>
#include <array>
#include <iomanip>
#include <sstream>

namespace djbridge {
namespace {

char ascii_lower(char c) {
    if (c >= 'A' && c <= 'Z') return static_cast<char>(c - 'A' + 'a');
    return c;
}

std::string ascii_fold(std::string_view value) {
    std::string out(value);
    for (char& c : out) c = ascii_lower(c);
    return out;
}

bool ascii_iequals(std::string_view a, std::string_view b) {
    if (a.size() != b.size()) return false;
    for (std::size_t i = 0; i < a.size(); ++i) {
        if (ascii_lower(a[i]) != ascii_lower(b[i])) return false;
    }
    return true;
}

std::string json_escape(std::string_view value) {
    static constexpr char kHex[] = "0123456789abcdef";
    std::string out;
    out.reserve(value.size() + 8);
    for (unsigned char c : value) {
        switch (c) {
        case '"': out += "\\\""; break;
        case '\\': out += "\\\\"; break;
        case '\b': out += "\\b"; break;
        case '\f': out += "\\f"; break;
        case '\n': out += "\\n"; break;
        case '\r': out += "\\r"; break;
        case '\t': out += "\\t"; break;
        default:
            if (c < 0x20) {
                out += "\\u00";
                out.push_back(kHex[(c >> 4) & 0x0F]);
                out.push_back(kHex[c & 0x0F]);
            } else {
                out.push_back(static_cast<char>(c));
            }
        }
    }
    return out;
}

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

bool is_core_metadata_name(std::string_view name) {
    static constexpr std::array<std::string_view, 26> kCoreNames = {
        "ARTIST", "ARTISTS", "TITLE", "ORIGINAL TITLE", "REMIXED BY",
        "ALBUM", "ALBUM ARTIST", "TRACKNUMBER", "TRACK", "TOTALTRACKS",
        "TRACKTOTAL", "DISCNUMBER", "DISC", "TOTALDISCS", "DISCTOTAL",
        "DATE", "YEAR", "GENRE", "STYLE", "BPM", "LABEL", "PUBLISHER",
        "CATALOGNUMBER", "CATALOG NUMBER", "CATALOG", "ISRC"
    };
    return std::any_of(kCoreNames.begin(), kCoreNames.end(), [name](std::string_view core) {
        return ascii_iequals(name, core);
    });
}

std::string canonical_extra_metadata_json(std::vector<MetadataEntry> fields) {
    fields.erase(std::remove_if(fields.begin(), fields.end(), [](const MetadataEntry& field) {
        if (field.name.empty() || is_core_metadata_name(field.name)) return true;
        return std::none_of(field.values.begin(), field.values.end(), [](const std::string& value) { return !value.empty(); });
    }), fields.end());

    for (auto& field : fields) {
        field.values.erase(std::remove(field.values.begin(), field.values.end(), std::string{}), field.values.end());
    }

    std::sort(fields.begin(), fields.end(), [](const MetadataEntry& a, const MetadataEntry& b) {
        const std::string af = ascii_fold(a.name);
        const std::string bf = ascii_fold(b.name);
        if (af != bf) return af < bf;
        return a.name < b.name;
    });

    std::vector<MetadataEntry> merged;
    for (auto& field : fields) {
        if (!merged.empty() && ascii_iequals(merged.back().name, field.name)) {
            merged.back().values.insert(merged.back().values.end(), field.values.begin(), field.values.end());
        } else {
            merged.push_back(std::move(field));
        }
    }

    std::string out = "{";
    for (std::size_t fieldIndex = 0; fieldIndex < merged.size(); ++fieldIndex) {
        if (fieldIndex) out.push_back(',');
        const auto& field = merged[fieldIndex];
        out.push_back('"');
        out += json_escape(field.name);
        out += "\":[";
        for (std::size_t valueIndex = 0; valueIndex < field.values.size(); ++valueIndex) {
            if (valueIndex) out.push_back(',');
            out.push_back('"');
            out += json_escape(field.values[valueIndex]);
            out.push_back('"');
        }
        out.push_back(']');
    }
    out.push_back('}');
    return out;
}

std::string canonical_metadata_vectors_json(std::vector<MetadataEntry> fields) {
    fields.erase(std::remove_if(fields.begin(), fields.end(), [](const MetadataEntry& field) {
        return field.name.empty();
    }), fields.end());

    std::stable_sort(fields.begin(), fields.end(), [](const MetadataEntry& a, const MetadataEntry& b) {
        const std::string af = ascii_fold(a.name);
        const std::string bf = ascii_fold(b.name);
        if (af != bf) return af < bf;
        return a.name < b.name;
    });

    std::string out = "[";
    for (std::size_t fieldIndex = 0; fieldIndex < fields.size(); ++fieldIndex) {
        if (fieldIndex) out.push_back(',');
        const auto& field = fields[fieldIndex];
        out += "{\"name\":\"";
        out += json_escape(field.name);
        out += "\",\"values\":[";
        for (std::size_t valueIndex = 0; valueIndex < field.values.size(); ++valueIndex) {
            if (valueIndex) out.push_back(',');
            out.push_back('"');
            out += json_escape(field.values[valueIndex]);
            out.push_back('"');
        }
        out += "]}";
    }
    out.push_back(']');
    return out;
}
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
    const std::array<std::string_view, 25> values = {
        record.path, subsong, record.artist, record.artists,
        record.title, record.original_title, record.remixed_by, record.album,
        record.album_artist, record.track_number, record.total_tracks,
        record.disc_number, record.total_discs, record.date, record.genre,
        record.style, record.bpm, record.label, record.catalog_number,
        record.duration_seconds, record.isrc, record.codec, record.bitrate,
        record.extra_metadata_json, record.metadata_vectors_json
    };
    for (auto value : values) fnv_append(hash, value);

    std::ostringstream oss;
    oss << std::hex << std::setfill('0') << std::setw(16) << hash;
    return oss.str();
}

std::string to_tsv_line(const Record& record) {
    std::array<std::string, 26> values = {
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
        sanitize_tsv(record.bitrate), sanitize_tsv(record.tag_fingerprint),
        sanitize_tsv(record.extra_metadata_json),
        sanitize_tsv(record.metadata_vectors_json)
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
