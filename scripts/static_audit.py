#!/usr/bin/env python3
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
bridge = (root / "src" / "foobar_bridge.cpp").read_text(encoding="utf-8")
publisher = (root / "src" / "publisher.cpp").read_text(encoding="utf-8")
contract = (root / "src" / "bridge_contract.h").read_text(encoding="utf-8")
contract_cpp = (root / "src" / "bridge_contract.cpp").read_text(encoding="utf-8")
project = (root / "foo_dj_library_bridge.vcxproj").read_text(encoding="utf-8")
bootstrap = (root / "scripts" / "bootstrap-sdk.ps1").read_text(encoding="utf-8")
build = (root / "scripts" / "build.ps1").read_text(encoding="utf-8")

errors = []
def require(ok, message):
    if not ok: errors.append(message)

expected_header = "path\tsubsong\tartist\tartists\ttitle\toriginal_title\tremixed_by\talbum\talbum_artist\ttrack_number\ttotal_tracks\tdisc_number\ttotal_discs\tdate\tgenre\tstyle\tbpm\tlabel\tcatalog_number\tduration_seconds\tisrc\tcodec\tbitrate\ttag_fingerprint\textra_metadata_json\tmetadata_vectors_json"
require(expected_header.replace("\t", "\\t") in contract, "schema-v3 header changed")
require('kSchemaVersion = 3' in contract, "schema version is not 3")
require('"0.1.0-rc4"' in bridge, "component version is not 0.1.0-rc4")
require('VALIDATE_COMPONENT_FILENAME("foo_dj_library_bridge.dll")' in bridge, "component filename validation missing")
require('library_manager::get()->get_all_items(items)' in bridge, "full Media Library enumeration missing")
for callback in ["on_items_added", "on_items_removed", "on_items_modified", "on_items_modified_v2", "on_library_initialized"]:
    require(callback in bridge, f"missing library callback: {callback}")
require('library_callback::is_modified_from_hook()' in bridge, "display-hook modification guard missing")
require('get_info_ref()' in bridge, "cached metadata read path missing")
require('get_full_info_ref' not in bridge, "component must not force-read media files")
require('meta_enum_name' in bridge and 'meta_enum_value_count' in bridge and 'meta_enum_value' in bridge, "generic metadata enumeration missing")
require('canonical_extra_metadata_json' in bridge, "generic metadata serialization missing")
require('extra_metadata_json' in contract and 'extra_metadata_json' in contract_cpp, "schema-v3 extra metadata field missing")
require('metadata_vectors_json' in contract and 'metadata_vectors_json' in contract_cpp, "schema-v3 metadata vectors field missing")
require('canonical_metadata_vectors_json' in bridge, "lossless metadata vector serialization missing")
require('core_api::get_profile_path()' in bridge, "foobar profile path API is not used")
require('g_get_native_path(core_api::get_profile_path()' in bridge, "profile path is not converted through the SDK filesystem helper")
require('L"foo_dj_library_bridge"' in bridge, "profile-local component data directory missing")
require('LOCALAPPDATA' not in bridge and 'LOCALAPPDATA' not in publisher, "global LOCALAPPDATA bridge storage must not be used")
for key in ["source_id", "source_name", "profile_path", "producer_version", "producer_pid"]:
    require(f'"{key}\\t"' in publisher, f"state metadata missing: {key}")
require('"schema_version\\t" << kSchemaVersion' in publisher, "state schema version must follow contract schema")
require('FOOBAR2000_TARGET_VERSION=81' in project, "foobar target version 81 missing")
require('<LanguageStandard>stdcpp20</LanguageStandard>' in project, "C++20 missing")
require('MultiThreadedDLL' in project and 'MultiThreadedDebugDLL' in project, "component runtime library is not aligned with official component sample")
require('foobar2000_sdk_helpers.vcxproj' not in project, "unused helpers project reference should not be linked")
require("$SdkVersion = '2026-09-17'" in bootstrap, "SDK pin changed")
require("[string]$PlatformToolset = 'v143'" in build, "VS2022 v143 CI toolset pin missing")
require('GENERIC_WRITE' in publisher and 'FlushFileBuffers' in publisher, "durable temp-file flush must use a writable handle")
require('MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH' in publisher, "atomic write-through replace missing")
require('complete ? 1 : 0' in publisher, "state complete marker missing")
require('write_state_file(state_tmp, next_generation, false' in publisher, "complete=0 safety marker must be published first")
require('write_state_file(state_tmp, next_generation, true' in publisher, "complete=1 commit marker missing")
require('std::locale::classic()' in bridge, "duration formatting must be locale-invariant")
require('std::isfinite(seconds)' in bridge, "duration must reject non-finite values")

banned = [
    r'update_info', r'tag_processor', r'metadb_io[^\n;]*update',
    r'g_open_write', r'open_write', r'file_info_filter', r'add_items_async',
    r'foobar2000-v2\\.*database', r'library-v2\\.*database'
]
for pattern in banned:
    if re.search(pattern, bridge, re.IGNORECASE):
        errors.append(f"forbidden write/private-DB API pattern in foobar adapter: {pattern}")

require('std::ofstream' not in bridge, "foobar callback adapter must not write files directly")

try:
    ET.fromstring(project)
except Exception as e:
    errors.append(f"vcxproj XML invalid: {e}")

if errors:
    print("STATIC AUDIT FAIL")
    for e in errors: print("-", e)
    sys.exit(1)
print("STATIC AUDIT PASS")
print("- read-only foobar SDK adapter")
print("- profile-local per-instance storage via core_api::get_profile_path()")
print("- source metadata in schema-v3 state")
print("- schema-v3 payload preserves schema-v2 prefix and appends exact metadata vectors")
print("- arbitrary metadata enumeration without core-field duplication")
print("- C++20 / target v81 / VS2022 v143 build path")
print("- atomic complete=0 -> payload -> complete=1 publication")
