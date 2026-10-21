# Proposed licensing — NOT YET AN OPERATIVE LICENSE

**Status: proposal / owner review only (2026-10-21).**
**This document does not grant any reuse, modification, redistribution or commercial rights.**
There is deliberately **no root `LICENSE`**. Do not interpret a GitHub-public
repository, a Draft PR or this proposal as a copyright grant. No binary
distribution, package, release or merge is authorized by this proposal.

## Owner's stated intent

The project owner has described developing `foo_dj_library_bridge` from the
ground up with an AI assistant, prefers **free access, use and free sharing**,
including for DJs who earn money from live performances, and wants to prevent
third parties from **selling the Bridge itself or a substantially equivalent
renamed/repackaged paid plugin or paid Bridge-as-a-service**.

The owner has not approved a final legal text, public licensor name or a
`LICENSE` file yet. AI-assistance is not by itself proof of ownership of every
fragment; the provenance/third-party inventory is a distinct release gate.

## Candidate: MIT License + Commons Clause License Condition v1.0

**Not plain MIT.** The proposed operative text, *only after owner approval*,
would contain both complete, unchanged standard documents:

1. MIT base license: <https://opensource.org/license/mit>
2. Commons Clause License Condition v1.0:
   <https://commonsclause.com/>
3. Fill Commons Clause variables as:
   - **Software:** `foo_dj_library_bridge` — Bridge-owned project source
     and compiled component, **excluding third-party SDK, pfc, libPPUI,
     foobar2000 player/installer, GitHub Actions, and independently licensed
     materials**.
   - **License:** MIT
   - **Licensor:** **[owner's public legal name / authorized entity — TO BE APPROVED]**
4. Fill MIT copyright line as **2026 [verified copyright owner / entity — TO
   BE APPROVED]**. Do not infer the user's legal name from Git account details
   or commit author metadata.

**The result is source-available, not OSI-approved open source.** Commons
Clause is a restrictive additional condition and must accompany the MIT notice
in every permitted redistribution. Do not identify this combination as
`SPDX-License-Identifier: MIT` without the additional condition, and do not
use GitHub's plain-MIT license badge.

## Expected interpretation; edge cases needing particular care

| Example | Candidate rule / limitation |
| --- | --- |
| A paid professional DJ runs Bridge for their own music library | Normally permitted: they are paid for DJ performance, not for selling Bridge functionality |
| Hobbyists build and share modified Bridge versions for free | Generally permitted with all requisite notices |
| Someone rebrands and sells the unmodified or trivially changed Bridge plugin | Prohibited under the Commons Clause definition of selling substantially the same functionality |
| Paid cloud hosting, paid setup, consulting or support whose value derives substantially from Bridge | May be prohibited: Commons Clause explicitly mentions hosting and consulting/support; do **not** promise these are automatically allowed |
| A materially different paid DJ application includes Bridge among substantial independent features | May be permissible where the paid product's value does *not* derive entirely or substantially from Bridge; this clause is **not** a universal ban on earning money from all software that uses Bridge |
| Bundle contains foobar2000 player files or SDK code | **Outside Bridge-owner's permission.** Respect those components' own licenses, packaging and attribution restrictions |

The words *entirely or substantially* create a factual, potentially disputed
boundary. There is no widely recognized `MIT-NonCommercial` license that is
both MIT and bans selling. A custom stricter no-resale/no-fees license could
more closely match particular edge cases but should be drafted/reviewed by
qualified legal counsel instead of modifying standard text informally.

## Mandatory before creating LICENSE or enabling distribution

- Owner expressly approves the MIT **plus** Commons Clause text and the
  precise named licensor / copyright notice. A general conversation about
  intentions is **not** approval of missing legal fields.
- Confirm independent licensing rights and third-party exclusions for all
  seven original Bridge production files and later contributions. Git
  authorship and AI-generated output alone do not independently establish
  every copyright/third-party clearance.
- Preserve foobar2000 SDK, pfc, libPPUI license texts/credits; do **not**
  substitute a Bridge license for them or imply affiliation with Peter
  Pawlowski / foobar2000.
- Independently review any installer mirrors under the foobar2000 **player**
  license, separate from component/SDK licensing; never repackage extracted
  player executables with a plugin.
- Obtain the owner's explicit individual permission before merging or
  enabling any candidate, upload, tag, release or DLL distribution workflow.
- Record exact green CI SHA and private-device, real-library read-only final
  acceptance independently. Synthetic 54,129 tracks are not the owner's
  actual collection.

**External primary sources:** MIT text at OSI; Commons Clause original text
and FAQ at commonsclause.com; Open Source Definition at
<https://opensource.org/osd>. This is a technical licensing preparation
document, not a substitute for legal advice or a signed ownership assessment.
