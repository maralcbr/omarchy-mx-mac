# Release Notes

Each stable Mac release has one curated notes file named after its immutable
tag, for example `v4.0.0-mac.14.md`. The release workflow publishes that file
verbatim instead of generating notes from pull request titles.

Release preparation must:

1. Update `version` and the recommended version in `README.md`.
2. Add the release to `CHANGELOG.md`.
3. Add `docs/releases/vX.Y.Z-mac.N.md` with user-facing changes, validation,
   known limitations when applicable, and a full-diff link.
4. Run `tests/stable-release-test.sh` before creating the tag.

The notes file must exist in the tagged commit. The publishing workflow reads
it with `git show`, validates its title and required sections, and passes the
immutable copy to `gh release create --notes-file`.
