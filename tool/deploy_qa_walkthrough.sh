#!/usr/bin/env bash
# Builds the walkthrough A/B QA web app into public/qa/walkthrough/ so it is
# served by Firebase Hosting at https://famotive.org/qa/walkthrough
# (see Documents/QA_AB_Walkthrough.md).
#
#   tool/deploy_qa_walkthrough.sh            # build only
#   tool/deploy_qa_walkthrough.sh --preview  # build + deploy to a temporary preview URL
#   tool/deploy_qa_walkthrough.sh --deploy   # build + deploy to the live site
#
# A Hosting deploy replaces the WHOLE site with public/. The site's pages
# (index.html, privacy-policy.html, delete-my-data.html, .well-known/ for
# app/password-reset links) are not in this repo, so this refuses to deploy
# unless they are in public/ next to the QA build.
set -euo pipefail

cd "$(dirname "$0")/.."

QA_PATH="qa/walkthrough"
OUT="public/$QA_PATH"
REQUIRED=(
  public/index.html
  public/privacy-policy.html
  public/delete-my-data.html
  public/.well-known/assetlinks.json
  public/.well-known/apple-app-site-association
)

mode="${1:-build}"
case "$mode" in
  build|--preview|--deploy) ;;
  *) echo "usage: $0 [--preview|--deploy]" >&2; exit 2 ;;
esac

if [[ "$mode" != build ]]; then
  missing=()
  for f in "${REQUIRED[@]}"; do [[ -e "$f" ]] || missing+=("$f"); done
  if (( ${#missing[@]} )); then
    echo "Refusing to deploy: these live-site files are missing from public/:" >&2
    printf '  %s\n' "${missing[@]}" >&2
    echo "Deploying without them would delete them from famotive.org." >&2
    echo "Copy the site's current public/ folder here first (ask whoever deploys the site)." >&2
    exit 1
  fi
fi

flutter pub get
flutter build web \
  -t lib/qa/ab_walkthrough_main.dart \
  --base-href "/$QA_PATH/" \
  --no-web-resources-cdn \
  --release

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
cp -R build/web "$OUT"
echo "Built QA app into $OUT"

case "$mode" in
  --preview)
    firebase hosting:channel:deploy qa-walkthrough --expires 14d
    echo "Open <preview URL>/$QA_PATH"
    ;;
  --deploy)
    firebase deploy --only hosting
    echo "Live at https://famotive.org/$QA_PATH"
    ;;
esac
