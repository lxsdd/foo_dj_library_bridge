#include "../src/bridge_contract.h"
#include "../src/gzip_stored.h"

#include <cassert>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <vector>

int main() {
    using namespace djbridge;

    assert(kSchemaVersion == 2);
    assert(count_columns(kHeader) == 25);
    assert(kHeader.ends_with("\textra_metadata_json"));
    assert(sanitize_tsv("A\tB\nC\rD") == "A B C D");
    assert(is_core_metadata_name("GENRE"));
    assert(is_core_metadata_name("genre"));
    assert(is_core_metadata_name("CATALOG NUMBER"));
    assert(!is_core_metadata_name("MOOD"));

    std::vector<MetadataEntry> metadata = {
        {"GENRE", {"House"}},
        {"MOOD", {"Euphoric", "Dark"}},
        {"custom_tag", {"Foo"}},
        {"CUSTOM_TAG", {"Bar"}},
        {"EMPTY", {""}},
        {"Quoted", {"A\"B", "Line\nBreak"}}
    };
    const std::string extra = canonical_extra_metadata_json(metadata);
    assert(extra == R"({"CUSTOM_TAG":["Bar","Foo"],"MOOD":["Euphoric","Dark"],"Quoted":["A\"B","Line\nBreak"]})");
    assert(canonical_extra_metadata_json({}) == "{}");
    assert(extra.find("GENRE") == std::string::npos);
    assert(extra.find('\n') == std::string::npos);
    assert(extra.find('\t') == std::string::npos);

    Record r;
    r.path = "C:\\Music\\test.flac";
    r.subsong = 2;
    r.artist = "Artist";
    r.title = "Title";
    r.album = "Album";
    r.genre = "Trance";
    r.duration_seconds = "300";
    r.codec = "FLAC";
    r.bitrate = "900";
    r.extra_metadata_json = extra;
    r.tag_fingerprint = fingerprint_for(r);

    const auto line = to_tsv_line(r);
    assert(count_columns(line) == 25);
    assert(r.tag_fingerprint.size() == 16);

    Record r2 = r;
    assert(fingerprint_for(r2) == r.tag_fingerprint);
    r2.title = "Different";
    assert(fingerprint_for(r2) != r.tag_fingerprint);
    r2 = r;
    r2.extra_metadata_json = R"({"MOOD":["Calm"]})";
    assert(fingerprint_for(r2) != r.tag_fingerprint);

    const auto out = std::filesystem::current_path() / "contract-test.tsv.gz";
    {
        GzipStoredWriter gz(out);
        gz.write(kHeader);
        gz.write("\n");
        for (int i = 0; i < 3; ++i) {
            Record x = r;
            x.subsong = static_cast<std::uint32_t>(i);
            x.title = "Title " + std::to_string(i);
            x.tag_fingerprint = fingerprint_for(x);
            gz.write(to_tsv_line(x));
            gz.write("\n");
        }
        gz.finish();
    }
    assert(std::filesystem::file_size(out) > 32);

    const auto large = std::filesystem::current_path() / "large-gzip-test.gz";
    std::string payload(200000, 'x');
    payload[65534] = 'A';
    payload[65535] = 'B';
    payload[131069] = 'C';
    {
        GzipStoredWriter gz(large);
        gz.write(payload.substr(0, 70000));
        gz.write(payload.substr(70000));
        gz.finish();
    }
    assert(std::filesystem::file_size(large) > payload.size());

    std::cout << out.string() << "\n" << large.string() << "\n";
    return 0;
}
