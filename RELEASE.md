# foo_dj_library_bridge release procedure

> **ON HOLD — 2026-10-21. DO NOT DISPATCH A CANDIDATE OR RELEASE.**
> This document preserves the *future* promotion design only.
> Independent Draft PR #9 disables the component DLL uploads, the package
> job, and the manual release job. Those changes are **not on main** until
> the repository owner explicitly approves and merges them. The older
> `main` workflows can still publish binaries on non-PR triggers.
> Do not trigger them while rights/notice, exact-head Windows qualification,
> private end acceptance and explicit merge/release approvals remain open.
> See `docs/RELEASE-GATES-AND-PROVENANCE.md` for the authoritative
> current gate state.

GitHub is the canonical source and build authority. A release is promoted from a qualified candidate; it is never rebuilt.

## Version source

`VERSION` is the canonical package and release version. The component packager records that value in `BUILD-MANIFEST.txt`.

## Candidate qualification

**Only after all release gates are cleared and the owner authorizes it:** run **foobar bridge candidate** manually from an approved `main` commit.

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

**Only after a separate explicit release authorization:** run **Release qualified foobar bridge candidate** and provide the successful candidate run ID.

The workflow verifies that the candidate:

- succeeded;
- was manually dispatched through `.github/workflows/candidate.yml`;
- ran on `main`;
- produced exactly the SHA-bound component artifact;
- matches the manifest commit and version;
- has the required x86/x64 PE architecture and archive layout;
- matches `SHA256SUMS.txt`.

It then creates tag `v<VERSION>` and publishes the exact candidate files without rebuilding. An existing tag/release is never replaced.
