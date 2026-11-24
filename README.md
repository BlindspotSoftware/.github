# Shared workflows

`hygiene` fails a push or pull request on:

- a secret in the tree or in the pushed commits, found by [gitleaks](https://github.com/gitleaks/gitleaks)
- a name or host from the `LEAK_DENYLIST` org secret in a tracked file. A hit prints as `path:line`, never with the name
- a commit without a `Signed-off-by` line for its author ([DCO](https://developercertificate.org/)). Bot commits need none

## Use it

Add `.github/workflows/hygiene.yml` to a repo:

```yaml
name: hygiene
on: [push, pull_request]
jobs:
  hygiene:
    uses: BlindspotSoftware/.github/.github/workflows/hygiene.yml@main
    secrets: inherit
```

Pull requests from forks get no secrets, so they skip the denylist; the next push to the default branch checks it.

## When it fails

- A test key or fixture that gitleaks flags: add its fingerprint from the log to `.gitleaksignore`, or a path to an allowlist in `.gitleaks.toml`, both in the repo root.
- A denylisted name: remove it from the file. The list lives only in the org secret, never in a repo.
- A missing sign-off: `git commit --amend --signoff`, or `git rebase --signoff <base>` for several commits.

## Change it

`scripts/` holds the checks. `scripts/selftest.sh` runs them against throwaway repos, on every pull request here.
