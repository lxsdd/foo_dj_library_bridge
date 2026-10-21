# Bridge RC4 – release gates, provenance and final acceptance

**21 October 2026. Draft/source-only review; not a release authorization.**
Scope: `lxsdd/foo_dj_library_bridge`, foobar2000 SDK 2026-09-17 (MSVC v143,
C++20), Win32 and x64. Only ephemeral synthetic-host CI is in scope.
Neither downstream databases nor real audio libraries may be modified.

## Gate status and evidentiary limits

| Gate | Evidence / required proof | Status |
| --- | --- | --- |
| Native producer, v3 contract, Win32/x64 | Native C++ contract tests, gzip, original C# DJ Library and MyTagSync readers; 54,129 wholly fictional items; PR #11 / run 39445004110 | CI PASS at then-current SHA; **not** real-library acceptance |
| Real foobar 2.26.1 callback integration | Synthetic WAV additions/modification/removal and populated restart, PR #12 / run 39493913803 | Win32/x64 CI PASS |
| Virtual external CUE | 2 subsongs from one WAV, PR #13 / run 39498771682 | Win32/x64 CI PASS |
| Virtual multi-file CUE | Two physical WAV source files, different subsong identities, PR #14 / run 39503019270 | Win32/x64 CI PASS |
| Embedded FLAC CUE | **Vorbis-comment field** `CUESHEET`, not native FLAC metadata block, PR #15 / run 39505172077 | Win32/x64 CI PASS |
| Schema-v3 verifier and v2 compatibility | PR #7; distinguish `Inspect` structure from `LoadItems` semantics; re-check exact HEAD and its CI, not an older PR description | Independent Draft; final HEAD qualification pending |
| Binary publication hold | PR #9: disabled upload/package/release, scan + reviewed workflow Git-blob allowlist; exact-head CI and artifact count must be checked after every amendment | Independent Draft, **not on main** |
| Vendor SDK integrity | Archive `SDK-2026-09-17.7z`: 793,742 bytes, SHA-256 `24fa95ed66b42624f593fd4b94c5efb08ae81dfebb92b79fe69c8cd170961e48`; two hosted Windows checks | Archive identity qualified; exact notices still to compare/review |
| Component source provenance and notices | Trace original Bridge code, document copyright/ownership; review exact pinned `sdk-license.txt`, `pfc/pfc-license.txt`, `libPPUI/libPPUI-license.txt` and determine complete notices; provide an appropriate root LICENSE/attribution only after rights are established | **BLOCKED for binary release** |
| Actual private machine end acceptance | Real Windows 11 x64 laptop, isolated foobar profile(s), profile separation, large user library and portability; user authorizes activity | **DEFERRED, no user action now** |
| Tag/database safety | Invariant: no writing user audio, physical tags, foobar databases, rekordbox/MyTagSync databases; verify within controlled environment before any personal use | Source and synthetic tests only; real end acceptance pending |
| Merge / tag / artifact / release | Explicit owner approval, provenance and notice clearance, successful exact-HEAD and end-device gates | **BLOCKED** |

**Never** equate synthetic 54,129-item scale with the roughly 54,129-entry
personal library; never represent publisher crash recovery as a real foobar
host-process crash test. A Vorbis CUESHEET comment is not the native FLAC
`METADATA_BLOCK_CUESHEET`. Those are distinct, unqualified cases.

## Critical GitHub exposure during review

The protected `main` build workflow still uploads Win32/x64 binaries on
non-PR events and its release workflow is manually dispatchable. The safety
gates currently exist **only on the independent PR #9 branch**. Therefore:

1. Never run `workflow_dispatch`, `candidate.yml`, a release workflow,
   manual packaging, or non-PR build/reusable workflows until reviewed
   safety changes are explicitly approved and active on `main`.
2. Only `pull_request` events with independently verified artifact count
   **zero** may be used while the freeze remains in force.
3. Do not merge the #11–#15 stack individually or change its bases, and do
   not merge #7 or #9 without the owner's explicit permission.
4. Re-review every changed workflow against PR #9's exact Git blob allowlist;
   workflow integrity pins are a fail-closed review tripwire, not a substitute
   for GitHub settings and authorization controls.

## License distinctions / outstanding provenance work

- The **foobar2000 PLAYER** redistribution restriction and the
  **foobar2000 SDK** source/binary permission are different licenses.
  Do not bundle an installed player or redistribute player DLLs in a
  component candidate. See <https://www.foobar2000.org/license> and
  <https://www.foobar2000.org/SDK>.
- A public SDK mirror is a useful comparison, not proof of what is present
  in the pinned 2026-09-17 vendor archive. Only the verified archive and
  the three extracted original license files can close that provenance gate.
- The official SDK license and distinct pfc/libPPUI licenses require a
  complete redistribution/notice review. Do not assert blanket permission
  from the fact that an SDK can be downloaded or from an existing CI PASS.
- `main` currently lacks a root LICENSE that establishes redistribution
  rights for the original Bridge sources. Do not invent an SPDX license or
  claim rights to third-party material. Request an owner decision **only**
  when the evidence and a proposed license/notice inventory are ready.

## Private final acceptance, only after access returns

The existing `scripts/local-acceptance-build.ps1` in PR #9 can produce a
private SHA-pinned Win32/x64 candidate if a supported toolchain is already
available on the owner's **private** PC. It must never be imposed on the
current work/other PC. The previously observed proxy `403` to
`raw.githubusercontent.com` and PowerShell policy restriction do not prove
anything about the owner's DJ laptop. Do not assume MSBuild is absent there
or propose disabling device-wide security policy. No additional foobar
plugins, system-wide installation, or public GitHub artifacts are required
just to continue the source-only development.

Private acceptance, when eventually requested and authorized, must check:
an isolated standard and portable foobar profile, deterministic read-only
snapshots, generation/complete protocol through restart, identity collisions,
virtual CUE types, source separation, DJ Library/MyTagSync read-only
consumers, and practical library scale. It must leave user music,
foobar metadata and Rekordbox database contents unchanged.

## Promotion prerequisites

Only after (1) the safety hold is reviewed and approved, (2) every required
HEAD and its Win32/x64 CI are green with zero unwanted artifacts,
(3) provenance/notices and the original project license are cleared,
(4) personal end acceptance is recorded, and (5) the owner explicitly
authorizes each merge and release step, may a release workflow be designed
or enabled. No approval is implied by this document.
