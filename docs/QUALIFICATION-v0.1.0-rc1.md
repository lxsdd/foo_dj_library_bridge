# Qualification — 0.1.0-rc1

Date: 2026-09-29  
Qualified baseline before the version-only RC promotion: `228bcfa6f2f9539154e1b25e08c02f29fa10bb35`.

## Cloud qualification

PASS:

- exact schema-v1 24-column contract;
- dependency-free RFC 1952 gzip writer, including multi-block boundary test;
- GCC and Clang contract builds with warnings-as-errors;
- static read-only/safety audit;
- Windows/MSVC Win32 component build;
- Windows/MSVC x64 component build.

## Real foobar2000 runtime qualification

Test Media Library size: **1,345 tracks**.

PASS:

1. Initial full scan exported exactly 1,345 items.
2. Removing one Media Library item advanced the bridge from Gen. 1 to Gen. 2 and produced exactly 1,344 items.
3. Modifying a track genre advanced Gen. 2 to Gen. 3 while retaining exactly 1,344 items.
4. Re-adding the removed item advanced Gen. 3 to Gen. 4 and restored exactly 1,345 items.
5. Fully restarting foobar2000 passed the lifecycle test: the complete 1,345-item Media Library was republished and the generation continued rather than reverting to a stale snapshot.
6. DJ Library v0.3.1 RC8 loaded the live snapshot at startup and reported the live generation/item count.

## Safety boundary

The component reads the Media Library through the supported foobar2000 SDK and cached metadata access. It does not write tags/audio files and does not access foobar2000 private database formats.

## RC1 delta

The RC1 promotion changes only the component version string, the static version assertion and documentation. Producer behavior, bridge schema, publisher, callback logic and build configuration are unchanged from the real-runtime-qualified baseline.
