// Large disposable fixture generator using the ORIGINAL C++ producer contract.
// No foobar process, user path, tag, audio file or real collection is accessed.
#include "../../src/bridge_contract.h"
#include "../../src/gzip_stored.h"
#include <filesystem>
#include <iostream>
#include <string>
#include <vector>

int main() {
    constexpr int kTrackCount = 54129;
    using namespace djbridge;
    const std::filesystem::path output =
        std::filesystem::current_path() / "contract-test-large-v3.tsv.gz";
    GzipStoredWriter stream(output);
    stream.write(kHeader);
    stream.write("\n");
    for (int i = 0; i < kTrackCount; ++i) {
        Record record;
        record.path = "X:\\SYNTHETIC_NO_REAL_MUSIC\\Artist" +
            std::to_string(i % 400) + "\\Fixture Track " +
            std::to_string(i) + ".flac";
        record.subsong = static_cast<std::uint32_t>(i % 3);
        record.artist = "CI Synthetic Artist";
        record.title = "Fixture Track " + std::to_string(i);
        record.album = "Fixture Album " + std::to_string(i / 12);
        record.genre = "Trance";
        record.bpm = "128.5";
        record.duration_seconds = "302.25";
        record.codec = "FLAC";
        record.bitrate = "900";
        record.extra_metadata_json =
            canonical_extra_metadata_json({{"MOOD", {"Euphoric", "Dark"}}});
        record.metadata_vectors_json = canonical_metadata_vectors_json({
            {"ARTIST", {"CI Synthetic Artist", "Guest"}},
            {"MOOD", {"Euphoric", "Dark"}},
            {"EMPTY", {""}}
        });
        record.tag_fingerprint = fingerprint_for(record);
        stream.write(to_tsv_line(record));
        stream.write("\n");
    }
    stream.finish();
    if (std::filesystem::file_size(output) < 100000)
        return 2;
    std::cout << "PASS C++ generated " << kTrackCount
              << " synthetic schema-v3 record payloads using original producer"
              << std::endl;
    return 0;
}
