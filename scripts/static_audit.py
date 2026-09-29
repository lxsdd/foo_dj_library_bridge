#!/usr/bin/env python3
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
bridge = (root / "src" / "foobar_bridge.cpp").read_text(encoding="utf-8")
publisher = (root / "src" / "publisher.cpp").read_text(encoding="utf-8")
contract = (root / "src" / "bridge_contract.h").read_text(encoding="utf-8")
project = (root / "foo_dj_library_bridge.vcxproj").read_text(encoding="utf-8")
bootstrap = (root / "scripts" / "bootstrap-sdk.ps1").read_text(encoding="utf-8")
build = (root / "scripts" / "build.ps1").read_text(encoding="utf-8")

errors = []
def require(ok, message):
    if not ok: errors.append(message)

expected_header = "path\tsubsong\tartist\tartists\ttitle\toriginal_title\tremixed_by\talbum\talbum_artist\ttrack_number\ttotal_tracks\tdisc_number\ttotal_discs\tdate\tgenre\tstyle\tbpm\tlabel\tcatalog_number\tduration_seconds\tisrc\tcodec\tbitrate\ttag_fingerprint"
require(expected_header.replace("\t", "\\t") in contract, "schema-v1 header changed")
require('"0.1.0-dev"' in bridge, "component version is not 0.1.0-dev")
require('VALIDATE_COMPONENT_FILENAME("foo_dj_library_bridge.dll")' in bridge, "component filename validation missing")
require('library_manager::get()->get_all_items(items)' in bridge, "full Media Library enumeration missing")
for callback in ["on_items_added", "on_items_removed", "on_items_modified", "on_items_modified_v2", "on_library_initialized"]:
    require(callback in bridge, f"missing library callback: {callback}")
require('library_callback::is_modified_from_hook()' in bridge, "display-hook modification guard missing")
require('get_info_ref()' in bridge, "cached metadata read path missing")
require('get_full_info_ref' not in bridge, "component must not force-read media files")
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

require('L"DJLibrary" / L"bridge"' in publisher, "bridge output directory changed")
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
print("- exact schema-v1 contract")
print("- C++20 / target v81 / VS2022 v143 build path")
print("- atomic complete=0 -> payload -> complete=1 publication")
