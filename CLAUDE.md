# CLAUDE.md

## What this actually is

Despite the README's `mix phx.new`-boilerplate look, this is not a bare
scaffold. Atrium (GitHub: alldoq/theatrium) is a multi-tenant intranet /
company-portal platform, ~230 commits deep, built on Phoenix 1.8.
Multi-tenancy is schema-per-tenant via `triplex`. Contexts under
`lib/atrium/` beyond Phoenix defaults: accounts (local + OIDC/SAML
federated auth via assent/samly), authorization (tenant-scoped groups,
section/subsection ACLs), audit (event log, redaction, retention sweep),
documents (envelope-encrypted files via cloak/cloak_ecto), forms builder,
events/calendar, learning & development (with SCORM package support),
community posts, customer contact book, projects, notifications, global
search, home/announcements, and separate super-admin and tenant-admin
consoles. There's also an AI chat widget (`lib/atrium/ai.ex`) currently
wired to an OpenAI-compatible Ollama endpoint, not Claude.

`docs/superpowers/plans/` and `docs/superpowers/specs/` hold the
phase-by-phase implementation plans and design docs; check there first
for the intent behind a given context. `docs/brand-instance-setup.md`
covers spinning up a new branded tenant.

## Deployment

Deployed to theatrium.online on a shared VPS (also hosts
clarence.alldoq.com), isolated under `/home/user/atrium`, port 4100.
Deploy via `bin/deploy_remote_production deploy` / `rollback`. Full
one-time setup and required env vars (DATABASE_URL, SECRET_KEY_BASE,
ATRIUM_CLOAK_KEY, ATRIUM_FILE_ENCRYPTION_KEY, ATRIUM_UPLOADS_ROOT) are in
README.md.

## Conventions (apply across all projects)

- No em dashes or en-dash ranges in generated text.
- No "X, not Y" / "not just A, it's B" antithesis constructions.
- No fabricated compliance/legal claims in generated copy.
- Avoid the generic AI-made look (warm-cream+serif+terracotta, badge icon
  rows, emoji-as-icons, three-feature-card layouts). Default to
  minimal/monochrome unless the project has established its own brand.
  Run the unslop-ui skill for any UI/design work.
- Treat the production host and database as read-only by default: no
  stop/restart/redeploy of shared services, no force-push, no data
  deletion, unless explicitly instructed in the current conversation.
  Before any destructive or hard-to-reverse operation, list what's
  affected and wait for confirmation.
- Never paste API keys, passwords, or tokens into chat; reference where
  they live instead.
- No AI attribution or co-author lines in git commit messages.
- Long-running operations should run in the background with proactive
  progress updates, not repeated manual status checks.
