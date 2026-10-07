#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace djbridge {

inline constexpr int kSchemaVersion = 3;
inline constexpr std::string_view kHeader =
    "path\tsubsong\tartist\tartists\ttitle\toriginal_title\tremixed_by\talbum\talbum_artist\ttrack_number\ttotal_tracks\tdisc_number\ttotal_discs\tdate\tgenre\tstyle\tbpm\tlabel\tcatalog_number\tduration_seconds\tisrc\tcodec\tbitrate\ttag_fingerprint\textra_metadata_json";

struct MetadataEntry {
    std::string name;
    std::vector<std::string> values;
};

struct Record {
    std::string path;
    std::uint32_t subsong = 0;
    std::string artist;
    std::string artists;
    std::string title;
    std::string original_title;
    std::string remixed_by;
    std::string album;
    std::string album_artist;
    std::string track_number;
    std::string total_tracks;
    std::string disc_number;
    std::string total_discs;
    std::string date;
    std::string genre;
    std::string style;
    std::string bpm;
    std::string label;
    std::string catalog_number;
    std::string duration_seconds;
    std::string isrc;
    std::string codec;
    std::string bitrate;
    std::string tag_fingerprint;
    std::string extra_metadata_json;
    std::string metadata_vectors_json;
};

bool is_core_metadata_name(std::string_view name);
std::string canonical_extra_metadata_json(std::vector<MetadataEntry> fields);
std::string canonical_metadata_vectors_json(std::vector<MetadataEntry> fields);
std::string sanitize_tsv(std::string_view value);
std::string identity_key(std::string_view path, std::uint32_t subsong);
std::string fingerprint_for(const Record& record);
std::string to_tsv_line(const Record& record);
std::size_t count_columns(std::string_view line);

} // namespace djbridge
