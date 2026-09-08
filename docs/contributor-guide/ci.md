# Continuous integration

This page explains what `.github/workflows/ci.yml` does, how the one long lived test org it
deploys into is configured, and how to sign off commits under the project's DCO policy.

It used to say the workflow tests four org shapes. It does not, and has not since the org
tests moved to a single long lived org: there is no shape matrix, so exactly one shape is
exercised, whichever the test org was created from. Testing a second shape means a second
org and a second secret.

## Jobs

### `static`

Runs on every pull request and push to `main`, and on manual `workflow_dispatch`. No
Salesforce org is needed for this job. Steps:

1. `npm ci`
2. `npm run prettier:verify`
3. `npm run lint`
4. `npm run test:unit:coverage`
5. `scripts/ci/check-namespace.sh`, failing the build if a hard-coded namespace prefix
   appears in source.
6. `scripts/ci/check-standard-objects.sh`, failing the build if a standard Salesforce
   object is referenced outside `packages/connect`.
7. `scripts/ci/check-custom-metadata.py`, failing the build if a shipped custom metadata
   record names a field its type does not define. Such a record refuses the whole
   deployment, and nothing else in the suite sees it: the offline Apex compiler does not
   read custom metadata records.
8. `scripts/ci/check-symlinks.sh`, failing the build if a tracked file is a symlink
   pointing outside the repository or at an absolute path. Such a link resolves on the
   machine that committed it and dangles everywhere else, so every local check passes and
   CI fails. This ran because a stray `.tools` symlink, left in an agent worktree and swept
   in by `git add -A`, broke the offline Apex compile check on `main`.
9. `scripts/ci/check-permission-sets.py`, failing the build if a packaged permission set
   grants access to a class, tab, app, custom permission, object, record type or field that
   the repository does not ship, or a permission set group contains a set that is not there. A dangling grant refuses the whole deployment, and the
   permission sets are assembled by hand at every merge from each branch's integration
   file, so the reference and the metadata can drift apart silently. This ran because
   `Nonprofit_Admin` granted a `Household_Member__c` tab that was never created.
10. `scripts/ci/check-canonical-model.py`, failing the build if a shipped object or field
   is missing from `docs/architecture/canonical-model.md`. The canonical model is updated
   before an object or a field is added, so this is the gate that keeps it true.
11. A grep check that fails the build if any tracked file contains an em dash character.
12. Installs the Salesforce CLI and the `code-analyzer` plugin, then runs
   `sf code-analyzer run --workspace packages --rule-selector Recommended --severity-threshold 2`.
   The results are uploaded as a build artifact (`code-analyzer-results.html` and
   `code-analyzer-results.json`) even if the job fails, so anyone can download and read
   them from the workflow run page.

If `packages/` has no Apex or JavaScript yet, Code Analyzer may report nothing to scan.
That is expected in the early scaffold and is not a failure.

### Run the same checks locally, before you push

Every gate above except the org tests runs on a laptop, and all of them are fast:

```
npm run prettier:verify
npm run lint
npm run test:unit
npm run check:namespace
npm run check:standard-objects
npm run check:custom-metadata
npm run check:symlinks
npm run check:permission-sets
npm run check:canonical-model
npm run check:apex
npm run check:analyzer
```

`check:analyzer` is the one most easily forgotten, because it is the slowest and needs the
Salesforce CLI with the `code-analyzer` plugin. It is also the one that enforces a
non-negotiable: zero high or critical findings before merge. Skipping it locally means
finding out from a red build.

## Connecting a Dev Hub

Until a Dev Hub is connected, the `org-tests` job skips every shape and no Apex test has
ever been executed. This is the setup, once, by someone with administrator access to the org
being used as the Dev Hub.

A Dev Hub is not special. Any Salesforce org can be one, including a free Developer Edition,
and its edition does not constrain the scratch orgs it creates. Use a development org, never a
production org holding real constituent data: the credential below grants full API access to
whatever org it names.

1. **Enable Dev Hub in the org.** Setup, then Quick Find, then Dev Hub, then switch Enable Dev
   Hub on. The switch cannot be turned off again, which is why this belongs in a development
   org. Nothing else on that page is needed yet: second generation packaging stays off until
   the namespace question is settled (plan Section 4.3).
2. **Install the Salesforce CLI locally**, if it is not already there: `npm install -g @salesforce/cli`, then `sf --version`.
3. **Log in to the org and mark it the default Dev Hub.** `sf org login web --alias devhub --set-default-dev-hub` opens a browser; sign in as the administrator of that org.
4. **Check it took.** `sf org list` shows `devhub` with a Dev Hub marker. `sf org display --target-org devhub` shows the username and instance you expect.
5. **Prove it can create a scratch org before involving continuous integration.** `scripts/org/create-scratch-org.sh platform-only smoke --days 1` creates the org, deploys Core and assigns the permission sets. If that fails, fix it here rather than in a build log. Delete it with `scripts/org/delete-scratch-org.sh smoke`.
6. **Read out the authentication URL.** `sf org display --target-org devhub --verbose --json` prints a `sfdxAuthUrl` field. **That string is a credential**: it carries a refresh token and anyone holding it has API access to the org. Do not paste it into a commit, an issue, or a chat window.
7. **Store it as a repository secret.** In GitHub: Settings, then Secrets and variables, then Actions, then New repository secret. Name it exactly `SF_DEVHUB_AUTH_URL` and paste the value from step 6.
8. **Create the test org and store its secret**, which is the next section. The Dev Hub alone does not run any test: it is what lets you create the org that does. Expect failures on the first run that reaches the Apex tests: several hundred have been written and none has ever executed.

To rotate or revoke, re-run steps 3 and 6 and replace the secret, or revoke the connected app
session in the org under Setup, Connected Apps OAuth Usage.

### The test org is one long lived org, not a new one per run

`org-tests` deploys into a single org named by the `SF_TEST_ORG_AUTH_URL` secret. It does not
create or delete anything. If the secret is unset the job skips with a warning and no Apex
test runs.

That is a deliberate trade, and it is worth being clear about what it costs. A fresh scratch
org per run is a clean room: what passes, passes against exactly what this repository
contains. A long lived org accumulates. Deleted metadata is not removed by a deploy, so a
class or field you deleted here still exists there; a test can pass because of something left
behind by an earlier run. When a result looks surprising, recreating the org is the first
thing to try, not the last.

Two consequences follow.

**It expires, and then every run fails at login.** The org is a scratch org, and Salesforce
caps those at 30 days. Every run prints the days remaining and warns from a week out;
`scripts/org/check-org-expiry.sh` does that and never fails a build on its own. Refreshing the
org means replacing the secret, because a new org has new credentials.

**One org means one shape.** The four shape definitions still exist and still matter, but this
job exercises whichever shape the org was created from. Use `person-accounts` unless you have
a reason not to: it is the closest an ordinary Dev Hub gets to the Agentforce Nonprofit orgs
the first customers run. Testing a second shape means a second org and a second secret.

### Creating the test org and connecting it

Do this on your own machine, after the Dev Hub steps above.

1. **Create it**, 30 days, from the shape you want to test:
   `scripts/org/create-scratch-org.sh person-accounts dev --days 30 --replace`
   This deploys Core, assigns the permission sets and seeds the sample data. Note the expiry
   date it prints.
2. **Read out its auth URL:** `sf org display --target-org dev --verbose --json`, and take the
   `sfdxAuthUrl` field. This is a credential, exactly like the Dev Hub one.
3. **Store it** as the repository secret `SF_TEST_ORG_AUTH_URL`.
4. **Push anything.** `org-tests` deploys both packages into that org and runs the Apex tests.
5. **Check the shape it reports.** The run prints what shape the org actually is, read from
   the org itself, before it deploys anything. Confirm it says the shape you meant to create.
   Nothing else in this repository records which definition the org came from, so that line
   in the build log is the record.

Refreshing it monthly is the same three commands: re-run step 1 with `--replace`, then redo
steps 2 and 3 with the new auth URL. Anything typed into the org by hand is lost at that
point, which is the discipline the package needs anyway: what matters belongs in this
repository.

### `org-tests`

Runs after `static` succeeds, against the one long lived org described above. It
authenticates from `SF_TEST_ORG_AUTH_URL`, prints how many days that org has left, prints
which shape the org actually is (`scripts/org/report-org-shape.sh`, which asks the org for
the same five facts `OrgShapeDetector` reads, through the Tooling API so it works before the
packages deploy), deploys
`packages/core` and then `packages/giving`, runs the Apex tests, and uploads the results. It
creates nothing and deletes nothing.

The deploy goes in stages through `scripts/org/deploy-packages.sh`: the vendored rollup
engine, then Core, then Giving. A failed stage asks the org for the component level report,
by job id, in human form and then as JSON.

That is not tidiness. The first deploy this project ever attempted sent all 982 components in
one request and came back with `UNKNOWN_EXCEPTION`, zero components deployed, zero component
errors, and a Salesforce ErrorId. A failure with nothing attached to it tells you nothing
about which of 982 things caused it. In stages, the same failure names a stage. The order also
matches how the packages depend on each other: the vendored engine is self contained, Core
does not call it yet, and Giving depends on Core.

An `UNKNOWN_EXCEPTION` with zero component errors is a Salesforce side failure rather than
something wrong with a component. Quote the ErrorId to Salesforce support.

**It is not transient here, whatever the general advice says.** This failure has now come back
four times across four separate runs, always on the Core stage, always with zero components
deployed and zero component errors, and always with the same trailing code in the ErrorId
(`-315522575`) behind a different leading number each time. Four identical failures is a
deterministic fault, so re-running costs a build and proves nothing. `scripts/org/deploy-packages.sh`
still prints the "sometimes transient" line; that advice was written before the fourth run.

Two things constrain when it runs, both because there is one org rather than one per run.

It runs **on a push to `main`, or on a manual run** from the Actions tab (Run workflow), which
is how to retry after changing a secret without inventing a commit to do it. Deploying a pull request's code into the test org would
leave that org holding unmerged work, and the next run against main would inherit it. Pull
requests get the static checks, which is where most of the signal is.

It carries a **single global concurrency group**, `org-tests-persistent`, so two runs never
deploy at once, and `cancel-in-progress` is **false**. Cancelling a deploy partway through
would leave the org holding half a package, and unlike a scratch org that is thrown away, that
state persists into the next run. Runs queue instead; GitHub keeps only the newest waiting one.

The first version of this got the second point wrong: a global group with cancel-in-progress
set to true meant an unrelated Dependabot run cancelled main's job after every step had
already passed, which showed up as a cancelled build on a commit that was fine.

### `dco`

Checks that every commit being merged (or every pushed commit, on a push to `main`) has
a `Signed-off-by:` trailer. See "Signing off commits" below.

## Offline Apex checking

`scripts/ci/check-apex-offline.sh` gives feature agents compile-level feedback on Apex
without needing a scratch org or Dev Hub. It is not yet wired into `.github/workflows/ci.yml`.

It runs `CheckForIssues` from `apex-ls` (the nawforce/apex-dev-tools Apex language
server, `io.github.apex-dev-tools:apex-ls` on Maven Central) against the whole
`packages/` tree, using the repo's root `sfdx-project.json`. On first run it resolves the
jar and its dependencies from Maven Central via Maven and caches them under `.tools/`
(gitignored); later runs reuse the cache and need no network access. Requires Java 21+
and, for the first run only, Maven, both already present in the standard dev and CI
environment.

Run it from anywhere in the repo:

```
scripts/ci/check-apex-offline.sh
```

It exits non-zero if any errors are found, and prints each error with file, line, and
column. What it catches:

- Syntax errors.
- Type errors (incompatible assignment, incompatible return type, wrong argument types,
  and similar).
- References to unknown classes, methods, and variables.

What it does not catch:

- Unknown fields in SOQL queries (for example `[SELECT Missing__c FROM Thing__c]` where
  `Missing__c` does not exist passes with no error). Field-level SOQL validation still
  needs an org, for example through `sf code-analyzer` at deploy time or an actual
  deploy to a scratch org.
- Anything that is only enforced at runtime (CRUD/FLS, governor limits, trigger order of
  execution, and so on).

## Detection-only exemptions

`scripts/ci/check-standard-objects.sh` fails the build when Core, Giving, Volunteers,
Programs, or Funders names a standard object the Platform-license floor does not have
(Opportunity, Campaign, Lead, Case), a Person Account field, or an Industries object
(ADR-0009, ADR-0013).

Detecting that one of those exists is not the same as depending on it. Core has to tell an
administrator what is installed in their org: that is the Health Check (plan Section 4.8),
and it is how the coexistence mode is recommended (plan Section 4.5). Detection is done
with `Schema.getGlobalDescribe()` and field maps, against names held in String constants,
so nothing is bound at compile time and Core still deploys on an org where those objects
are absent. The grep cannot tell the difference, so it is told explicitly.

An Apex line (`*.cls` or `*.trigger`) carrying the comment

```
// detection-only: <reason>
```

is exempt from the check. Rules:

- The marker works only in Apex, and only on the line it is written on.
- Use it on constant declarations. A constant is inert; an expression is not.
- The reason is written for a reviewer, not for the script. Say what the constant detects
  and what reads it.
- Every exempted line is printed on every run, under the heading "Detection-only
  exemptions", whether the check passes or fails. The list is meant to be read: if it grows,
  something is wrong.
- The marker does not make a compile-time reference legal. `Opportunity.Name` with the
  marker appended still stops Core deploying on a Platform-only org, and no CI check will
  catch it before the org shape matrix does.

As of v0.1 the marker appears on four constant declarations in `OrgShapeDetector` (the NPSP
namespace prefix, the Person Account indicator field, the Industries gift object, and the
standard Sales Cloud object) and nowhere else. Three of the four are printed as exemptions:
the NPSP prefix is not a name the grep looks for, and carries the marker only so that the
four detection constants read alike.

## What happens when the secrets are missing

The `org-tests` job checks for the secret first. If it is empty, every org-dependent
step is skipped and the job posts a `::warning::` explaining why, instead of failing.
`static` (lint, unit tests, Code Analyzer, namespace and standard-object checks) still
runs and still gates merges regardless of whether the secret is set. This means a fork
without access to the secret can still open a pull request and get useful signal; only the
live org work is skipped.

Two secrets are involved and they do different jobs. `SF_DEVHUB_AUTH_URL` lets a machine
create scratch orgs; nothing in continuous integration uses it now that the test org is long
lived, and it is kept because creating and refreshing that org needs it.
`SF_TEST_ORG_AUTH_URL` names the org the tests actually run in, and is the one `org-tests`
requires.

## Setting the `SF_DEVHUB_AUTH_URL` secret

This secret holds a Salesforce SFDX auth URL for the Dev Hub the `org-tests` job uses to
spin up scratch orgs. Only repository maintainers with a Dev Hub-enabled org should set
this.

1. Authenticate to the Dev Hub locally:

   ```
   sf org login web --alias devhub
   ```

2. Get its auth URL:

   ```
   sf org display --target-org devhub --verbose --json
   ```

   Copy the `result.sfdxAuthUrl` value from the JSON output. Treat this value as a
   credential: it grants access to the Dev Hub. Do not paste it into a file that gets
   committed, and do not paste it into chat, an issue, or a pull request.

3. In the GitHub repository, go to **Settings > Secrets and variables > Actions > New
   repository secret**. Name it `SF_DEVHUB_AUTH_URL` and paste the auth URL as the
   value.

The workflow writes this secret to a temporary file only inside the CI runner, uses it
once with `sf org login sfdx-url --sfdx-url-file`, and deletes the file immediately
afterward. The auth URL itself is never written to any file that is committed or
uploaded as an artifact.

## Reading Code Analyzer results

Every `static` run uploads a `code-analyzer-results` artifact containing:

- `code-analyzer-results.html`: a readable report, open it in a browser.
- `code-analyzer-results.json`: the same findings in machine-readable form.

Download the artifact from the workflow run's Summary page under **Artifacts**. Each
finding lists a severity (1 Critical through 5 Info), the rule, the file and line, and a
description.

### Severity threshold policy

The `static` job runs Code Analyzer with `--severity-threshold 2`, meaning the command
(and the job) fails if any finding is severity 1 (Critical) or 2 (High). Lower-severity
findings are reported but do not fail the build. The policy is zero high or critical
findings on every pull request; do not raise the threshold to make a build pass, fix the
finding or, if it is a false positive, suppress that specific rule with a documented
reason.

## Signing off commits (DCO)

Open Impact uses the Developer Certificate of Origin instead of a CLA. Every commit must
carry a `Signed-off-by:` trailer with your name and email, certifying you have the right
to submit the change under the project's license.

Sign off a single commit:

```
git commit -s -m "Your commit message"
```

Sign off every commit on an existing branch that is missing the trailer:

```
git rebase --signoff main
git push --force-with-lease
```

Git has no built-in setting that adds the trailer to every `git commit` automatically,
but you can get the same effect with a local alias so you never have to remember the
flag:

```
git config --global alias.ci "commit -s"
```

Then use `git ci` instead of `git commit`. If you prefer, a `prepare-commit-msg` hook
that appends the trailer works too; either is fine as long as every commit ends up
signed off before it reaches CI.

The `dco` CI job checks every commit in a pull request (or every pushed commit, on a
push to `main`) for the trailer and fails with a list of offending commits and a fix
hint if any are missing.
