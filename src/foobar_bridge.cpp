#include <foobar2000/SDK/foobar2000.h>

#include "bridge_contract.h"
#include "publisher.h"

#include <algorithm>
#include <cmath>
#include <exception>
#include <iomanip>
#include <initializer_list>
#include <locale>
#include <map>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

DECLARE_COMPONENT_VERSION(
    "DJ Library Bridge",
    "0.1.0-rc1",
    "Read-only Media Library bridge for DJ Library.\n"
    "Exports an atomic snapshot to %LOCALAPPDATA%\\DJLibrary\\bridge.\n"
    "Does not modify audio files, tags, or foobar2000 private databases."
);
VALIDATE_COMPONENT_FILENAME("foo_dj_library_bridge.dll");

namespace {

std::string meta_join(const file_info& info, const char* name, const char* separator = "; ") {
    const t_size count = info.meta_get_count_by_name(name);
    std::string out;
    for (t_size i = 0; i < count; ++i) {
        const char* value = info.meta_get(name, i);
        if (!value || !*value) continue;
        if (!out.empty()) out += separator;
        out += value;
    }
    return out;
}

std::string meta_first_of(const file_info& info, std::initializer_list<const char*> names) {
    for (const char* name : names) {
        auto value = meta_join(info, name);
        if (!value.empty()) return value;
    }
    return {};
}

std::string info_first_of(const file_info& info, std::initializer_list<const char*> names) {
    for (const char* name : names) {
        const char* value = info.info_get(name);
        if (value && *value) return value;
    }
    return {};
}

std::string format_duration(double seconds) {
    if (!(seconds > 0.0) || !std::isfinite(seconds)) return {};
    std::ostringstream out;
    out.imbue(std::locale::classic());
    out << std::fixed << std::setprecision(6) << seconds;
    std::string s = out.str();
    while (!s.empty() && s.back() == '0') s.pop_back();
    if (!s.empty() && s.back() == '.') s.pop_back();
    return s;
}

djbridge::Record make_record(const metadb_handle_ptr& handle) {
    djbridge::Record r;
    r.path = handle->get_path();
    r.subsong = handle->get_subsong_index();

    const auto container = handle->get_info_ref();
    const file_info& info = container->info();
    r.artist = meta_join(info, "ARTIST");
    r.artists = meta_join(info, "ARTISTS");
    r.title = meta_join(info, "TITLE");
    r.original_title = meta_join(info, "ORIGINAL TITLE");
    r.remixed_by = meta_join(info, "REMIXED BY");
    r.album = meta_join(info, "ALBUM");
    r.album_artist = meta_join(info, "ALBUM ARTIST");
    r.track_number = meta_first_of(info, {"TRACKNUMBER", "TRACK"});
    r.total_tracks = meta_first_of(info, {"TOTALTRACKS", "TRACKTOTAL"});
    r.disc_number = meta_first_of(info, {"DISCNUMBER", "DISC"});
    r.total_discs = meta_first_of(info, {"TOTALDISCS", "DISCTOTAL"});
    r.date = meta_first_of(info, {"DATE", "YEAR"});
    r.genre = meta_join(info, "GENRE");
    r.style = meta_join(info, "STYLE");
    r.bpm = meta_join(info, "BPM");
    r.label = meta_first_of(info, {"LABEL", "PUBLISHER"});
    r.catalog_number = meta_first_of(info, {"CATALOGNUMBER", "CATALOG NUMBER", "CATALOG"});
    r.duration_seconds = format_duration(info.get_length());
    r.isrc = meta_join(info, "ISRC");
    r.codec = info_first_of(info, {"codec", "codec_profile"});
    r.bitrate = info_first_of(info, {"bitrate", "bitrate_dynamic"});
    r.tag_fingerprint = djbridge::fingerprint_for(r);
    return r;
}

class BridgeCallback : public library_callback_v2 {
public:
    void on_items_added(metadb_handle_list_cref items) override {
        if (!initialized_) return;
        try { upsert(items); publish(); }
        catch (const std::exception& e) { log_exception("on_items_added", e); }
        catch (...) { console::print("[foo_dj_library_bridge] on_items_added failed with unknown exception"); }
    }

    void on_items_removed(metadb_handle_list_cref items) override {
        if (!initialized_) return;
        try {
            for (t_size i = 0; i < items.get_count(); ++i) {
                const auto& h = items[i];
                records_.erase(djbridge::identity_key(h->get_path(), h->get_subsong_index()));
            }
            publish();
        } catch (const std::exception& e) { log_exception("on_items_removed", e); }
        catch (...) { console::print("[foo_dj_library_bridge] on_items_removed failed with unknown exception"); }
    }

    void on_items_modified(metadb_handle_list_cref items) override {
        if (!initialized_ || library_callback::is_modified_from_hook()) return;
        try { upsert(items); publish(); }
        catch (const std::exception& e) { log_exception("on_items_modified", e); }
        catch (...) { console::print("[foo_dj_library_bridge] on_items_modified failed with unknown exception"); }
    }

    void on_items_modified_v2(metadb_handle_list_cref items, metadb_io_callback_v2_data&) override {
        if (!initialized_ || library_callback::is_modified_from_hook()) return;
        try { upsert(items); publish(); }
        catch (const std::exception& e) { log_exception("on_items_modified_v2", e); }
        catch (...) { console::print("[foo_dj_library_bridge] on_items_modified_v2 failed with unknown exception"); }
    }

    void on_library_initialized() override {
        try {
            metadb_handle_list items;
            library_manager::get()->get_all_items(items);
            records_.clear();
            for (t_size i = 0; i < items.get_count(); ++i) {
                auto r = make_record(items[i]);
                records_[djbridge::identity_key(r.path, r.subsong)] = std::move(r);
            }
            initialized_ = true;
            if (!publisher_.available()) {
                pfc::string_formatter msg;
                msg << "[foo_dj_library_bridge] publisher unavailable: " << publisher_.initialization_error().c_str();
                console::print(msg.c_str());
                return;
            }
            publish();
            pfc::string_formatter msg;
            msg << "[foo_dj_library_bridge] initialized: " << static_cast<t_uint64>(records_.size()) << " Media Library items queued for publication";
            console::print(msg.c_str());
        } catch (const std::exception& e) { log_exception("on_library_initialized", e); }
        catch (...) { console::print("[foo_dj_library_bridge] library initialization failed with unknown exception"); }
    }

private:
    void upsert(metadb_handle_list_cref items) {
        for (t_size i = 0; i < items.get_count(); ++i) {
            auto r = make_record(items[i]);
            records_[djbridge::identity_key(r.path, r.subsong)] = std::move(r);
        }
    }

    void publish() {
        std::vector<djbridge::Record> snapshot;
        snapshot.reserve(records_.size());
        for (const auto& [_, record] : records_) snapshot.push_back(record);
        publisher_.request(std::move(snapshot));
    }

    static void log_exception(const char* where, const std::exception& e) {
        pfc::string_formatter msg;
        msg << "[foo_dj_library_bridge] " << where << " failed: " << e.what();
        console::print(msg.c_str());
    }

    bool initialized_ = false;
    std::map<std::string, djbridge::Record> records_;
    djbridge::Publisher publisher_;
};

library_callback_factory_t<BridgeCallback> g_bridge_callback_factory;

} // namespace
