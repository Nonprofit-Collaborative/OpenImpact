# Contributor environment

## Tool versions used to build this scaffold

- Salesforce CLI (`sf`) 2.150.6
- Salesforce Code Analyzer plugin 5.16.0
- `@salesforce/sfdx-plugin-lwc-test` 1.2.1
- Node v22.22.2 (npm 10.9.7)
- git 2.43.0
- OpenJDK 21.0.10 (needed by PMD, which the Code Analyzer runs)
- Python 3.11.15

## Requirements

- **Node**: use the current Node LTS line (22.x at the time of writing; check
  [nodejs.org](https://nodejs.org) for the active LTS before installing). Older LTS lines may
  work but are not tested.
- **Java 11 or newer**: required for PMD, which `sf code-analyzer` runs as part of the rule
  engine. Java 21 (as installed here) is fine; anything 11+ works.

## Install

```bash
npm install -g @salesforce/cli
sf plugins install code-analyzer
npm install
```

`npm install` pulls the devDependencies pinned in `package.json` (ESLint, Prettier,
`@salesforce/sfdx-lwc-jest`, husky, lint-staged, and their Salesforce-specific plugins) and
produces `package-lock.json`.

## Verify the toolchain

```bash
npm run lint
npm run test:unit
npm run prettier:verify
npm run check:namespace
npm run check:standard-objects
```

All five should pass with a clean checkout, even before any package has real metadata: `lint`
and `test:unit` pass with zero LWC components, and the two `check:*` scripts pass on an empty
`packages/` tree.

## A note on `config/scratch-defs/person-accounts.json`

The product plan's repository layout (Section 4.3) lists this file as `npc.json`. Per Brandon's
instruction, it is named `person-accounts.json` in this repository instead: the file name says
what the org shape verifies (Person Accounts enabled) rather than a product-name shorthand.
