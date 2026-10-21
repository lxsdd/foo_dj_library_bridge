#!/usr/bin/env python3
from pathlib import Path
import hashlib
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

# Licensing is an owner-approved restricted combined grant. A stale or
# MIT-only LICENSE would silently restore resale rights, so treat changes
# as a legal review gate separate from the build/distribution hold.
license_bytes = (root / "LICENSE").read_bytes()
license_text = license_bytes.decode("utf-8", errors="strict")
normalized_license = " ".join(license_text.split())
license_blob = hashlib.sha1(
    f"blob {len(license_bytes)}\0".encode("ascii") + license_bytes
).hexdigest()
require(
    license_blob == "b9998241259c5cc30a512ae25257409c48319f9a",
    "owner-approved MIT plus Commons Clause LICENSE changed: re-review full legal grant",
)
for required in (
    "Copyright (c) 2026 lxsdd",
    '"Commons Clause" License Condition v1.0',
    "the right to Sell the Software",
    "Software: foo_dj_library_bridge",
    "License: MIT",
    "Licensor: lxsdd",
    "Independently licensed third-party",
):
    require(required in normalized_license, f"mandatory restricted-license term absent: {required}")

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
require("$SdkVersion = '2026-10-01'" in bootstrap, "SDK must use currently approved 2026-10-01")
require("$TemplateCommit = '31a35947a7527826c2199491692802e3ce3d8bd7'" in bootstrap, "Immutable SDK source commit missing")
require("$SdkTree = '2ba8caeb73f72633ad7f60ee5f72ed8074a0eb17'" in bootstrap, "Immutable SDK source tree missing")
require("$ExpectedArchiveHash = 'd4c55077336fae81bf8df0259b5b2748fa45ea84132c656ead93eb123cbcdc26'" in bootstrap,
        "SDK upstream archive evidence pin missing")
require("Invoke-WebRequest" not in bootstrap and "foobar2000_component_template.git" in bootstrap,
        "Bridge SDK bootstrap must use the pinned owner-controlled Git source, not vendor archive HTTP")
require("[ValidateSet('v143','v145')] [string]$PlatformToolset = 'v143'" in build,
        "v143 default with explicit reviewed v145 toolset option missing")
local_build = (root / "scripts" / "local-acceptance-build.ps1").read_text(encoding="utf-8")
workflow_source = (root / ".github" / "workflows" / "build.yml").read_text(encoding="utf-8")
require("[ValidateSet('Auto','v143','v145')]" in local_build,
        "private SHA-pinned build must accept only vetted toolsets")
require("if ($hasV143) { 'v143' } else { 'v145' }" in local_build,
        "private build toolset-selection fail-safe missing")
require("MSVC C++ $selectedToolset x86/x64" in local_build,
        "per-architecture compiler presence requirement removed")
require("-PlatformToolset $selectedToolset" in local_build,
        "private dual-architecture compile does not enforce selected toolset")
require("toolset: [v143, v145]" in workflow_source,
        "Win32/x64 host CI must independently qualify both reviewed toolsets")
require("-Toolset '${{ matrix.toolset }}'" in workflow_source and
        "-PlatformToolset '${{ matrix.toolset }}'" in workflow_source and
        "/p:PlatformToolset='${{ matrix.toolset }}'" in workflow_source,
        "host builds, publisher and exact SHA acceptance must use same selected toolset")
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
print("- owner-approved lxsdd MIT + Commons Clause v1.0 license exact Git-blob allowlist")
print("- read-only foobar SDK adapter")
print("- profile-local per-instance storage via core_api::get_profile_path()")
print("- source metadata in schema-v3 state")
print("- schema-v3 payload preserves schema-v2 prefix and appends exact metadata vectors")
print("- arbitrary metadata enumeration without core-field duplication")
print("- C++20 / target v81 / independently gated VS2022 v143 and VS2026 v145 host build paths")
print("- atomic complete=0 -> payload -> complete=1 publication")
