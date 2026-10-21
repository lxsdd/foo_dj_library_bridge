# foo_dj_library_bridge release procedure

> **SUSPENDED — DO NOT EXECUTE, source-only Draft (2026-10-21).**
> Historical `main` candidate and manual release workflows remain
> publish-capable and are NOT yet covered by unmerged Draft guards.
> **Do not dispatch candidate/package/release workflows, create tags
> or distribute DLLs.** The owner's standing instruction **does allow
> independently qualified, fail-closed source-only PR merges** under
> [the autonomous safety policy](docs/AUTONOMOUS-PROMOTION-POLICY.md).
> Green synthetic host CI alone does not authorize public binary
> releases. The owner-approved [MIT + Commons Clause v1.0](LICENSE)
> applies only to Bridge-owned materials. Release still requires legal
> provenance, third-party notices, actual private DJ-device read-only
> acceptance and independently verified exact-SHA package safeguards.
> The procedures below are **historical design notes only** until
> formally requalified and separately approved.

GitHub is the canonical source and build authority. A release is promoted from a qualified candidate; it is never rebuilt.

## Version source

`VERSION` is the canonical package and release version. The component packager records that value in `BUILD-MANIFEST.txt`.

## Candidate qualification

Run **foobar bridge candidate** manually from `main`.

The reusable build workflow:

1. runs static safety/contract audits;
2. runs the pure contract suite with GCC and Clang;
3. validates generated gzip streams independently;
4. builds Win32 and x64 with the qualified foobar2000 SDK/toolset;
5. verifies root DLL = IMAGE_FILE_MACHINE_I386 and `x64/` DLL = IMAGE_FILE_MACHINE_AMD64;
6. creates exactly one combined `.fb2k-component`;
7. emits `BUILD-MANIFEST.txt` and `SHA256SUMS.txt`;
8. uploads `foo_dj_library_bridge-component-<commit>`.

The archive layout is mandatory:

```
foo_dj_library_bridge.dll
x64/
  foo_dj_library_bridge.dll
```

There is no `x86/` directory.

## Runtime acceptance

Use the exact candidate artifact for any real foobar2000 runtime qualification. Do not rebuild locally.

## Release promotion

Run **Release qualified foobar bridge candidate** and provide the successful candidate run ID.

The workflow verifies that the candidate:

- succeeded;
- was manually dispatched through `.github/workflows/candidate.yml`;
- ran on `main`;
- produced exactly the SHA-bound component artifact;
- matches the manifest commit and version;
- has the required x86/x64 PE architecture and archive layout;
- matches `SHA256SUMS.txt`.

It then creates tag `v<VERSION>` and publishes the exact candidate files without rebuilding. An existing tag/release is never replaced.
