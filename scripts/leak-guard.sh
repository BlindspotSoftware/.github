#!/usr/bin/env bash
# Run in a git checkout. Fails on secrets in the tree or in the commits of $1 (base..head, may be
# empty), and on any line of LEAK_DENYLIST in a tracked file. A denylist hit prints as path:line,
# never with the matched text. A line that says denylist:allow is let through.
set -uo pipefail

range=${1:-}
gitleaks=${GITLEAKS:-gitleaks}
denylist=${LEAK_DENYLIST:-}
failed=0

"$gitleaks" dir . --verbose --redact --no-banner || failed=1

if [ -n "$range" ]; then
  "$gitleaks" git . --log-opts="$range" --verbose --redact --no-banner || failed=1
fi

if [ "${LEAK_GUARD_FORK_PR:-false}" = true ]; then
  echo "::notice::A pull request from a fork gets no secrets, so the next push to the default branch checks the denylist."
elif [ -z "${denylist//[[:space:]]/}" ]; then
  echo "::error::LEAK_DENYLIST is empty"
  failed=1
else
  list=$(mktemp)
  trap 'rm -f "$list"' EXIT
  printf '%s\n' "$denylist" | sed '/^[[:space:]]*$/d' > "$list"

  hits=$(git grep -i -I -n -F -f "$list" | grep -v -F 'denylist:allow' | cut -d: -f1,2)
  if [ -n "$hits" ]; then
    echo "::error::Denylisted names in tracked files:"
    echo "$hits"
    failed=1
  fi
fi

exit "$failed"
