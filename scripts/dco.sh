#!/usr/bin/env bash
# Run in a git checkout. Fails when a non-merge commit in $1 (base..head) has no Signed-off-by
# line for its author. Bot commits, such as Dependabot's, need none.
set -uo pipefail

range=${1:?usage: dco.sh <base..head>}

if ! commits=$(git rev-list --no-merges "$range"); then
  echo "::error::cannot list the commits in $range"
  exit 1
fi

unsigned=0

for commit in $commits; do
  author=$(git log -1 --format='%an <%ae>' "$commit")

  case $author in
    *'[bot]@users.noreply.github.com>') continue ;;
  esac

  if ! git log -1 --format='%(trailers:key=Signed-off-by,valueonly,unfold)' "$commit" |
    sed 's/[[:space:]]*$//' | grep -qxF "$author"; then
    echo "::error::$(git log -1 --format='%h %s' "$commit") has no Signed-off-by: $author"
    unsigned=1
  fi
done

if [ "$unsigned" = 1 ]; then
  echo "Sign off with git commit --amend --signoff, or git rebase --signoff <base> for several commits."
fi

exit "$unsigned"
