# Distribution

One complete shared package exposed through native integration metadata.

### shared-resources — Native installations expose the same complete skills, roles, references and CLI from the intended revision

Why: instructions without their resources do not install the workflow

- Load complete packages from relocated paths → common skills, role sources, references and CLI resolve to the intended revision; target-project profiles/artifacts stay outside package code.
- After login, load the package in real Qoder and dispatch all three roles → capture loaded sources, role identity, requested/reported settings and result delivery; unavailable settings or authentication are not passed
