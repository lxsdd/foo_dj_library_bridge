# Repository operating rules

This repository is the canonical source of truth for `foo_dj_library_bridge`. Builds, tests, candidate packaging, and releases must be reproducible in GitHub Actions without a persistent local development checkout.

## Component safety

- The component is read-only with respect to audio files, tags, and foobar2000 private databases.
- Preserve profile-local / multi-instance behavior and the snapshot completeness protocol.
- Keep exact `(path, subsong)` identity and the documented schema contract.

## Build matrix

- Build both Win32 and x64 with the pinned/qualified foobar2000 SDK and supported Visual Studio toolset.
- Keep independent pure-contract tests and gzip validation.
- No hidden dependency may require a developer-machine path or preinstalled local SDK copy.

## foobar2000 component packaging

A combined `.fb2k-component` package must use this exact architecture layout:

```
foo_dj_library_bridge.dll          # Win32/x86 DLL in archive root
x64/
  foo_dj_library_bridge.dll        # x64 DLL
```

Do not use an `x86/` directory for the 32-bit DLL.

CI must verify the PE machine architecture before packaging:
- root DLL = x86 / IMAGE_FILE_MACHINE_I386;
- `x64/foo_dj_library_bridge.dll` = x64 / IMAGE_FILE_MACHINE_AMD64.

A candidate or release fails qualification if either architecture is missing, swapped, duplicated incorrectly, or packaged at the wrong path.

## Candidate and release policy

- `VERSION` is the canonical package/release version source.
- Candidate packaging runs in GitHub Actions from one exact commit.
- Emit SHA-256/integrity metadata with the component package.
- Real foobar2000 runtime validation must use the exact candidate artifact.
- Release promotion derives the immutable `v<VERSION>` tag from the candidate manifest, reuses and verifies that exact candidate, and never rebuilds after runtime qualification.
- Existing release tags are immutable and must never be replaced.
