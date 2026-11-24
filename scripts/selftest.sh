#!/usr/bin/env bash
# Runs leak-guard.sh and dco.sh against throwaway repos built here: a committed secret or
# denylisted name would trip this repo's own checks and GitHub's push protection.
set -euo pipefail

scripts=$(cd "$(dirname "$0")" && pwd)
"${GITLEAKS:-gitleaks}" version > /dev/null

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

denied=a7-denied-name
token=ghp_$(head -c 512 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 36)
failures=0

# repo <name>: a repo with one signed-off base commit, left in $dir.
repo() {
  dir=$work/$1
  git init -q -b main "$dir"
  git -C "$dir" config user.name "Self Test"
  git -C "$dir" config user.email selftest@example.org
  git -C "$dir" commit -q --allow-empty --signoff -m base
}

# change <file> <content> [git commit flags...]: commits content to file in $dir.
change() {
  printf '%s\n' "$2" > "$dir/$1"
  git -C "$dir" add "$1"
  git -C "$dir" commit -q -m "change $1" "${@:3}"
}

# expect <pass|fail> <case> <command...>: runs the command in $dir; its output lands in $out.
expect() {
  local want=$1 name=$2 got
  shift 2
  out=$work/$name.out
  if (cd "$dir" && "$@") > "$out" 2>&1; then got=pass; else got=fail; fi

  if [ "$got" = "$want" ]; then
    echo "ok   $name ($got)"
  else
    echo "FAIL $name: want $want, got $got"
    sed 's/^/     /' "$out"
    failures=$((failures + 1))
  fi
}

# Fails the case unless the last output contains (want=yes) or lacks (want=no) the text.
expect_output() {
  local want=$1 name=$2 text=$3
  if grep -qiF -- "$text" "$out"; then has=yes; else has=no; fi
  if [ "$has" != "$want" ]; then
    echo "FAIL $name: output contains '$text': $has, want $want"
    failures=$((failures + 1))
  fi
}

export LEAK_DENYLIST=$denied LEAK_GUARD_FORK_PR=false

repo clean
change README.md "nothing to see" --signoff
expect pass clean-leaks "$scripts/leak-guard.sh" main~1..main
expect pass clean-dco "$scripts/dco.sh" main~1..main

repo secret-in-tree
change config.txt "token = $token" --signoff
expect fail secret-in-tree "$scripts/leak-guard.sh" main~1..main
expect_output yes secret-in-tree-found "leaks found:"
expect_output yes secret-in-tree-names-file "config.txt"
expect_output no secret-not-printed "$token"

repo secret-in-history
change config.txt "token = $token" --signoff
change config.txt "token = from the environment" --signoff
expect fail secret-in-history "$scripts/leak-guard.sh" main~2..main
expect_output yes secret-in-history-found "leaks found:"

repo denylisted
change notes.md "a board from ${denied^^} in the lab" --signoff
expect fail denylisted "$scripts/leak-guard.sh" main~1..main
expect_output yes denylisted-names-path "notes.md:1"
expect_output no denylisted-not-a-leak "leaks found:"
expect_output no denylisted-not-printed "$denied"

LEAK_DENYLIST=$'\n  \n' expect fail empty-denylist "$scripts/leak-guard.sh" main~1..main
expect_output yes empty-denylist-says-so "LEAK_DENYLIST is empty"

LEAK_DENYLIST='' LEAK_GUARD_FORK_PR=true expect pass fork-pr-skips-denylist "$scripts/leak-guard.sh" main~1..main
expect_output yes fork-pr-notice "gets no secrets"

repo unsigned
change feature.go "package feature"
expect fail unsigned "$scripts/dco.sh" main~1..main
expect_output yes unsigned-names-commit "change feature.go"

repo foreign-sign-off
change feature.go "package feature" -m "change feature.go" -m "Signed-off-by: Someone Else <else@example.org>"
expect fail foreign-sign-off "$scripts/dco.sh" main~1..main

repo bot
git -C "$dir" -c user.name='dependabot[bot]' -c user.email='49699333+dependabot[bot]@users.noreply.github.com' \
  commit -q --allow-empty -m "bump a dependency"
expect pass bot-needs-no-sign-off "$scripts/dco.sh" main~1..main

repo denylist-allow
change hosts.yaml "host: build.$denied.example # denylist:allow" --signoff
change notes.md "a board from $denied in the lab" --signoff
expect fail denylist-allow-is-per-line "$scripts/leak-guard.sh" main~2..main
expect_output yes denylist-allow-names-other-line "notes.md:1"
expect_output no denylist-allow-skips-its-line "hosts.yaml"
git -C "$dir" rm -q notes.md
git -C "$dir" commit -q --signoff -m "drop notes.md"
expect pass denylist-allow "$scripts/leak-guard.sh" main~3..main

expect fail bad-range "$scripts/dco.sh" main..no-such-branch

if [ "$failures" -gt 0 ]; then
  echo "$failures case(s) failed"
  exit 1
fi
