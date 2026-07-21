# Security

## Safety boundary

CodexSkinTool edits only the documented appearance keys in the user's
`~/.codex/config.toml`. It does not modify `ChatGPT.app`, `Codex.app`,
`app.asar`, account data, conversations, projects, credentials, or provider
configuration.

Before the first theme change, the tool stores only the five managed appearance
values under `~/Library/Application Support/CodexSkinTool`; it does not copy the
complete Codex configuration. Writes use a sibling temporary file and an atomic
replacement. Configuration and local state files are restricted to the current
user with `0600` permissions.

## Optional image backgrounds

Image backgrounds are opt-in and are not part of Codex's documented appearance
configuration. The tool validates and copies the selected image to its private
support directory, launches Codex with an available CDP port bound to
`127.0.0.1`, and injects only after verifying an `app://` page and expected
Codex DOM markers. The decorative layer uses `pointer-events: none`.

CDP has no authentication; another process running as the same local user can
reach the temporary loopback port. Selecting a normal theme or restoring the
original appearance stops the recorded injector and relaunches Codex normally,
closing the CDP session. Process identity is checked before any recorded PID is
signalled. Renderer changes after Codex updates cause verification to fail
closed.

## Reporting

Please report vulnerabilities through GitHub's private vulnerability reporting
for this repository. Do not include API keys, authentication files, private
conversations, or the full contents of `config.toml` in a public issue.
