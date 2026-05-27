# run-tailscale-funnel

Exposing a local HTTP server at a public `.ts.net` URL via Tailscale Funnel for agent-browser navigation, mobile testing, webhooks, or shared dev demos.

**Category:** platform

## Install

Install this skill individually:

```bash
npx -y skills add -y -g yigitkonur/skills-by-yigitkonur-secondary/skills/run-tailscale-funnel
```

Or install the full pack:

```bash
npx -y skills add -y -g yigitkonur/skills-by-yigitkonur-secondary
```

## Prerequisites

- macOS or Linux with Tailscale installed and logged in to a tailnet
- MagicDNS enabled on the tailnet (`https://login.tailscale.com/admin/dns`)
- For Funnel: HTTPS Certificates enabled and the `funnel` nodeAttr granted in the tailnet ACL (`https://login.tailscale.com/admin/acls`)
- `bash`, `curl`, `dig`, `lsof` available on PATH

The skill verifies these in its preflight and tells the user which one is missing if anything is.
