# Licensing decision — MIT + Commons Clause v1.0 (approved 2026-10-21)

**Status: owner-approved for the Bridge-owned code on this Draft branch.**
The original nonbinding proposal was accepted with public copyright
holder / licensor **`lxsdd`**. The operative grant is now the complete
combined text in [`../LICENSE`](../LICENSE), not this explanatory document.
The former proposed file path is preserved so previously shared project
handoff links remain valid.

## Selected grant

- **Base:** complete MIT license text with `Copyright (c) 2026 lxsdd`.
- **Additional condition:** the complete, unchanged Commons Clause License
  Condition v1.0 with
  `Software: foo_dj_library_bridge`,
  `License: MIT`, `Licensor: lxsdd`.
- **Software scope:** original Bridge-owned source, authored scripts,
  documentation and compiled Bridge component to the extent licensable by
  the owner. This license does **not** replace the independent permissions
  and notices for foobar2000 player/installer, SDK, pfc, libPPUI, GitHub
  tools or third-party materials.
- **License classification:** *source-available*, **not OSI-approved open
  source**. Do **not** use a plain MIT-only badge or claim
  `SPDX-License-Identifier: MIT` alone fully describes the combined grant.

Official complete standard texts:
- MIT: <https://opensource.org/license/mit>
- Commons Clause v1.0: <https://commonsclause.com/>

## Owner's intended use and the actual condition

The owner developed the Bridge project with AI assistance and chose this
combination to permit **free access, private use, modification and sharing**,
including by DJs who are paid for performing at events, without permitting
third parties simply to rebrand/repackage and **sell the Bridge itself**.

Commons Clause defines prohibited **Sell** as offering a product or service
for a fee whose value is entirely or substantially derived from the
software's functionality. This includes substantially Bridge-derived paid
hosting or consulting/support; therefore **not all paid services can be
promised as allowed**. Materially different products adding substantial
independent functionality may be offered commercially; the clause is **not**
a blanket ban on all business activity involving Bridge.

Professional DJ performances using the free Bridge as an aid are different
from selling the Bridge itself. Nonetheless, each borderline commercial
service must be judged against the actual combined license text, not an
oversimplified slogan. This interpretation is informational, not a legal
opinion or assurance of any particular jurisdiction's enforcement.

## Public pseudonym and rights documentation

`lxsdd` is the owner's chosen public attribution/pseudonym. German
copyright law recognizes attribution under a chosen designation (UrhG
section 13) and addresses pseudonymous works (section 66).
The owner should privately retain evidence connecting this public handle
to the entitled individual or legal entity for possible enforcement.
It is not necessary to publish their civil name merely to use an alias.

The owner's assertion that the Bridge was independently developed with
AI assistance and the Git commit provenance for its seven original
production files are supporting project history, **not** exhaustive proof
that no protected fragment from a third party exists. No AI model or
hosting provider is listed as co-author merely because it assisted with
writing code. Relevant independent third-party material remains under
its original permissions.

See [third-party inventory](THIRD-PARTY-NOTICES-INVENTORY.md)
and independent source-provenance notes on safety Draft #9.

## Not a merge or release authorization

The owner **approved this licensing decision**. This is strictly different
from giving approval to merge PRs, publish DLLs, tag releases, or install
the component on their personal Windows/DJ machine.

- The license is present **only on the unmerged Draft integration branch**;
  the repository default branch has not been changed.
- Exact-head green isolated foobar2000 Win32/x64 CI and synthetic
  54,129-item producer/reader tests cannot substitute for private-device
  safety acceptance.
- Before distribution, recheck third-party code provenance/notice
  obligations, preserve separate foobar licenses, and obtain the owner's
  **separate explicit approval** for each promotion step.
- Keep all manual candidate/package/upload/release workflows blocked,
  particularly the historical publish-capable workflows still present on
  `main`.

References: <https://www.gesetze-im-internet.de/urhg/__13.html>,
<https://www.gesetze-im-internet.de/urhg/__66.html>,
<https://opensource.org/osd>. Not legal advice.
