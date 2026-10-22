#include "../src/bridge_contract.h"
#include "../src/gzip_stored.h"

#include <cassert>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <vector>

int main() {
    using namespace djbridge;

    assert(kSchemaVersion == 3);
    assert(count_columns(kHeader) == 26);
    assert(kHeader.ends_with("\textra_metadata_json\tmetadata_vectors_json"));
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
    const std::string vectors = canonical_metadata_vectors_json(metadata);
    assert(extra == R"({"CUSTOM_TAG":["Bar","Foo"],"MOOD":["Euphoric","Dark"],"Quoted":["A\"B","Line\nBreak"]})");
    assert(canonical_extra_metadata_json({}) == "{}");
    assert(extra.find("GENRE") == std::string::npos);
    assert(extra.find('\n') == std::string::npos);
    assert(extra.find('\t') == std::string::npos);
    assert(vectors == R"([{"name":"CUSTOM_TAG","values":["Bar"]},{"name":"custom_tag","values":["Foo"]},{"name":"EMPTY","values":[""]},{"name":"GENRE","values":["House"]},{"name":"MOOD","values":["Euphoric","Dark"]},{"name":"Quoted","values":["A\"B","Line\nBreak"]}])");
    assert(canonical_metadata_vectors_json({{"ARTIST", {"A", "A", ""}}, {"artist", {"B"}}}) == R"([{"name":"ARTIST","values":["A","A",""]},{"name":"artist","values":["B"]}])");

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
    r.metadata_vectors_json = vectors;
    r.tag_fingerprint = fingerprint_for(r);

    const auto line = to_tsv_line(r);
    assert(count_columns(line) == 26);
    assert(r.tag_fingerprint.size() == 16);

    // Cross-tool CUE provenance: path alone can never be a unique Bridge
    // identity. A hypothetical file-level row 0 and virtual rows 1/2 for
    // the *same path* remain distinct, with independent fingerprints.
    // File-level row 0 is not implicitly created from either virtual row.
    Record fileLevel = r;
    fileLevel.subsong = 0;
    Record virtualOne = r;
    virtualOne.subsong = 1;
    Record virtualTwo = r;
    virtualTwo.subsong = 2;
    assert(identity_key(fileLevel.path, 0) != identity_key(virtualOne.path, 1));
    assert(identity_key(virtualOne.path, 1) != identity_key(virtualTwo.path, 2));
    assert(identity_key(fileLevel.path, 0) != identity_key(virtualTwo.path, 2));
    assert(fingerprint_for(fileLevel) != fingerprint_for(virtualOne));
    assert(fingerprint_for(virtualOne) != fingerprint_for(virtualTwo));
    assert(to_tsv_line(fileLevel).starts_with(fileLevel.path + "\t0\t"));
    assert(to_tsv_line(virtualOne).starts_with(virtualOne.path + "\t1\t"));
    assert(to_tsv_line(virtualTwo).starts_with(virtualTwo.path + "\t2\t"));

    Record r2 = r;
    assert(fingerprint_for(r2) == r.tag_fingerprint);
    r2.title = "Different";
    assert(fingerprint_for(r2) != r.tag_fingerprint);
    r2 = r;
    r2.extra_metadata_json = R"({"MOOD":["Calm"]})";
    assert(fingerprint_for(r2) != r.tag_fingerprint);
    r2 = r;
    r2.metadata_vectors_json = R"([{"name":"ARTIST","values":["Artist","Guest"]}])";
    assert(fingerprint_for(r2) != r.tag_fingerprint);

    // This is the single owner of the language-neutral V3 / CUE golden
    // fixture. Downstream consumers pin its Git blob and test their own
    // readers, never copy this production C++ serialization algorithm.
    const auto golden = std::filesystem::current_path() /
        "tests/contracts/bridge-v3-cue-identity.tsv";
    std::ifstream fixture(golden, std::ios::binary);
    assert(fixture.is_open());
    std::string goldenHeader;
    assert(static_cast<bool>(std::getline(fixture, goldenHeader)));
    assert(goldenHeader == kHeader);
    std::vector<std::string> expectedWireRows;
    std::string goldenLine;
    while (std::getline(fixture, goldenLine)) {
        assert(count_columns(goldenLine) == 26);
        expectedWireRows.push_back(goldenLine);
    }
    assert(expectedWireRows.size() == 3);
    const std::vector<MetadataEntry> fixtureFields = {
        {"DATE", {"2026-10-22"}},
        {"GENRE", {"Trance"}},
        {"MOOD", {"Driving"}}
    };
    const std::string fixtureExtra = canonical_extra_metadata_json(fixtureFields);
    const std::string fixtureVectors = canonical_metadata_vectors_json(fixtureFields);
    assert(fixtureExtra == R"({"MOOD":["Driving"]})");
    for (std::uint32_t subsong = 0; subsong <= 2; ++subsong) {
        Record expected;
        expected.path = "SYNTHETIC:/Cue Mix.flac";
        expected.subsong = subsong;
        expected.artist = "Fixture Artist";
        expected.title = "Cue Track";
        expected.genre = "Trance";
        expected.duration_seconds = "300";
        expected.codec = "FLAC";
        expected.extra_metadata_json = fixtureExtra;
        expected.metadata_vectors_json = fixtureVectors;
        expected.tag_fingerprint = fingerprint_for(expected);
        assert(to_tsv_line(expected) == expectedWireRows[subsong]);
        // Identity is path + subsong. Virtual rows (1/2) must not promote
        // themselves into a physical file-level row (0).
        assert(identity_key(expected.path, subsong) !=
               identity_key(expected.path, (subsong + 1) % 3));
        if (subsong > 0) assert(expected.subsong != 0);
    }
    Record staleFixture;
    staleFixture.path = "SYNTHETIC:/Cue Mix.flac";
    staleFixture.subsong = 2;
    staleFixture.artist = "Fixture Artist";
    staleFixture.title = "Changed synthetic title";
    staleFixture.genre = "Trance";
    staleFixture.duration_seconds = "300";
    staleFixture.codec = "FLAC";
    staleFixture.extra_metadata_json = fixtureExtra;
    staleFixture.metadata_vectors_json = fixtureVectors;
    staleFixture.tag_fingerprint = fingerprint_for(staleFixture);
    assert(to_tsv_line(staleFixture) != expectedWireRows[2]);

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
