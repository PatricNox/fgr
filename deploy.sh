#!/usr/bin/env bash
# Commit, tag and push a release. Version comes from the .toc.
# Usage: ./deploy.sh "commit message"
set -euo pipefail

msg="${1:-Release}"
version=$(sed -n 's/^## Version: *//p' FastGuildRecruiter.toc | tr -d '\r')
[ -n "$version" ] || { echo "No '## Version:' in FastGuildRecruiter.toc"; exit 1; }
tag="v$version"

git rev-parse -q --verify "refs/tags/$tag" >/dev/null && {
    echo "Tag $tag already exists. Bump '## Version:' in the .toc first."; exit 1; }

git add -A
git diff --cached --quiet || git commit -m "$msg"
git tag -a "$tag" -m "$tag"
git push origin HEAD
git push origin "$tag"
echo "Deployed $tag"
