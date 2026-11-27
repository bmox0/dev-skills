#!/usr/bin/env bash
set -euo pipefail

script="$(cd "$(dirname "$0")/../.." && pwd)/.github/scripts/publish-release.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
git init -q
git config user.name Fixture
git config user.email fixture@example.invalid
echo 7.2.0 > VERSION
git add VERSION
git commit -qm base
export BEFORE=$(git rev-parse HEAD)
export GITHUB_SHA="$BEFORE"
export PATH="$tmp:$PATH"
cat > gh <<'SH'
#!/usr/bin/env bash
case "$2" in
  view) echo false ;;
  create) printf '%s\n' "$@" > published ;;
  *) exit 1 ;;
esac
SH
chmod +x gh

bash "$script"
test ! -e published
echo 7.2.1 > VERSION
mkdir -p docs/releases
echo 'Improved CLI help.' > docs/releases/7.2.1.md
git add VERSION docs
git commit -qm patch
GITHUB_SHA=$(git rev-parse HEAD)
bash "$script"
diff -u published - <<EOF
release
create
v7.2.1
--target
$GITHUB_SHA
--title
Runweld 7.2.1
--notes-file
docs/releases/7.2.1.md
EOF
git tag v7.2.1
rm published
bash "$script"
test ! -e published
git tag -f v7.2.1 "$BEFORE"
if bash "$script"; then exit 1; fi
test ! -e published

echo 7.3.0-rc.1 > VERSION
git commit -qam candidate
GITHUB_SHA=$(git rev-parse HEAD)
bash "$script"
grep -Fx -- --generate-notes published
grep -Fx -- --prerelease published
