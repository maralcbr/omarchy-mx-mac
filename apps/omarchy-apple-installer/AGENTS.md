# Apple installer development

## Goal autonomy

During an active goal, choose and implement the best reversible local source,
test, or documentation option without pausing for routine choices. Stop only
when the next step needs owner authority, credentials, physical-device access,
or would cross a safety boundary below.

## Language conventions

- Format Python with conventional four-space indentation and validate it with
  `py_compile` plus the focused engine tests.
- Format Swift with the package's `swift-format` configuration and validate
  macOS builds and tests through XcodeBuildMCP.
- Keep shell scripts compatible with the root repository rules. Build workers
  come from `OMARCHY_BUILD_JOBS`, whose default is 10.

## Completion evidence

For installer changes, verify the focused Python tests, Swift tests in debug
and release, packaging structure, code-signing requirements, and unsupported
host rejection as applicable. A source build is not physical installation
proof.

## Authorization boundary

Local source edits, pure tests, read-only inspection, and disposable artifacts
are reversible. Obtain the owner's explicit authorization immediately before
helper registration, privileged execution, disk or boot-policy mutation,
signing or notarization with production credentials, publication, deployment,
or physical-device work. Keep `apple,j614s` fail-closed until official support
and physical qualification both exist.
