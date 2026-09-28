---
description: macOS workstation with remote 1C platform — execution boundary, MCP endpoints and source synchronization
alwaysApply: false
category: development
---

# Remote 1C platform

Load when `.dev.env` has `PLATFORM_MODE=remote`, before platform / infobase,
configuration repository, web-server, MCP installation/update or scheduled-export work.
Empty or `local` keeps the existing local workflows. Unknown values are errors.

## Execution boundary

The workstation owns the Git checkout, AI client and rules. The remote host owns
1C executables, infobases, server paths and scheduled exports. `INFOBASE_KIND=server`
only selects a connection kind; it does not move a local Designer process to that
server. `PLATFORM_MODE=remote` is a routing policy, not an SSH or deployment client.

- Do not detect or request a local `PLATFORM_PATH`, install 1C locally, launch
  `1cv8.exe` / `ibcmd`, invoke local `db-*` / EPF build/dump / repository operations,
  publish Apache/IIS, or register Windows tasks on the Mac to perform remote work.
- Use an already configured remote execution mechanism only after verifying its
  host, working directory, project/infobase identity and authorization. Run the
  matching operation procedure on that host. Its `.dev.env` describes its own
  local execution environment; never switch the Mac's mode to bypass this boundary.
- If no remote executor is configured, prepare the exact server-side procedure
  and report the operation as unexecuted. Ask for access only when that operation
  is actually needed. Reading and editing local sources can continue.
- MCP capabilities are limited to the tools actually exposed. An HTTP URL or a
  data-query tool does not supply Designer deployment or shell execution.
- `/installfilesupdatescript` targets the Windows host performing the export.
  No local launchd task is needed when both the platform and dump live remotely.
  Server OS must be established before choosing a scheduler.

## MCP endpoints

The installer reads `MCP_URL_<SERVER_ID>` from `.dev.env`: uppercase the server ID
and replace every non-alphanumeric character with `_`. For example,
`1c-code-metadata-mcp` becomes `MCP_URL_1C_CODE_METADATA_MCP`. Values are complete
HTTP(S) endpoints, including the correct port and path; quoted values are accepted.
No embedded credentials or fragments. Keep tokens in the client's supported secret
configuration and retain the deployment's authentication requirements.

Remote mode includes only explicitly configured endpoints, plus `1c-data-mcp`
when `INFOBASE_PUBLISH_URL` is set. It does not silently connect to `localhost` from
the catalogue. An explicit localhost URL is valid for an existing SSH tunnel.
An override for `1c-data-mcp` takes precedence over the publication-derived URL.
External MCP installation mode continues to preserve externally managed configs;
these overrides apply only to installer-managed configurations.

After changing endpoints run the rules installer `update` and restart/reload the
AI client. Respect user-owned config conflicts; do not force-overwrite them.
Confirm exposed tools with their actual schemas. A successful install does not
prove remote connectivity or a live infobase operation.

## Source and path identity

Keep Mac paths, server paths and container paths distinct. Never send `/Users/...`
to a server-side file tool unless that exact mount is verified. Establish the
server's project ID, source revision and path mapping before a file-based check.
Use a documented text-input variant only where that validator permits it; report
its narrower evidence. No path mapping means file-based checks are unverified.

Transfer source changes via the project's agreed Git/synchronization workflow.
Validate the same revision that will be deployed. Pull exported XML from the
server before editing it; do not claim a remote dump updated the Mac checkout.
All existing dev/test, authorization, repository lock, vendor-support, backup
and validation requirements still apply.
