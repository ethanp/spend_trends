# Pulling transactions from Empower

Empower (the Personal Dashboard, formerly Personal Capital) is the only
source for some history: 401(k) and HSA contributions, accounts SimpleFIN
can't reach, and years before this app existed. There is no public API, so
the pull reads Empower's own web API from a signed-in dashboard tab and hands
the saved response to the app's agent API.

Nothing from an export belongs in git. The app copies each export into
`~/Library/Application Support/com.ethan.spend_trends/imports/empower/` and
keeps the Empower → app account mapping there too; `.gitignore` blocks
`empower_*.json` and `*transactions_*.json` in this repo as a backstop.

## 1. Sign in (the user)

Use the user's **Chrome** through Claude in Chrome; the built-in browser pane
loads the dashboard slowly and its session dropped mid-pull. The user signs
in; an agent never types Empower credentials.

## 2. Let the dashboard make the first request

Do **not** call `pc-api.empower-retirement.com/api/login/querySession`
yourself. It issues a new session token and Empower then answers every call,
including the dashboard's, with "Session is no longer valid", which means a
fresh sign-in.

Instead, in the signed-in tab:

1. Install a recorder that keeps the URL and body of each XHR/fetch to
   `pc-api…/api/` in `window.__capturedBodies` (wrap
   `XMLHttpRequest.prototype.open/send` and `window.fetch`).
2. Set `location.hash = '#/all-transactions'` and wait a few seconds. The
   dashboard posts `transaction/getUserTransactions` with `userAccountIds`,
   `startDate`, `endDate`, `lastServerChangeId`, `csrf`, `apiClient`.
3. Re-send that captured body with `startDate` set to `2015-01-01` and
   `endDate` to today. Keep the response in `window`; read back only counts
   and the rows you need to inspect (the full response is ~14 MB).

Other dashboard calls work the same way with the captured `csrf`, e.g.
`invest/getHoldings` with `userAccountIds=[<id>]`, which is how to check
share counts against contributions.

## 3. Save the response (ask first)

Saving is a download: ask the user, naming the file, source, and size. Then
build a Blob from `JSON.stringify(response)` in the tab and click a
temporary `<a download="empower_transactions_<yyyy-mm-dd>.json">`. It lands
in `~/Downloads`.

## 4. Import through the app

```bash
cd Flutter/spend_trends
scripts/agent_api GET /imports/empower            # saved exports + mapping
scripts/agent_api POST /imports/empower '{
  "file": "~/Downloads/empower_transactions_<yyyy-mm-dd>.json",
  "accounts": {"<empowerUserAccountId>": {"accountId": "<appAccountId>", "label": "401(k) contribution"}},
  "dryRun": true
}'
```

- `file` is copied into the app's folder; later calls can omit it to use
  the newest saved export.
- `accounts` maps Empower's `userAccountId` (in each row of the response) to
  an app account and the description label the categorization rules match
  (`401(k) contribution`, `HSA contribution`). The mapping is remembered
  once an import is applied, so later pulls need only `file`.
- `transactionTypes` defaults to contribution types. Buys, dividend
  reinvestment, and share moves inside the account are not cash flow.

Read the dry run before applying:

- `insert`: rows no source has. `insertByAccount` totals them; reconcile
  against what you expect.
- `rekeyEarlierImport`: rows from an older Empower import under another id
  scheme; they take Empower's ids (`empower:<userTransactionId>`), nothing
  is duplicated.
- `recordedByOtherSource`: rows the live bank feed already has (same amount
  within 2 days); left alone.
- `unmatchedEarlierImports`: earlier Empower rows no longer in Empower's
  data. Reported, never deleted; investigate before doing anything.

Then repeat the call without `dryRun`. A second dry run should report
`insert: 0`.

## Things that went wrong once

- **Paired contributions are real.** Sunrun 401(k) shows two identical
  "Employee contribution" rows per paycheck (same fund, amount, price,
  shares, consecutive ids). Current holdings only match when both count, so
  never dedupe them. `GET /duplicates` only treats same-account repeats as
  duplicates when a Copilot import is involved.
- **Check the running code before a destructive call.** After a hot reload
  or restart, confirm the run log says `Reloaded …`/`Restarted …` without
  errors before calling anything that deletes or rewrites rows; a failed
  reload leaves the old code serving the API.
- **HSA Cash and HSA Investment** both list the same contribution; map only
  HSA Investment.
- **Bank pulls skip Empower-recorded rows.** The Sunrun 401(k) is also a
  live SimpleFIN account. A SimpleFIN pull, full history included, no
  longer inserts a row an Empower import already recorded on that account
  (same amount within 2 days, one row per row, so pairs survive). Before
  that fix, a full-history pull re-added 24 feed copies of imported
  contributions.
- **SimpleFIN rate-limits full-history pulls.** A 429 now ends the pull with
  the newer windows kept and a `rateLimited` warning; the rules still run
  over what was written. Retry later for the older history.
