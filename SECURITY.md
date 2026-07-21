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

## Reporting

Please report vulnerabilities through GitHub's private vulnerability reporting
for this repository. Do not include API keys, authentication files, private
conversations, or the full contents of `config.toml` in a public issue.
