# Third-party inventory and release notice gates (source-only Draft)

**Status: 2026-10-21, no distribution authorization.** This is an
inventory of independently licensed upstream materials used by the Bridge
CI/build. It is not an exhaustive software-supply-chain audit or an
authorization to distribute compiled binaries. The owner-selected project
license cannot relicense any of these materials.

## Source of truth for pinned build dependency

Existing, independently successful [PR #17 integration CI](https://github.com/lxsdd/foo_dj_library_bridge/actions/runs/39593237071)
builds with foobar2000 SDK **2026-10-01**, from the owner's pinned public
`lxsdd/foobar2000_component_template` Git commit:
`31a35947a7527826c2199491692802e3ce3d8bd7`,
vendor SDK subtree Git object:
`2ba8caeb73f72633ad7f60ee5f72ed8074a0eb17`.

`SDK-PIN.json` in that immutable commit describes upstream vendor archive
`https://www.foobar2000.org/downloads/SDK-2026-10-01.7z`
(793,738 bytes; SHA-256
`d4c55077336fae81bf8df0259b5b2748fa45ea84132c656ead93eb123cbcdc26`).
**Verification of the pinned Git tree is NOT verification of vendor .7z
archive bytes.** Do not misrepresent the archive claim.

## Inventory of distinct license regimes

| Dependency / material | Pinned original notice (relative to `vendor/sdk`) | Exact Git blob | Conditions to retain and check |
| --- | --- | --- | --- |
| foobar2000 **2.x SDK** (Peter Pawlowski) | `sdk-license.txt` | `fb358788e9b8459de9a8225af79159d042fa93da` | BSD-like source/binary grant with retained source copyright, conditions and disclaimer; no author/contributor name endorsement |
| **pfc** library | `pfc/pfc-license.txt` | `ca25433e1f0cd9b63a576791ee832d704862abb9` | Permissive including commercial use; do not misrepresent origin; mark altered sources; retain notice in source redistribution; attribution in product documentation appreciated but not required |
| **libPPUI** library | `libPPUI/libPPUI-license.txt` | `ca25433e1f0cd9b63a576791ee832d704862abb9` | Same conditions as pfc; independently identified despite matching text |
| foobar2000 **player / installer** | <https://www.foobar2000.org/?page=License> | **Not bundled as Bridge source** | Redistribution only of **unmodified original installer**, not extracted foobar program files; no endorsement. Separate from SDK and Bridge licenses |
| **Bridge-owned original project code** | `src/*.cpp`, `src/*.h` | Per-file first-introduction history preserved in safety Draft #9 | Owner-approved **MIT + Commons Clause v1.0** in root `LICENSE` (`Copyright (c) 2026 lxsdd`; `Licensor: lxsdd`). Excludes all independent SDK/player/library materials; separate provenance and release clearance still required. |
| **Actions / test fixture tools** | SHA-pinned GitHub actions, .NET, Python, MSVC, synthetic fixtures | See exact CI build workflow and vendor tools' original licensing | Build/test tools are not thereby relicensed as Bridge. Revalidate any parts copied or distributed in a later archive |

No original foobar2000 installer, SDK archive, private music, source
databases, .fb2k-component or DLL is committed or published by this Draft
license inventory.

### Previously independently verified SDK notice contents

The SDK 2026-09-17 vendor archive was separately inspected on Windows
(previous [PR #9](https://github.com/lxsdd/foo_dj_library_bridge/pull/9)
provenance checks):
- `sdk-license.txt` SHA-256:
  `e1413fbd19af042ae2c7e47d2d323471436cc3b601dfd5dd975986a58c9e7967`
- `pfc-license.txt`, `libPPUI-license.txt` SHA-256:
  `03874acd85ca8ee28d5e33abbfbc00352ca05b4a59da085241bc1b47d7269d66`.

The old archive notice text, after its established newline normalization,
matches the very same exact Git license-text blobs used by SDK 2026-10-01.
This is text identity, **not** a whole-SDK-tree equality claim.

## Eventual distribution: explicit NO-GO until each is complete

1. Recheck project rights, all relevant contributors, the original
   source provenance and actual scope of the **now owner-approved**
   MIT + Commons Clause grant (public licensor `lxsdd`). The owner
   has described creating Bridge from scratch with AI assistance, but
   commit authorship and that statement alone do not establish
   third-party fragment provenance exhaustively.
2. Recheck and carry SDK, pfc and libPPUI notices as legally required for
   the actual proposed *distribution format* (source package vs compiled
   component). Do not silently remove vendor notices from redistributed
   source files. Check any new linker libraries independently.
3. Never repackage extracted foobar2000 player files with the component.
   Keep any unmodified installer transport separate, with its own upstream
   attribution and SHA-256 verification; no implication of vendor endorsement.
4. Final private end-device safety and real collection acceptance plus
   exact-Git-HEAD CI, reviewed build manifests, and owner-approved artifact
   SHA. None is implied by isolated synthetic-host CI results.
5. Owner has given **standing permission for qualified source-only
   merges**, not for bypassing safety checks or actual DJ-device tests.
   Package/release/tag/distribution remains gated by
   [the autonomous policy](AUTONOMOUS-PROMOTION-POLICY.md)
   and must not proceed until all prerequisites are independently met.

**Primary references:** vendor license files at the immutable Git tree,
<https://www.foobar2000.org/?page=License>, and
<https://www.foobar2000.org/SDK>.
