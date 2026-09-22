#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
INFO_PLIST="$PROJECT_DIR/Resources/Info.plist"

commit_count=$(git -C "$PROJECT_DIR" rev-list --count HEAD)
pending_changes=$(git -C "$PROJECT_DIR" status --porcelain --untracked-files=normal -- \
  . ':(exclude)Resources/Info.plist')

build_number=$commit_count
if [[ -n "$pending_changes" ]]; then
  build_number=$((commit_count + 1))
fi

major=$((build_number / 100))
minor=$(((build_number / 10) % 10))
patch=$((build_number % 10))
marketing_version="${major}.${minor}.${patch}"

/usr/libexec/PlistBuddy \
  -c "Set :CFBundleShortVersionString $marketing_version" \
  -c "Set :CFBundleVersion $build_number" \
  "$INFO_PLIST"

echo "版本已同步：V${marketing_version} (build ${build_number})"
