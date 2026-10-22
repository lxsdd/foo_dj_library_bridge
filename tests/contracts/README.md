# Bridge v3 + embedded-CUE golden wire contract

The file `bridge-v3-cue-identity.tsv` is a **synthetic, non-user-media** golden vector for the original C++ Bridge producer. Its canonical source owner is `lxsdd/foo_dj_library_bridge`; consumers must pin the immutable Git blob rather than reimplementing this fixture generator independently.

- Exactly 26 tab-separated header columns in schema v3 order; column 24 (1-based) is `tag_fingerprint` and the final two contain compact JSON.
- Three rows have the **same synthetic path** but distinct `subsong` indices `0`, `1`, `2` and distinct producer-computed 16-digit FNV fingerprints. `0` is a *candidate* physical row subject to independent eligibility checks; `1` and `2` are virtual CUE subsongs and must **never** be inferred, substituted or counted as physical files or write targets.
- The metadata vector preserves `DATE`, `GENRE` and `MOOD` as ordered value arrays. Extras contain only non-core `MOOD`; no real tag or file was read.
- The native producer `tests/contract_tests.cpp` compares actual serialized C++ output to every byte of the golden fixture on its existing GCC/Clang CI. A changed `title` invalidates the original fingerprint. Separate language consumers must verify parser behavior against this *same* SHA-pinned file; the producer test alone does **not** prove their own preview/mapping/read-only policies.
- Scope: **read-only interchange and source identity**. It does not authorize any foobar metadata write, rekordbox SQLCipher operation, tag alteration, or public binary release. Package/security/licensing/end-user acceptance remain independent.

Do not add personal drive letters, user profile paths, music excerpts, Discogs credentials or database records to fixtures.
