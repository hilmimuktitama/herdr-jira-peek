# Connection lifecycle plan

The runtime moves backend and account changes through an explicit connection
boundary while keeping the current picker and reader behavior. It is designed
for the optional Jira Cloud REST backend and the default TWG backend.

## Principles

- `twg` remains the default. `rest` is explicit and never falls back to TWG.
- Setup offers an interactive backend choice. It writes a staged candidate
  configuration and activates it only after the selected connection passes its
  read-only validation. Cancelled or failed setup preserves the working config.
- Noninteractive setup reports readiness and leaves activation to the existing
  config workflow; it never prompts for or stores tokens.
- TWG OAuth remains in TWG-managed storage. REST credentials remain in an
  external mode-400/600 netrc file referenced by an absolute path.
- Revocation and permission changes are checked at setup and request
  boundaries. The plugin does not continuously poll Atlassian.

## Connection identity and cache boundary

At runtime, the connection ID includes the project allowlist and the selected
backend and target. Layout and TTL edits preserve the connection identity:

- REST: backend, `JIRA_BASE`/`JIRA_CLOUD_ID`, and a hash of the netrc file
  contents (the hash is never displayed or persisted as credential material).
- TWG: backend, `JIRA_BASE`/`JIRA_SITE`, and the authenticated account identity returned by
  a read-only TWG identity check.

The first runtime discards unscoped legacy cache entries safely. The current
cache remains flat, with the hashed connection marker and epoch governing reuse;
when account, site, backend, or credentials change, the flat cache is purged.
A positive TTL still means cached content may remain available until expiry or
an explicit clear; clearing the cache bumps the connection epoch even when
authentication is unavailable.

## Viewer and request lifecycle

Each viewer receives `VIEWER_CONNECTION_ID` and a connection epoch when it is
opened. A local UI timer catches config, REST netrc, and epoch changes; TWG
account changes are checked by `whoami` at the next request. Workers and callbacks capture both values. Metadata publication,
detail publication, and fzf refresh actions must be discarded when either value
no longer matches the active connection. Changing backend or credentials
therefore requires closing and reopening viewers, and old workers cannot publish
responses into the new connection.

## Acceptance scenario matrix

| Scenario | Expected result |
| --- | --- |
| First setup, choose TWG, valid OAuth | Candidate config activates; setup reports ready; doctor confirms site access. |
| First setup, choose REST, valid netrc and endpoint | Candidate config activates; no TWG command runs; doctor confirms REST identity/connectivity. |
| Cancel backend selection | Existing config remains byte-for-byte unchanged. |
| Candidate backend has missing curl, netrc, or OAuth | Candidate config is not activated; existing working config remains usable. |
| Noninteractive setup | No prompt and no token handling; reports readiness or actionable failure. |
| Switch TWG account/site or REST netrc/cloud ID | New connection ID and epoch isolate cache; old viewer callbacks are ignored. |
| Revoke credentials while a positive-TTL cache exists | Cached content may render until TTL/clear; next network request fails with a fixed diagnostic. |
| Revoke credentials before `clear-cache` | Cache clear still succeeds without authentication and bumps epoch. |
| Old worker finishes after a switch | Response is discarded because connection ID/epoch is stale. |
| Malformed/wrong-key REST response or an empty nonfinal comment page | No cache publication; fixed safe error; no fallback to TWG. |

## Delivery order

1. Add fictional offline fixtures for setup cancellation/failure, cache
   isolation, stale callbacks, revoked credentials, and malformed REST output.
2. Keep the setup, troubleshooting, and retention documentation aligned with
   the shipped lifecycle behavior.
