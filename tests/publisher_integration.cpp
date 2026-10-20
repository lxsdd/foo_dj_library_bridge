#include "../src/publisher.h"
#include "../src/bridge_contract.h"

#include <windows.h>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace fs = std::filesystem;
using namespace std::chrono_literals;

namespace {
void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

std::pair<std::string, std::string> read_state(const fs::path& path) {
    std::ifstream stream(path, std::ios::binary);
    if (!stream) return {};
    std::string generation, complete, count, line;
    while (std::getline(stream, line)) {
        const auto split = line.find('\t');
        if (split == std::string::npos) continue;
        const auto key = line.substr(0, split);
        const auto value = line.substr(split + 1);
        if (key == "generation") generation = value;
        if (key == "complete") complete = value;
        if (key == "item_count") count = value;
    }
    return {generation + ":" + complete, count};
}

void capture(const fs::path& live, const fs::path& output,
             unsigned generation, unsigned count) {
    const auto deadline = std::chrono::steady_clock::now() + 30s;
    const auto state = live / "bridge-state.tsv";
    const auto payload = live / "digital-items.tsv.gz";
    const std::string expected = std::to_string(generation) + ":1";
    for (;;) {
        const auto [marker, items] = read_state(state);
        if (marker == expected && items == std::to_string(count) &&
            fs::exists(payload)) break;
        if (std::chrono::steady_clock::now() >= deadline) {
            throw std::runtime_error("Timed out at generation " +
                std::to_string(generation) + " marker=" + marker +
                " items=" + items);
        }
        std::this_thread::sleep_for(75ms);
    }

    // Between read and copy no new request is submitted by this test, so a
    // complete marker and matching gzip payload constitute one stable snapshot.
    fs::create_directories(output);
    fs::copy_file(state, output / "bridge-state.tsv",
                  fs::copy_options::overwrite_existing);
    fs::copy_file(payload, output / "digital-items.tsv.gz",
                  fs::copy_options::overwrite_existing);
    require(read_state(output / "bridge-state.tsv").first == expected,
            "Captured state marker mismatch");
    std::cout << "PUBLISHER_STAGE_" << generation << "=PASS count="
              << count << std::endl;
}

djbridge::Record make_record(unsigned id, const std::string& title) {
    djbridge::Record record;
    record.path = "C:\\SyntheticCI\\Track" + std::to_string(id) + ".flac";
    record.subsong = id % 3;
    record.artist = "Synthetic Artist";
    record.title = title;
    record.album = "Synthetic CI Album";
    record.genre = "Trance";
    record.bpm = "128";
    record.duration_seconds = "240.5";
    record.codec = "FLAC";
    record.extra_metadata_json = R"({"MOOD":["Synthetic","CI"]})";
    record.metadata_vectors_json =
        djbridge::canonical_metadata_vectors_json({
            {"TITLE", {title}}, {"ARTIST", {"Synthetic Artist", ""}},
            {"MOOD", {"Synthetic", "CI"}}
        });
    record.tag_fingerprint = djbridge::fingerprint_for(record);
    return record;
}
}  // namespace

int wmain(int argc, wchar_t** argv) {
    try {
        require(argc == 2, "Expected one isolated test root argument");
        const fs::path root = fs::path(argv[1]);
        require(!fs::exists(root), "Refusing to overwrite an existing test root");
        fs::create_directories(root);
        const fs::path live = root / "live";
        const fs::path stages = root / "stages";
        djbridge::SourceInfo source{"ci-synthetic-source", "Synthetic CI",
                                     "Disposable Publisher Test", "0.1.0-rc4"};

        const auto one = make_record(1, "Alpha");
        const auto two = make_record(2, "Beta");
        auto modified = one;
        modified.title = "Alpha (updated)";
        modified.metadata_vectors_json =
            djbridge::canonical_metadata_vectors_json({
                {"TITLE", {modified.title}},
                {"ARTIST", {"Synthetic Artist", ""}},
                {"MOOD", {"Synthetic", "CI"}}
            });
        modified.tag_fingerprint = djbridge::fingerprint_for(modified);
        require(one.tag_fingerprint != modified.tag_fingerprint,
                "Modified metadata must have a different fingerprint");

        {
            djbridge::Publisher producer;
            require(producer.configure(live, source), "Publisher not configured");
            producer.request({});
            capture(live, stages / "g1-empty", 1, 0);

            producer.request({two, one}); // Intentionally unsorted.
            capture(live, stages / "g2-add", 2, 2);

            producer.request({two, modified});
            capture(live, stages / "g3-edit", 3, 2);

            producer.request({modified});
            capture(live, stages / "g4-remove", 4, 1);

            // Burst of revisions: only the last requested generation should
            // be committed after the 750ms coalescing window.
            for (unsigned i = 0; i < 40; ++i) {
                producer.request({make_record(11, "Burst " + std::to_string(i))});
            }
            producer.request({modified, two, make_record(3, "Burst final")});
            capture(live, stages / "g5-coalesced", 5, 3);
            producer.shutdown();
        }
        {
            djbridge::Publisher restarted;
            require(restarted.configure(live, source), "Restart publisher failed");
            restarted.request({modified, two, make_record(3, "Burst final")});
            capture(live, stages / "g6-restart", 6, 3);

            restarted.request({});
            capture(live, stages / "g7-delete", 7, 0);

            std::vector<djbridge::Record> many;
            many.reserve(1024);
            for (unsigned i = 0; i < 1024; ++i) {
                many.push_back(make_record(i + 100, "Large payload " +
                    std::string(50, 'x') + std::to_string(i)));
            }
            restarted.request(std::move(many));
            capture(live, stages / "g8-many", 8, 1024);
            restarted.shutdown();
        }

        // Force a deterministic output failure by making the temporary gzip
        // *path* a directory. No real music, tags, or user-owned files exist.
        // The producer must fail closed with complete=0 and preserve the
        // previously committed gzip, even though the new generation fails.
        const auto blocker = live / "digital-items.tsv.gz.tmp";
        require(!fs::exists(blocker), "Unexpected temporary gzip path");
        fs::create_directory(blocker);
        {
            djbridge::Publisher failing;
            require(failing.configure(live, source), "Failure-test publisher unavailable");
            failing.request({make_record(9, "Blocked output")});
            const auto deadline = std::chrono::steady_clock::now() + 20s;
            for (;;) {
                const auto [marker, count] = read_state(live / "bridge-state.tsv");
                if (marker == "9:0" && count == "1" &&
                    fs::is_regular_file(live / "bridge-error.txt")) break;
                if (std::chrono::steady_clock::now() >= deadline) {
                    throw std::runtime_error("Publisher did not fail closed: " + marker);
                }
                std::this_thread::sleep_for(75ms);
            }
            const auto failedDir = stages / "g9-fail-closed";
            fs::create_directories(failedDir);
            fs::copy_file(live / "bridge-state.tsv",
                failedDir / "bridge-state.tsv", fs::copy_options::overwrite_existing);
            fs::copy_file(live / "digital-items.tsv.gz",
                failedDir / "digital-items.tsv.gz", fs::copy_options::overwrite_existing);
            fs::copy_file(live / "bridge-error.txt",
                failedDir / "bridge-error.txt", fs::copy_options::overwrite_existing);
            require(fs::file_size(failedDir / "digital-items.tsv.gz") ==
                    fs::file_size(stages / "g8-many" / "digital-items.tsv.gz"),
                    "Previous atomic gzip was unexpectedly changed");
            std::cout << "PUBLISHER_FAIL_CLOSED_GENERATION_9=PASS" << std::endl;
            failing.shutdown();
        }
        fs::remove(blocker);
        {
            djbridge::Publisher recovered;
            require(recovered.configure(live, source), "Recovery publisher unavailable");
            recovered.request({make_record(9, "Recovered after failure")});
            capture(live, stages / "g10-recovery", 10, 1);
            require(!fs::exists(live / "bridge-error.txt"),
                "Successful commit did not remove stale error state");
            recovered.shutdown();
        }
        std::cout << "PUBLISHER_FAILURE_RECOVERY=PASS" << std::endl;
        std::cout << "PUBLISHER_NATIVE_INTEGRATION=PASS" << std::endl;
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "PUBLISHER_NATIVE_INTEGRATION=FAIL " << e.what() << std::endl;
        return 1;
    }
}
