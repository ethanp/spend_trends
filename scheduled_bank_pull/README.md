# Scheduled bank pull

The home server pulls SimpleFIN every day at 06:00, so transactions are
already on the phone even when the Mac app has not been opened.

It is the Banks tab's "Pull bank transactions", run headless: a Flutter test
binding with no window (like the workbench daemon) hosts
`lib/scheduled/scheduled_bank_pull.dart`, which is its own PowerSync client.
Each run downloads first (so it sees the same last successful pull as the
apps), pulls, runs the categorization rules, and exits once every change has
uploaded through PostgREST.

| Piece | Where |
|---|---|
| Entry point | `tool/scheduled_bank_pull_harness.dart` |
| Image | `Dockerfile` (built from the server's `~/Flutter`) |
| Compose service | `spend-trends-bank-pull` in `infra/docker-compose.yml`, `jobs` profile |
| Local SQLite | Docker volume `spend_trends_bank_pull_data` |
| Schedule | `systemd/spend-trends-bank-pull.timer` (user unit, `Persistent=true`) |
| Secrets | `spend_trends/.env` (`SIMPLEFIN_ACCESS_URL`, `POWERSYNC_JWT_SECRET`) and `ethan_sync/home_server.env`, mounted read-only at run time |

## Deploy

After `infra/deploy.sh`, from the workspace:

```bash
Flutter/spend_trends/scheduled_bank_pull/deploy.sh        # ship code, env, timer
Flutter/spend_trends/scheduled_bank_pull/deploy.sh --run  # and pull now
```

Re-run it after changing the pull code; the next run rebuilds the image.

## On the server

```bash
systemctl --user list-timers spend-trends-bank-pull.timer
systemctl --user start spend-trends-bank-pull.service   # pull now
journalctl --user -u spend-trends-bank-pull.service -n 100
```
