# Validation

Portable checks and explicitly selected native-host evidence.

### portable-default — Default checks and unit/fixture tests require the shared runtime without installed AI clients or a fixed host catalogue

Why: common validation must not require unrelated clients

- Run default checks and unit/fixture tests without AI clients in PATH → pass without client discovery, installation or model calls.

### selected-host-checks — Native checks run only when selected; missing required verification is named and never passed

Why: explicit coverage keeps unavailable verification visible

- Select Claude/Codex validators and a fixture adapter with another name → selected checks execute without editing the common catalogue; unknown, missing, failed and unsafe selectors refuse; coverage names actual validators/versions.
- After login, load the package in real Qoder and dispatch all three roles → capture loaded sources, role identity, requested/reported settings and result delivery; unavailable settings or authentication are not passed
- Drive a complete Qoder temporary-repository workflow, including question/recovery and authorized finish → captured evidence meets the same contract; fixtures cannot satisfy this required live case

### coverage-is-named — Reports distinguish core, fixture, loader and live coverage, actual versions and limits

Why: narrower evidence cannot certify broader compatibility

- Select Claude/Codex validators and a fixture adapter with another name → selected checks execute without editing the common catalogue; unknown, missing, failed and unsafe selectors refuse; coverage names actual validators/versions.
- Load complete packages from relocated paths → common skills, role sources, references and CLI resolve to the intended revision; target-project profiles/artifacts stay outside package code.
- After login, load the package in real Qoder and dispatch all three roles → capture loaded sources, role identity, requested/reported settings and result delivery; unavailable settings or authentication are not passed
- Drive a complete Qoder temporary-repository workflow, including question/recovery and authorized finish → captured evidence meets the same contract; fixtures cannot satisfy this required live case
