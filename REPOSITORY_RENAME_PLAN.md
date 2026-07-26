# Repository Rename Plan

Target name: `maralcbr/omarchy-mx-mac`

Status: completed on July 26, 2026.

The repository slug changed, while the Omarchy Mac product and existing command
names remain unchanged for compatibility. The old repository name must remain
unused so GitHub can continue redirecting legacy installations.

This plan intentionally separates preparation from the GitHub rename so release
downloads and installation commands can be checked before the public URL changes.

## 1. Confirm The Target

- Confirm that `omarchy-mx-mac` is the final spelling and project name.
- Verify that `maralcbr/omarchy-mx-mac` is available immediately before rename.
- Decide whether `Omarchy MX Mac` should replace `Omarchy Mac` in user-facing
  text or whether only the repository slug changes.
- Announce a maintenance window and avoid publishing a release during it.

## 2. Prepare Repository References

- Create a dedicated rename branch from `main`.
- Replace active hard-coded `maralcbr/omarchy-mac` URLs in bootstrap, setup,
  install, boot, configuration, documentation, badges, and issue templates.
- Inventory historical migrations separately. Update one only when its runtime
  behavior depends on the old URL; otherwise preserve history and rely on the
  GitHub redirect.
- Update maintainer documentation, local path examples, and test fixtures that
  use `omarchy-mac` as a checkout directory.
- Review the `OMARCHY_REPO` defaults in `bootstrap.sh`, `setup.sh`, and `boot.sh`.
- Update GitHub Pages references from `maralcbr.github.io/omarchy-mac` if Pages
  remains part of the installation path.
- Keep compatibility only where old persisted configuration or published
  installers require it; do not duplicate names everywhere preemptively.

## 3. Audit External Dependencies

- Record branch protection, Actions secrets, environments, webhooks, deploy
  keys, GitHub Pages settings, Discussions, and release automation.
- Check links from `omarchy-pkgs`, release notes, package metadata, Discord,
  social posts, and external installation guides.
- Confirm whether package and release assets contain embedded source URLs.
- Preserve immutable release tags and checksums; do not rebuild an existing
  release solely to change a redirected source link.

## 4. Perform The GitHub Rename

- Rename the repository in GitHub Settings from `omarchy-mac` to
  `omarchy-mx-mac`.
- Confirm that GitHub redirects the old repository, clone, issue, discussion,
  commit, and release URLs.
- Update the local remote:

```bash
git remote set-url origin https://github.com/maralcbr/omarchy-mx-mac.git
git remote -v
```

- Push the prepared reference changes to the renamed repository.

## 5. Reconfigure GitHub Services

- Recheck the default branch and branch protection rules.
- Recheck GitHub Actions permissions, environments, secrets, and scheduled jobs.
- Reconfigure GitHub Pages and its custom domain or deployment source.
- Verify issue templates, Discussions links, badges, and repository metadata.
- Update package repository links and future release notes to the new URL.

## 6. Validate End To End

- Clone the renamed repository into a clean directory using the new URL.
- Fetch `main`, `dev`, tags, and submodules if any.
- Run repository tests and the Apple Silicon focused test suite.
- Verify old GitHub URLs redirect and new raw-content URLs return expected files.
- Run the public Quattro bootstrap with `--verify-only` on the tested MacBook.
- Confirm update checks, package source metadata, issue links, and Pages links.

## 7. Communicate And Monitor

- Publish a short rename notice in the README, release notes, and Discussions.
- Ask maintainers to update local remotes and documentation bookmarks.
- Monitor issues, Actions, Pages, and release downloads for broken links.
- Keep the old-name compatibility window provided by GitHub redirects; do not
  create a new repository at `maralcbr/omarchy-mac`, because that would break
  those redirects.

## Rollback

If critical automation or installation links fail, rename the repository back
to `omarchy-mac`, restore the previous remote URL, and investigate on a branch.
Published package assets and immutable release checksums should remain unchanged
during rollback.
