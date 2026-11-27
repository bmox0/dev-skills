---
name: release-runweld
description: Prepare, publish and verify a Runweld CLI release when asked to bump VERSION, draft release notes, or ship a patch, minor or major version.
---

# Release Runweld

Read `VERSION` and inspect changes on `main` since the preceding version bump. Use `git log -1 --format=%H -- VERSION` to locate the bump and inspect the subsequent commits and diffs. For a version already bumped, compare with the previous bump. Historical versions can lack Git tags.

Honor the requested bump. Draft short English notes for the humans and agents using the CLI. Describe observable changes, useful commands and any effect on existing runs. Keep internal fixes within the same release out of the notes. Save the approved text in `docs/releases/<version>.md`; CI also supports a plain `VERSION` bump with GitHub-generated notes.

For a preview, show the proposed version and notes in chat. For publication, show the version and notes for approval unless the owner has already authorized those exact terms. Commit the version and notes together on `main` and push the approved changes. Check for unrelated staged or working-tree changes, particularly `.runweld/runweld.lock`, and leave them out of the release commit.

The existing CI publishes on a green push that changes `VERSION`. It creates `v<version>` at the tested push SHA. Follow the run for that SHA with `gh run list --workflow ci.yml --commit SHA` and `gh run watch RUN_ID --exit-status`. Check the resulting tag, title, notes and URL with `gh release view TAG` and confirm the tag resolves to the tested commit. On failure, inspect the failed job; retry that run for a transient failure. An existing tag on another commit requires the owner's decision.

Report the release URL. Projects select the new CLI release for new tasks with `runweld update --project` after installing it. Existing runs retain their pinned release.
