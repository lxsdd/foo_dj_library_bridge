#include "gzip_stored.h"

#include <array>
#include <stdexcept>

namespace djbridge {
namespace {

std::uint32_t crc32_step(std::uint32_t crc, std::uint8_t byte) {
    crc ^= byte;
    for (int i = 0; i < 8; ++i) {
        const std::uint32_t mask = 0u - (crc & 1u);
        crc = (crc >> 1u) ^ (0xEDB88320u & mask);
    }
    return crc;
}

} // namespace

GzipStoredWriter::GzipStoredWriter(const std::filesystem::path& path)
    : out_(path, std::ios::binary | std::ios::trunc) {
    if (!out_) throw std::runtime_error("cannot create gzip output");
    static constexpr std::array<std::uint8_t, 10> header = {
        0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF
    };
    out_.write(reinterpret_cast<const char*>(header.data()), static_cast<std::streamsize>(header.size()));
    buffer_.reserve(65535);
}

GzipStoredWriter::~GzipStoredWriter() {
    try { if (!finished_) finish(); } catch (...) {}
}

void GzipStoredWriter::write(std::string_view bytes) {
    if (finished_) throw std::logic_error("gzip writer already finished");
    const auto* p = reinterpret_cast<const std::uint8_t*>(bytes.data());
    update_crc(p, bytes.size());
    size_mod32_ += static_cast<std::uint32_t>(bytes.size());

    std::size_t offset = 0;
    while (offset < bytes.size()) {
        const std::size_t room = 65535u - buffer_.size();
        const std::size_t take = (bytes.size() - offset < room) ? (bytes.size() - offset) : room;
        buffer_.insert(buffer_.end(), p + offset, p + offset + take);
        offset += take;
        if (buffer_.size() == 65535u) {
            emit_block(false, buffer_.data(), buffer_.size());
            buffer_.clear();
        }
    }
}

void GzipStoredWriter::finish() {
    if (finished_) return;
    emit_block(true, buffer_.data(), buffer_.size());
    buffer_.clear();
    write_u32(crc_ ^ 0xFFFFFFFFu);
    write_u32(size_mod32_);
    out_.flush();
    if (!out_) throw std::runtime_error("failed to flush gzip output");
    out_.close();
    finished_ = true;
}

void GzipStoredWriter::emit_block(bool final_block, const std::uint8_t* data, std::size_t size) {
    if (size > 65535u) throw std::logic_error("stored deflate block too large");
    const std::uint8_t header = final_block ? 0x01u : 0x00u;
    out_.put(static_cast<char>(header));
    write_u16(static_cast<std::uint16_t>(size));
    write_u16(static_cast<std::uint16_t>(~static_cast<std::uint16_t>(size)));
    if (size) out_.write(reinterpret_cast<const char*>(data), static_cast<std::streamsize>(size));
    if (!out_) throw std::runtime_error("failed to write gzip block");
}

void GzipStoredWriter::update_crc(const std::uint8_t* data, std::size_t size) {
    for (std::size_t i = 0; i < size; ++i) crc_ = crc32_step(crc_, data[i]);
}

void GzipStoredWriter::write_u16(std::uint16_t value) {
    out_.put(static_cast<char>(value & 0xFFu));
    out_.put(static_cast<char>((value >> 8u) & 0xFFu));
}

void GzipStoredWriter::write_u32(std::uint32_t value) {
    for (int shift = 0; shift < 32; shift += 8) out_.put(static_cast<char>((value >> shift) & 0xFFu));
}

} // namespace djbridge
