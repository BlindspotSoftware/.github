#!/usr/bin/env bash
# Installs the pinned gitleaks into the directory $1, checked against its published checksum.
set -euo pipefail

version=8.30.1
sha256=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
dir=${1:?usage: install-gitleaks.sh <dir>}
archive=$dir/gitleaks.tar.gz

curl -fsSL -o "$archive" "https://github.com/gitleaks/gitleaks/releases/download/v$version/gitleaks_${version}_linux_x64.tar.gz"
echo "$sha256  $archive" | sha256sum -c --quiet -
tar -xzf "$archive" -C "$dir" gitleaks
