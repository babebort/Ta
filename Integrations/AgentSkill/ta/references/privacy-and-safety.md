# Privacy and safety

## Capture

After the user grants Ta macOS Screen Recording permission, ordinary silent captures do not require per-shot confirmation. This does not authorize capturing an obviously sensitive target the user did not identify.

Stop and ask before capturing password managers, banking/payment apps, recovery codes, private keys, authentication prompts, private browsing windows, or similarly sensitive content. Respect `TARGET_BLOCKED_BY_PRIVACY_POLICY`; do not bypass the denylist with a display capture.

## Cloud

- `deny`: never upload; a cloud-required operation must fail clearly.
- `auto`: follow the policy and configured model profile in Ta.
- `allow`: use only when cloud processing is within the user's request or standing configuration.

Always read `meta.cloudUploaded` rather than inferring cloud use from the command name. Ta stores provider secrets; neither this skill nor the CLI should request or expose them.

## Clipboard and files

`ta copy` changes the user's clipboard. Use it only when requested or when copying is the explicit deliverable. `ta save` writes a persistent file; use a user-approved destination and avoid overwrite surprises.

## Artifacts and logs

Managed artifacts are temporary local files with expiry and checksum metadata. Do not paste image bytes into prompts or logs. Do not retain OCR text containing secrets. Save a durable copy only when the user asks to keep the result.

## Visible operations

Pinning, interactive selection, annotation UI, and native-app scrolling capture visibly affect the desktop. Silent capture authorization does not automatically authorize mouse/keyboard control. Never move the pointer or send synthetic input through Ta Skill.
