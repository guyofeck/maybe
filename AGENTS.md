# Base44 dev environment notes

- Run: `docker compose -f docker-compose.base44.yml up -d --build`. Uses `.base44/Dockerfile` (runtime-only Ruby image); source is bind-mounted, gems live in the `bundle` volume.
- The one-shot `setup` service runs `bundle install`, `db:prepare`, `tailwindcss:build`, and loads `demo_data:default` only when no users exist (first run takes ~3 min). `web` and `worker` wait for it.
- Demo login: `user@maybe.local` / `password`.
- `SELF_HOSTED=true` is set in compose so the app runs without managed-mode services (Stripe etc.).
- Rails reloads code per request; `web` also runs `tailwindcss:watch[always]` in the background. Gemfile changes: `docker compose -f docker-compose.base44.yml up -d setup && docker compose -f docker-compose.base44.yml restart web worker`.
- Health: `GET /up` (Rails health check). `/` redirects to `/sessions/new` when logged out.
- All external integrations (Synth, OpenAI, Plaid) are optional; nothing is required to boot.
- Tests: `docker compose -f docker-compose.base44.yml exec web bin/rails test` (uses `maybe_test` DB on the same Postgres).
- Transactions CSV uses the same family-scoped search as the list but exports every matching row, ignoring pagination. CSV requests deliberately do not restore or overwrite saved page filters. Exported amounts use the display sign (income positive, expense negative), opposite the stored entry amount. Focused checks: `docker compose -f docker-compose.base44.yml exec -T web bin/rails test test/controllers/transactions_controller_test.rb`.
