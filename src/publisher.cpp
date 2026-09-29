#include "publisher.h"
#include "gzip_stored.h"

#include <windows.h>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <fstream>
#include <stdexcept>

namespace djbridge {
namespace {

void flush_path(const std::filesystem::path& path) {
    HANDLE h = CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) throw std::runtime_error("cannot open temporary file for flush");
    const BOOL ok = FlushFileBuffers(h);
    CloseHandle(h);
    if (!ok) throw std::runtime_error("FlushFileBuffers failed");
}

void replace_atomic(const std::filesystem::path& from, const std::filesystem::path& to) {
    if (!MoveFileExW(from.c_str(), to.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        throw std::runtime_error("MoveFileExW atomic replace failed");
    }
}

std::string utc_now_iso8601() {
    SYSTEMTIME st{};
    GetSystemTime(&st);
    char buf[64]{};
    std::snprintf(buf, sizeof(buf), "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ",
        st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, st.wMilliseconds);
    return buf;
}

std::string state_value(std::string value) {
    for (char& c : value) {
        if (c == '\t' || c == '\r' || c == '\n' || c == '\0') c = ' ';
    }
    return value;
}

void write_state_file(const std::filesystem::path& path, std::uint64_t generation,
                      bool complete, std::size_t item_count, std::string_view utc,
                      const SourceInfo& source) {
    std::ofstream out(path, std::ios::binary | std::ios::trunc);
    if (!out) throw std::runtime_error("cannot create bridge-state temporary file");
    out << "schema_version\t1\n"
        << "generation\t" << generation << "\n"
        << "complete\t" << (complete ? 1 : 0) << "\n"
        << "item_count\t" << item_count << "\n"
        << "last_change_utc\t" << utc << "\n"
        << "source_id\t" << state_value(source.id) << "\n"
        << "source_name\t" << state_value(source.name) << "\n"
        << "profile_path\t" << state_value(source.profile_path) << "\n"
        << "producer_version\t" << state_value(source.producer_version) << "\n"
        << "producer_pid\t" << GetCurrentProcessId() << "\n";
    out.flush();
    if (!out) throw std::runtime_error("cannot flush bridge-state temporary file");
    out.close();
    flush_path(path);
}

} // namespace

Publisher::Publisher() = default;

Publisher::~Publisher() { shutdown(); }

bool Publisher::configure(std::filesystem::path directory, SourceInfo source) {
    if (enabled_) return directory_ == directory;
    try {
        directory_ = std::move(directory);
        source_ = std::move(source);
        std::error_code ec;
        std::filesystem::create_directories(directory_, ec);
        if (ec) throw std::runtime_error("cannot create bridge directory: " + ec.message());
        generation_ = load_previous_generation();
        stopping_ = false;
        dirty_ = false;
        initialization_error_.clear();
        enabled_ = true;
        worker_ = std::thread([this] { worker_loop(); });
        return true;
    } catch (const std::exception& ex) {
        enabled_ = false;
        initialization_error_ = ex.what();
        const std::string msg = std::string("[foo_dj_library_bridge] publisher initialization failed: ") + ex.what() + "\n";
        OutputDebugStringA(msg.c_str());
        return false;
    } catch (...) {
        enabled_ = false;
        initialization_error_ = "unknown publisher initialization failure";
        OutputDebugStringA("[foo_dj_library_bridge] publisher initialization failed with unknown exception\n");
        return false;
    }
}

void Publisher::request(std::vector<Record> snapshot) {
    if (!enabled_) return;
    {
        std::lock_guard lock(mutex_);
        pending_ = std::move(snapshot);
        ++revision_;
        dirty_ = true;
    }
    cv_.notify_one();
}

void Publisher::shutdown() {
    {
        std::lock_guard lock(mutex_);
        if (stopping_) return;
        stopping_ = true;
    }
    cv_.notify_one();
    if (worker_.joinable()) worker_.join();
    enabled_ = false;
}

void Publisher::worker_loop() {
    for (;;) {
        std::vector<Record> snapshot;
        std::uint64_t observed_revision = 0;
        {
            std::unique_lock lock(mutex_);
            cv_.wait(lock, [this] { return dirty_ || stopping_; });
            if (stopping_ && !dirty_) return;
            observed_revision = revision_;
            cv_.wait_for(lock, std::chrono::milliseconds(750), [this, observed_revision] {
                return stopping_ || revision_ != observed_revision;
            });
            if (!stopping_ && revision_ != observed_revision) continue;
            snapshot = pending_;
            dirty_ = false;
        }
        try {
            publish(snapshot);
        } catch (const std::exception& ex) {
            std::string msg = std::string("[foo_dj_library_bridge] publish failed: ") + ex.what() + "\n";
            OutputDebugStringA(msg.c_str());
            std::ofstream err(directory_ / L"bridge-error.txt", std::ios::binary | std::ios::trunc);
            err << msg;
        }
        std::lock_guard lock(mutex_);
        if (stopping_ && !dirty_) return;
    }
}

void Publisher::publish(const std::vector<Record>& input) {
    std::vector<Record> snapshot = input;
    std::sort(snapshot.begin(), snapshot.end(), [](const Record& a, const Record& b) {
        if (a.path != b.path) return a.path < b.path;
        return a.subsong < b.subsong;
    });

    const std::uint64_t next_generation = ++generation_;
    const std::string utc = utc_now_iso8601();
    const auto state_tmp = directory_ / L"bridge-state.tsv.tmp";
    const auto state_final = directory_ / L"bridge-state.tsv";
    const auto items_tmp = directory_ / L"digital-items.tsv.gz.tmp";
    const auto items_final = directory_ / L"digital-items.tsv.gz";

    write_state_file(state_tmp, next_generation, false, snapshot.size(), utc, source_);
    replace_atomic(state_tmp, state_final);

    {
        GzipStoredWriter gz(items_tmp);
        gz.write(kHeader);
        gz.write("\n");
        for (auto record : snapshot) {
            if (record.tag_fingerprint.empty()) record.tag_fingerprint = fingerprint_for(record);
            gz.write(to_tsv_line(record));
            gz.write("\n");
        }
        gz.finish();
    }
    flush_path(items_tmp);
    replace_atomic(items_tmp, items_final);

    write_state_file(state_tmp, next_generation, true, snapshot.size(), utc, source_);
    replace_atomic(state_tmp, state_final);

    std::error_code ec;
    std::filesystem::remove(directory_ / L"bridge-error.txt", ec);
}

std::uint64_t Publisher::load_previous_generation() const {
    std::ifstream in(directory_ / L"bridge-state.tsv", std::ios::binary);
    if (!in) return 0;
    std::string line;
    while (std::getline(in, line)) {
        constexpr std::string_view prefix = "generation\t";
        if (line.rfind(prefix.data(), 0) == 0) {
            try { return std::stoull(line.substr(prefix.size())); }
            catch (...) { return 0; }
        }
    }
    return 0;
}

} // namespace djbridge
