#include "../src/publisher.h"
#include "../src/bridge_contract.h"

#include <windows.h>
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <iterator>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
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
        if (argc == 3 && std::wstring_view(argv[1]) == L"--crash-child") {
            const fs::path directory = fs::path(argv[2]);
            require(fs::is_directory(directory),
                    "Crash child may only target its pre-created synthetic directory");
            require(_wputenv_s(L"DJBRIDGE_CI_CRASH_PROBE", L"1") == 0,
                    "Could not enable test-only process pause");
            djbridge::SourceInfo childSource{
                "ci-synthetic-source", "Synthetic CI",
                "Disposable Publisher Test", "0.1.0-rc4"};
            djbridge::Publisher child;
            require(child.configure(directory, childSource), "Crash child unavailable");
            child.request({make_record(990, "Interrupted by host process kill")});
            std::this_thread::sleep_for(40s);
            child.shutdown();
            throw std::runtime_error("Crash child unexpectedly survived process-kill test");
        }
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

            // Scale evidence for a realistically sized foobar profile.
            // Paths and tags are invented and never resolved on disk.
            std::vector<djbridge::Record> largeSnapshot;
            largeSnapshot.reserve(54129);
            for (unsigned id = 0; id < 54129; ++id) {
                largeSnapshot.push_back(make_record(
                    id + 10000, "Synthetic library track " + std::to_string(id)));
            }
            const auto scaleStart = std::chrono::steady_clock::now();
            recovered.request(std::move(largeSnapshot));
            capture(live, stages / "g11-large", 11, 54129);
            const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::steady_clock::now() - scaleStart).count();
            std::cout << "PUBLISHER_NATIVE_SCALE_54129=PASS elapsed_ms="
                      << elapsed << std::endl;
            recovered.shutdown();
        }
        // OrdinalIgnoreCase is part of both production C# consumers' identity
        // contract. Two CUE subsongs of the same path are valid, but two
        // byte-distinct case variants with the same subsong are not.
        // Everything remains under the disposable test root.
        {
            const auto ambiguousDir = root / "case-identity";
            djbridge::Record base = make_record(66, "CUE subsong A");
            base.path = "C:\\SyntheticCI\\CaseTrack.FLAC";
            base.subsong = 0;
            base.tag_fingerprint = djbridge::fingerprint_for(base);
            auto differentSubsong = base;
            differentSubsong.subsong = 1;
            differentSubsong.title = "CUE subsong B";
            differentSubsong.metadata_vectors_json =
                djbridge::canonical_metadata_vectors_json({
                    {"TITLE", {differentSubsong.title}},
                    {"ARTIST", {"Synthetic Artist", ""}},
                    {"MOOD", {"Synthetic", "CI"}}
                });
            differentSubsong.tag_fingerprint = djbridge::fingerprint_for(differentSubsong);
            auto duplicate = base;
            duplicate.path = "c:\\syntheticci\\casetrack.flac";
            duplicate.tag_fingerprint = djbridge::fingerprint_for(duplicate);
            djbridge::Publisher guarded;
            require(guarded.configure(ambiguousDir, source), "Identity test publisher unavailable");
            guarded.request({base, differentSubsong});
            capture(ambiguousDir, stages / "identity-valid-subsongs", 1, 2);
            const auto oldGzipBytes = fs::file_size(ambiguousDir / "digital-items.tsv.gz");
            guarded.request({base, duplicate});
            const auto deadline = std::chrono::steady_clock::now() + 20s;
            for (;;) {
                const auto [marker, count] = read_state(ambiguousDir / "bridge-state.tsv");
                if (marker == "2:0" && count == "2" &&
                    fs::is_regular_file(ambiguousDir / "bridge-error.txt")) break;
                if (std::chrono::steady_clock::now() >= deadline) {
                    throw std::runtime_error("Case-insensitive duplicate was not rejected");
                }
                std::this_thread::sleep_for(75ms);
            }
            require(fs::file_size(ambiguousDir / "digital-items.tsv.gz") == oldGzipBytes,
                    "Duplicate identity overwrote last good gzip");
            std::cout << "PUBLISHER_CASE_COLLISION_FAIL_CLOSED=PASS" << std::endl;
            guarded.request({base, differentSubsong});
            capture(ambiguousDir, stages / "identity-recovered-subsongs", 3, 2);
            require(!fs::exists(ambiguousDir / "bridge-error.txt"),
                    "Successful identity recovery did not clear error marker");
            guarded.shutdown();
            std::cout << "PUBLISHER_CASE_COLLISION_RECOVERY=PASS" << std::endl;
        }
        // End-to-end HARD PROCESS KILL (not merely a simulated error):
        // Start a second process using only invented music paths and test root.
        // Compile-time guard pauses it after its complete=0 state is *really*
        // atomically committed. Kill it without running Publisher::shutdown,
        // then confirm a second publisher process can recover the generation.
        {
            const fs::path crashDir = root / "crash-host";
            fs::create_directories(crashDir);
            const auto baseline = make_record(990, "Before host process crash");
            {
                djbridge::Publisher initial;
                require(initial.configure(crashDir, source), "Crash baseline publisher unavailable");
                initial.request({baseline});
                capture(crashDir, stages / "crash-baseline", 1, 1);
                initial.shutdown();
            }
            const fs::path crashPayload = crashDir / "digital-items.tsv.gz";
            std::ifstream oldStream(crashPayload, std::ios::binary);
            require(static_cast<bool>(oldStream), "Cannot read synthetic baseline gzip");
            const std::string oldBytes((std::istreambuf_iterator<char>(oldStream)),
                                        std::istreambuf_iterator<char>());
            // Windows CRT readers may deny FILE_SHARE_DELETE. Closing before
            // recovery is essential: a test-held handle is not a producer bug.
            oldStream.close();
            wchar_t modulePath[32768]{};
            const DWORD moduleLength = GetModuleFileNameW(
                nullptr, modulePath, static_cast<DWORD>(std::size(modulePath)));
            require(moduleLength > 0 && moduleLength < std::size(modulePath),
                    "Cannot resolve test executable path");
            std::wstring command = L"\"" + std::wstring(modulePath) +
                                   L"\" --crash-child \"" + crashDir.wstring() + L"\"";
            STARTUPINFOW si{};
            si.cb = sizeof(si);
            PROCESS_INFORMATION pi{};
            require(CreateProcessW(modulePath, command.data(), nullptr, nullptr,
                                   FALSE, CREATE_NO_WINDOW, nullptr, nullptr,
                                   &si, &pi) != 0, "Could not create disposable crash-child process");
            CloseHandle(pi.hThread);
            bool markerSeen = false;
            try {
                const auto deadline = std::chrono::steady_clock::now() + 15s;
                while (std::chrono::steady_clock::now() < deadline) {
                    const auto [marker, count] = read_state(crashDir / "bridge-state.tsv");
                    if (marker == "2:0" && count == "1") {
                        markerSeen = true;
                        break;
                    }
                    if (WaitForSingleObject(pi.hProcess, 0) != WAIT_TIMEOUT) break;
                    std::this_thread::sleep_for(15ms);
                }
                require(markerSeen, "Child never committed its incomplete generation");
                require(WaitForSingleObject(pi.hProcess, 0) == WAIT_TIMEOUT,
                        "Crash child exited before forceful termination");
                require(TerminateProcess(pi.hProcess, 73) != 0,
                        "Could not terminate crash child without shutdown");
                require(WaitForSingleObject(pi.hProcess, 5000) == WAIT_OBJECT_0,
                        "Crash child did not terminate in five seconds");
            } catch (...) {
                if (WaitForSingleObject(pi.hProcess, 0) == WAIT_TIMEOUT) {
                    TerminateProcess(pi.hProcess, 73);
                    WaitForSingleObject(pi.hProcess, 5000);
                }
                CloseHandle(pi.hProcess);
                throw;
            }
            CloseHandle(pi.hProcess);
            require(read_state(crashDir / "bridge-state.tsv").first == "2:0",
                    "Hard kill left an unexpectedly complete generation");
            std::ifstream afterStream(crashPayload, std::ios::binary);
            const std::string afterBytes((std::istreambuf_iterator<char>(afterStream)),
                                          std::istreambuf_iterator<char>());
            afterStream.close();
            require(afterBytes == oldBytes, "Hard kill changed previous committed gzip bytes");
            const auto incompleteDir = stages / "crash-incomplete";
            fs::create_directories(incompleteDir);
            fs::copy_file(crashDir / "bridge-state.tsv",
                          incompleteDir / "bridge-state.tsv");
            fs::copy_file(crashPayload, incompleteDir / "digital-items.tsv.gz");
            std::cout << "PUBLISHER_ACTUAL_PROCESS_KILL_FAIL_CLOSED=PASS" << std::endl;
            {
                djbridge::Publisher recovered;
                require(recovered.configure(crashDir, source),
                        "Publisher could not initialize after abrupt process death");
                recovered.request({make_record(990, "After real host process crash")});
                capture(crashDir, stages / "crash-recovered", 3, 1);
                recovered.shutdown();
            }
            std::cout << "PUBLISHER_ACTUAL_PROCESS_KILL_RECOVERY=PASS" << std::endl;
        }
        std::cout << "PUBLISHER_FAILURE_RECOVERY=PASS" << std::endl;
        std::cout << "PUBLISHER_NATIVE_INTEGRATION=PASS" << std::endl;
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "PUBLISHER_NATIVE_INTEGRATION=FAIL " << e.what() << std::endl;
        return 1;
    }
}
