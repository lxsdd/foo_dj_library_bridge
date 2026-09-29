#pragma once

#include <cstdint>
#include <filesystem>
#include <fstream>
#include <string_view>
#include <vector>

namespace djbridge {

// Dependency-free gzip writer using DEFLATE stored blocks (BTYPE=00).
// Output is standard RFC 1952 gzip; it is intentionally uncompressed to keep
// the foobar component dependency-free and deterministic.
class GzipStoredWriter {
public:
    explicit GzipStoredWriter(const std::filesystem::path& path);
    ~GzipStoredWriter();

    GzipStoredWriter(const GzipStoredWriter&) = delete;
    GzipStoredWriter& operator=(const GzipStoredWriter&) = delete;

    void write(std::string_view bytes);
    void finish();

private:
    void emit_block(bool final_block, const std::uint8_t* data, std::size_t size);
    void update_crc(const std::uint8_t* data, std::size_t size);
    void write_u16(std::uint16_t value);
    void write_u32(std::uint32_t value);

    std::ofstream out_;
    std::vector<std::uint8_t> buffer_;
    std::uint32_t crc_ = 0xFFFFFFFFu;
    std::uint32_t size_mod32_ = 0;
    bool finished_ = false;
};

} // namespace djbridge
