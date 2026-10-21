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
| Vendor SDK integrity | Archive `SDK-2026-09-17.7z`: 793,742 bytes, SHA-256 `24fa95ed66b42624f593fd4b94c5efb08ae81dfebb92b79fe69c8cd170961e48`; two hosted Windows checks | Archive SHA-256 and all three original license texts bytewise verified; release notices and Bridge rights still OPEN |
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
- **Original SDK notice text identity VERIFIED, 2026-10-21.** Both hosted
  Windows builds independently extracted license files from the pinned
  793,742-byte vendor archive and reported identical original-file hashes
  (source-only run [39566578193](https://github.com/lxsdd/foo_dj_library_bridge/actions/runs/39566578193)):
  - `sdk-license.txt`: 1,441 bytes, SHA-256
    `e1413fbd19af042ae2c7e47d2d323471436cc3b601dfd5dd975986a58c9e7967`;
  - `pfc/pfc-license.txt`: 856 bytes, SHA-256
    `03874acd85ca8ee28d5e33abbfbc00352ca05b4a59da085241bc1b47d7269d66`;
  - `libPPUI/libPPUI-license.txt`: 856 bytes, same SHA-256 as pfc.
  A public unmodified SDK mirror at
  <https://github.com/reupen/foobar2000-sdk-unmodified>
  contains text Git blobs `fb358788e9b8459de9a8225af79159d042fa93da`
  (SDK) and `ca25433e1f0cd9b63a576791ee832d704862abb9`
  (both pfc/libPPUI). After *only* LF->CRLF conversion the SHA-256 and
  byte counts match all three original archive files **exactly**. This
  makes the contents of these mirrored texts cryptographically tied to
  the pinned vendor archive; it does not make the mirror the vendor.
- **License-obligation inventory:** The SDK license permits source/binary
  redistribution with its retained source copyright/conditions/disclaimer
  and prohibits endorsement using author/contributor names without
  permission. The pfc and libPPUI license texts are the same, granting
  broad use including commercial use, subject to proper attribution of
  origin, marking altered source versions, and retaining the notice in
  source distributions. Copy/compile the exact required notices for any
  later permitted distribution; do not present this factual license
  review as an authorization for the separate original Bridge code.
- Public binary distribution is still held pending ownership/rights
  assessment for the Bridge sources and verified packaging/notice
  obligations. Never include or redistribute foobar2000 player binaries.
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
