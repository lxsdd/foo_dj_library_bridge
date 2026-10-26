#!/usr/bin/env python3
"""Reject accidental re-enabling of public GitHub binary artifacts."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
config = {
    "music-metadata-studio": {
        "workflow": root / ".github/workflows/foobar.yml",
        "steps": ("Upload DLL", "Upload combined component"),
        "jobs": ("package",),
        "uploads": 2,
    },
    "foo_dj_library_bridge": {
        "workflow": root / ".github/workflows/build.yml",
        "steps": ("Upload DLL", "Upload qualified component candidate"),
        "jobs": ("package-component",),
        "uploads": 2,
    },
}
# Project identity is detected using the source tree, not external arguments.
key = "foo_dj_library_bridge" if (root / "foo_dj_library_bridge.sln").exists() else "music-metadata-studio"
entry = config[key]
source = entry["workflow"].read_text(encoding="utf-8")
lines = source.splitlines()
errors = []

def gated_line(label):
    found = [i for i, line in enumerate(lines) if line.strip() == label]
    if len(found) != 1:
        errors.append(f"{label!r}: expected one definition, found {len(found)}")
        return
    block = lines[found[0] + 1 : found[0] + 7]
    if not any(line.strip().startswith("if: false") for line in block):
        errors.append(f"{label!r}: no explicit 'if: false' gate")

for step in entry["steps"]:
    gated_line("- name: " + step)
for job in entry["jobs"]:
    gated_line(job + ":")
if source.count("uses: actions/upload-artifact@") != entry["uploads"]:
    errors.append("new/removed artifact upload action; manual review required")
if key == "foo_dj_library_bridge":
    release = (root / ".github/workflows/release-qualified.yml").read_text(encoding="utf-8").splitlines()
    positions = [i for i, line in enumerate(release) if line == "  release:"]
    if len(positions) != 1 or not any(
        line.strip().startswith("if: false")
        for line in release[positions[0]+1:positions[0]+6]
    ):
        errors.append("manual release job is not disabled")

if errors:
    sys.exit("FAIL: public binary distribution gate:\n- " + "\n- ".join(errors))
print("PASS: public uploads and release jobs disabled; build/tests remain enabled")


# Common source-pinned publication scanner; retain the product-specific
# disabled-step checks above and immutable workflow Git-blob pins below.
# Fail locally on shared implementation or provenance drift. The reviewed owner
# Git blob is immutable; this check runs during each product's normal CI.
import hashlib as _shared_hashlib
import json as _shared_json
_SHARED_EXPECTED_BLOB = "2de36b9f8ff429aca93841907f9106f11ebe9886"
# Normalize only checkout CRLF to Git-canonical LF (Windows core.autocrlf).
_SHARED_CONTENT = (root / "scripts/_shared_publication_guard.py").read_bytes().replace(b"\r\n", b"\n")
_SHARED_PREFIX = ("blob " + str(len(_SHARED_CONTENT)) + "\0").encode("ascii")
_SHARED_ACTUAL_BLOB = _shared_hashlib.sha1(
    _SHARED_PREFIX + _SHARED_CONTENT
).hexdigest()
_SHARED_PIN = _shared_json.loads(
    (root / "scripts/SHARED_PUBLICATION_GUARD.pin.json").read_text(encoding="utf-8")
)
if (_SHARED_ACTUAL_BLOB != _SHARED_EXPECTED_BLOB or
        _SHARED_PIN.get("source_git_blob_sha1") != _SHARED_EXPECTED_BLOB):
    sys.exit("FAIL: local shared publication guard or immutable provenance pin drift")

from _shared_publication_guard import scan_workflows as _scan_publication_surface

_D_EXPECTED = {"build.yml": 2}
_D_DIR = Path(__file__).resolve().parents[1] / ".github/workflows"
_D_FILES = {p.name: p.read_text(encoding="utf-8") for p in _D_DIR.iterdir()
            if p.suffix.lower() in (".yml", ".yaml")}
_D_ERRORS = _scan_publication_surface(
    _D_FILES, _D_EXPECTED,
    required_disabled_steps={
        "build.yml": ["Upload DLL", "Upload qualified component candidate"]},
    required_disabled_jobs={
        "build.yml": ["package-component"],
        "release-qualified.yml": ["release"],
    },
)
if _D_ERRORS:
    sys.exit("FAIL shared publication audit:\n- " + "\n- ".join(_D_ERRORS))
_D_MUTATION = dict(_D_FILES)
_D_MUTATION["unreviewed-upload.yml"] = (
    "jobs:\n  leak:\n    runs-on: ubuntu-latest\n    steps:\n"
    "      - uses: actions/upload-artifact@v7\n"
)
if not _scan_publication_surface(_D_MUTATION, _D_EXPECTED):
    sys.exit("FAIL: new upload workflow bypassed shared scan")
print("PASS: common scan and existing Bridge-specific release/rights holds")

# Third-line guard: every workflow must remain byte-for-byte identical to
# the reviewed source-only configuration. Searching only for upload actions
# is insufficient: shell commands, reusable workflows, and YAML refactors
# could otherwise bypass pattern matching. A legitimate workflow edit must
# be re-reviewed and its Git blob pin updated, followed by exact-HEAD CI.
# This draft-only gate is NOT active on main before an authorized merge.
import hashlib as _hashlib

_APPROVED_WORKFLOW_GIT_BLOBS = {
    "build.yml": "880ab50d18184f325031d32b886b6b4145a5ebb2",
    "candidate.yml": "1a8c7b17a396cdcc5d084583f19649f8c6dac6d5",
    "public-pr-head-ci-recovery.yml": "c6c346346462b4636dea1833af85c36a59bf61e7",
    "release-qualified.yml": "1d6e1f1c335eb143704bd278c5b942f17636c561",
}

def _git_blob_sha1(_data):
    _header = f"blob {len(_data)}\0".encode("ascii")
    return _hashlib.sha1(_header + _data).hexdigest()

def _check_reviewed_workflow_bytes(_payloads):
    _errors = []
    _actual_names = set(_payloads)
    _expected_names = set(_APPROVED_WORKFLOW_GIT_BLOBS)
    for _name in sorted(_expected_names - _actual_names):
        _errors.append(f"missing reviewed workflow: {_name}")
    for _name in sorted(_actual_names - _expected_names):
        _errors.append(f"unreviewed workflow: {_name}")
    for _name in sorted(_actual_names & _expected_names):
        _actual = _git_blob_sha1(_payloads[_name])
        if _actual != _APPROVED_WORKFLOW_GIT_BLOBS[_name]:
            _errors.append(
                f"{_name}: unreviewed workflow bytes (Git blob {_actual}; "
                f"expected {_APPROVED_WORKFLOW_GIT_BLOBS[_name]})"
            )
    return _errors

_WORKFLOW_BYTES = {p.name: p.read_bytes() for p in _D_DIR.iterdir()
                   if p.suffix.lower() in (".yml", ".yaml")}
_WORKFLOW_ERRORS = _check_reviewed_workflow_bytes(_WORKFLOW_BYTES)
if _WORKFLOW_ERRORS:
    sys.exit("FAIL: source-only workflow pin:\n- " + "\n- ".join(_WORKFLOW_ERRORS))

# Regression: both an extra workflow and a changed existing workflow must
# fail, even when the change contains no obvious upload-artifact action.
_extra = dict(_WORKFLOW_BYTES)
_extra["bypass.yml"] = b"name: extra\non: workflow_dispatch\njobs: {}\n"
if not _check_reviewed_workflow_bytes(_extra):
    sys.exit("FAIL: extra workflow bypassed exact workflow allowlist")
_tampered = dict(_WORKFLOW_BYTES)
_tampered["candidate.yml"] += b"# harmless-looking but unreviewed edit\n"
if not _check_reviewed_workflow_bytes(_tampered):
    sys.exit("FAIL: changed workflow bypassed reviewed Git blob pin")
print("PASS: four reviewed workflows match Git blob pins; mutations rejected")
