# Validation

Portable checks and explicitly selected native-host evidence.

### portable-default — Default checks and unit/fixture tests require the shared runtime without installed AI clients or a fixed host catalogue

Why: common validation must not require unrelated clients

- Run default checks and unit/fixture tests without AI clients in PATH → pass without client discovery, installation or model calls.
