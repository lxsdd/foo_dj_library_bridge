# Qualification — 0.1.0-rc2

Date: 2026-09-29

## Purpose

Move bridge runtime storage from the global `%LOCALAPPDATA%\DJLibrary\bridge` directory into the active foobar2000 profile and add source metadata so multiple foobar profiles can coexist safely.

## Cloud qualification

PASS on commit `b0e5b00a81dc001506b371bbc562ba3fe9b3d9ab`:

- static read-only/safety audit;
- profile-local path contract using `core_api::get_profile_path()`;
- no producer reference to `LOCALAPPDATA`;
- optional source metadata present in the state sidecar;
- exact schema-v1 24-column payload unchanged;
- GCC and Clang contract builds;
- independent gzip decoder/boundary test;
- Windows/MSVC Win32 build;
- Windows/MSVC x64 build.

## RC1 runtime baseline retained

RC1 was qualified on a real 1,345-track foobar2000 Media Library:

- full scan;
- remove;
- metadata/genre modify;
- add;
- full foobar restart lifecycle;
- DJ Library live snapshot activation.

RC2 does not change those callback/matching payload semantics.

## Real-runtime migration and multi-profile qualification

PASS on Windows with DJ Library v0.3.1 RC9:

1. Portable/alternate foobar profile produced its own profile-local bridge:
   - source: `64bit (portable)`
   - profile: `C:\\Projects\\foobar2000\\64bit\\profile`
   - generation: 1
   - items: **1,345**
2. Standard foobar2000-v2 profile produced a separate profile-local bridge:
   - source: `foobar2000-v2`
   - profile: `%APPDATA%\\foobar2000-v2`
   - generation: 1
   - items: **54,129**
3. DJ Library manually selected the portable source and applied the 1,345-item snapshot.
4. Returning to automatic source selection switched to the standard profile and applied the 54,129-item snapshot.
5. The two sources kept independent generation counters and item counts; no cross-overwrite occurred.
6. Matching and genre projection were recalculated after source switching, proving the selected payload rather than stale status metadata became authoritative.

RC2 multi-instance/profile-local storage is therefore **runtime-qualified** for the tested standard + portable profile arrangement.
