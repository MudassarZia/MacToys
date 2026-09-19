# Security and privacy

This is an early alpha, not a security-reviewed system utility.

- No analytics, cloud AI, background networking, remote command execution, or key logging.
- Input interception is enabled explicitly, is not persisted across launches, and stops on quit or Control–Option–Escape. macOS Secure Input can prevent interception.
- Screen capture starts only from an explicit action, using a system selection interface. Protected content may be blank. Temporary region files are removed after processing.
- Saved profiles are local JSON with restrictive permissions, not encrypted. Do not use Environment Profiles as a secrets vault.
- Host-file editing is the only administrator operation. It checks for concurrent changes, backs up the file, and requests macOS authentication. It does not install a privileged daemon. Do not approve the prompt unless you intend to apply the displayed edits.
- Renaming never intentionally overwrites destinations, but filesystem operations are not a transaction. Simultaneous external filesystem changes can interfere; inspect reported rollback failures.
- App builds use an ad-hoc local signature unless a signing identity is explicitly supplied. Do not present unsigned/unnotarized artifacts as trusted public releases.

Report vulnerabilities privately using GitHub private vulnerability reporting once the repository owner enables it. Until a repository and private contact are established, do not publish exploit details or sensitive files in public issues.
