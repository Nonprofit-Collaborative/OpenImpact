# Continuous integration

This page explains what `.github/workflows/ci.yml` does, the four org shapes it tests
against, how to configure the Dev Hub secret, and how to sign off commits under the
project's DCO policy.

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
7. A grep check that fails the build if any tracked file contains an em dash character.
8. Installs the Salesforce CLI and the `code-analyzer` plugin, then runs
   `sf code-analyzer run --workspace packages --rule-selector Recommended --severity-threshold 2`.
   The results are uploaded as a build artifact (`code-analyzer-results.html` and
   `code-analyzer-results.json`) even if the job fails, so anyone can download and read
   them from the workflow run page.

If `packages/` has no Apex or JavaScript yet, Code Analyzer may report nothing to scan.
That is expected in the early scaffold and is not a failure.

### `org-tests`

Runs after `static` succeeds, as a matrix over four org shapes:

- **platform-only**: no Sales Cloud or Service Cloud license features, no NPSP. Proves
  Core (and Connect's dynamic Apex) work with nothing else installed.
- **sales-cloud**: standard Sales Cloud objects available (Account, Opportunity, and so
  on), no NPSP.
- **npsp**: Sales Cloud plus NPSP installed, simulating an org migrating from NPSP.
- **person-accounts**: Person Accounts enabled, simulating the Agentforce Nonprofit /
  Nonprofit Cloud shape.

For each shape, the job authenticates to the Dev Hub, runs
`scripts/org/create-scratch-org.sh <shape> ci-<shape>-<run id> --days 1 --no-sample-data`,
runs Apex tests if any `@IsTest` classes exist under `packages/core`, uploads the test
results, and always deletes the scratch org afterward.

Each shape's job also carries its own concurrency group
(`org-tests-<shape>-<ref>`), so pushing new commits to the same branch cancels
in-flight runs for that shape instead of piling up scratch orgs.

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

## What happens when `SF_DEVHUB_AUTH_URL` is missing

The `org-tests` job checks for the secret first. If it is empty, every org-dependent
step is skipped and the job posts a `::warning::` explaining why, instead of failing.
`static` (lint, unit tests, Code Analyzer, namespace and standard-object checks) still
runs and still gates merges regardless of whether the secret is set. This means a fork
without access to the Dev Hub secret can still open a pull request and get useful
signal; only the live-org matrix is skipped.

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
