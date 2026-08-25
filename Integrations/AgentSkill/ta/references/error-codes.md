# Error handling

Read the structured `error.code`, `message`, `hint`, and `retryable` fields. Do not parse localized prose.

| Code | Action |
|---|---|
| `TA_APP_NOT_INSTALLED` | Stop. Explain that Ta must be installed; do not loop. |
| `BRIDGE_UNAVAILABLE` | The CLI already attempts one non-activating launch. Retry manually at most once. |
| `PROTOCOL_VERSION_MISMATCH` | Stop and request compatible App/CLI versions. |
| `SCREEN_PERMISSION_REQUIRED` | Stop and direct the user to Ta Settings → Permissions. Do not retry until permission changes. |
| `ACCESSIBILITY_PERMISSION_REQUIRED` | Stop; this is expected for input-affecting or scrolling workflows, not ordinary capture. |
| `TARGET_NOT_FOUND` | Re-list windows/displays and retry once only when the target is still unambiguous. |
| `TARGET_CHANGED` | Refresh the target and retry once. |
| `TARGET_BLOCKED_BY_PRIVACY_POLICY` | Stop. Do not switch to display capture to evade the policy. |
| `CAPTURE_BUSY` | Wait briefly and retry once if the original task is still active. |
| `OCR_ENGINE_UNAVAILABLE` | Report the unavailable engine; use another configured local engine when permitted. |
| `MODEL_PROFILE_NOT_CONFIGURED` | Stop and ask the user to configure the model in Ta. Never ask for the API key in chat. |
| `CLOUD_UPLOAD_NOT_ALLOWED` | Stop or fall back to a genuinely local operation. Never change `deny` to `allow`. |
| `USER_ACTIVITY_DETECTED` | Stop or wait; do not fight the user for control. |
| `ARTIFACT_EXPIRED` | Re-run the source operation if still authorized. |
| `CANCELLED` | Treat as cancelled; do not automatically restart. |

If the shell cannot find `ta`, distinguish that from `TA_APP_NOT_INSTALLED`: the CLI itself is missing from `PATH`. Ask the user to install or expose the CLI.

Expected fixture behavior:

- No Ta app: installation guidance, no repeated launch.
- Permission missing: permission guidance, no retry.
- Healthy bridge: proceed and validate `ok` plus artifacts/data.
- Cloud denied: stay local or report that the requested model operation is unavailable.
