#pragma once

#include "bridge_contract.h"

#include <condition_variable>
#include <filesystem>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace djbridge {

class Publisher {
public:
    Publisher();
    ~Publisher();

    Publisher(const Publisher&) = delete;
    Publisher& operator=(const Publisher&) = delete;

    void request(std::vector<Record> snapshot);
    void shutdown();

    bool available() const noexcept { return enabled_; }
    const std::string& initialization_error() const noexcept { return initialization_error_; }

    static std::filesystem::path default_directory();

private:
    void worker_loop();
    void publish(const std::vector<Record>& snapshot);
    std::uint64_t load_previous_generation() const;

    std::filesystem::path directory_;
    std::mutex mutex_;
    std::condition_variable cv_;
    std::thread worker_;
    std::vector<Record> pending_;
    std::uint64_t revision_ = 0;
    bool dirty_ = false;
    bool stopping_ = false;
    bool enabled_ = false;
    std::uint64_t generation_ = 0;
    std::string initialization_error_;
};

} // namespace djbridge
