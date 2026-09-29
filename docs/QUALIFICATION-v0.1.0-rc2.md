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

## Required real-runtime migration check

1. Upgrade the qualified foobar instance from RC1 to RC2 and restart it.
2. Confirm a fresh profile-local snapshot exists with exactly 1,345 items.
3. Confirm DJ Library selects the profile-local source rather than the stale RC1 global location.
4. Install RC2 into the second foobar profile/instance.
5. Confirm both profile-local snapshots coexist and can be selected independently, with no cross-overwrite.
