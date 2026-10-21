# Bridge autonomous integration and release safety policy

**Effective 2026-10-21 by the repository owner's standing instruction.**

The owner granted ongoing permission to develop the Bridge autonomously and
**merge qualified source-only changes** without requesting a separate manual
approval for each pull request. The owner also authorizes future releases
**only when all independent safety, legal, end-device and release gates have
actually passed**. This is not an authorization to bypass any gate.

## Source-only merges — automated, bounded

A reviewed PR may be merged into `main` without a new owner confirmation if:

1. The exact proposed head commit has successful required contract, Windows
   Win32/x64 real foobar host, source-only publisher and original consumers,
   v2/v3 verifier, crash-recovery and metadata/CUE safety checks **as relevant
   to the change**, or equivalent independently reviewed evidence.
2. Both the effective `main` workflow and the proposed post-merge workflow
   explicitly prevent public Bridge DLL uploads, component packaging,
   release creation and unintended artifacts. Merge only when the destination
   immediately becomes fail-closed; never dispatch the historical unguarded
   `main` workflows before such a merge.
3. The owner-approved **MIT plus Commons Clause v1.0** license remains
   present and its exact reviewed text is protected by the audit, together
   with the independent foobar2000 SDK/pfc/libPPUI notices.
4. No personal audio, metadata, cues, foobar profile/DB, Rekordbox database,
   credentials, license keys, proprietary player installers or unrelated
   project files are committed, copied or modified.
5. GitHub branch protection, required checks and authorized permissions are
   respected; no administrative bypass, force push or security-disablement.
6. The PR changed-file list, commit head, CI run IDs and zero artifact count
   are recorded so source-only integration is auditable.

Only the integrated PR supersedes overlapping predecessor Drafts; do not
merge obsolete intermediate branches after the already-qualified composite
head because they could revert SDK/safety gates.

## Public binary release — a distinct, later autonomous operation

No release, tag, component packaging, DLL artifact upload or activation of
the currently suspended release workflows is allowed merely because
source-only `main` passed CI. Publication requires **all**:

1. Owner rights to distribute all contents, separate third-party notices
   and provenance, correct combined project license, and a reviewed release
   manifest/notice bundle.
2. Full exact-source SHA build and runtime qualification in both supported
   foobar2000 architectures with the original verified installer, including
   the required virtual CUE and metadata cases.
3. **Actual private DJ-device acceptance** for the real foobar profiles and
   associated DJ Library/MyTagSync consumers, with explicitly authorized
   device access, read-only hashes and database invariants. Previous
   synthetic 54,129-track tests are not real-library acceptance.
4. No unresolved safety failures, no new unreviewed source or dependency,
   a reproducible and reviewed exact candidate SHA256 and package structure.
5. Publisher/workflow audit remains an enforceable release gate.
6. Publication is consistent with the owner's standing authorization at
   that time. If a material policy/security/licensing decision changes,
   pause and ask; owner can withdraw the standing authority at any time.

This standing permission avoids routine merge/release approval requests.
It **does not** grant access to the owner's computer, connected drives or
private data. A truly necessary private device/test action still requires
the owner's separate involvement. Don't conflate source availability on
GitHub with a qualified, published foobar2000 component release.

**Current state:** No private-device final acceptance yet. Therefore
source-only main integration may proceed after its exact-HEAD safety checks,
but the compiled component cannot be released publicly.
