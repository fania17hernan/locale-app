#!/usr/bin/env bash
# Run the EXACT checks .github/workflows/deploy.yml runs, locally, before pushing.
# Run 155 failed on a check that would have taken two seconds to catch here.
# Usage:  bash preflight.sh
set -uo pipefail
cd "$(dirname "$0")"
DEPLOY_FILES="index.html locale.html locale-v2.html og-card.png whats-new.html"
fail=0

echo "1. deployable files exist"
for f in $DEPLOY_FILES; do [ -f "$f" ] || { echo "   MISSING $f"; fail=1; }; done

echo "2. required script tags"
for app in locale.html locale-v2.html; do
  for tag in react.production.min.js react-dom.production.min.js babel.min.js; do
    grep -q "$tag" "$app" || { echo "   MISSING $tag in $app"; fail=1; }
  done
done

echo "3. brace balance (tolerance 50)"
for app in locale.html locale-v2.html; do
  O=$(grep -o '{' "$app" | wc -l); C=$(grep -o '}' "$app" | wc -l)
  D=$((O - C)); A=${D#-}
  echo "   $app diff=$D"
  [ "$A" -gt 50 ] && { echo "   FAIL brace balance"; fail=1; }
done

echo "4. secret scan"
# NOTE: these greps match their own patterns. Never write the literal token strings
# in app source — even inside a comment. That is exactly what failed run 155.
grep -rlE "sk-ant-[a-zA-Z0-9-]{20,}" --include="*.html" . && { echo "   FAIL anthropic key"; fail=1; }
grep -rlE "\bre_[A-Za-z0-9]{20,}"    --include="*.html" . && { echo "   FAIL resend key"; fail=1; }
grep -rl  "service""_role"           --include="*.html" . && { echo "   FAIL elevated-role literal"; fail=1; }
FOUND=0
for tok in $(grep -rhoE "eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}" --include="*.html" . | sort -u); do
  P=$(echo "$tok" | cut -d. -f2)
  PAD=$(( (4 - ${#P} % 4) % 4 )); for _ in $(seq 1 $PAD); do P="${P}="; done
  D=$(echo "$P" | tr '_-' '/+' | base64 -d 2>/dev/null || true)
  echo "$D" | grep -q "service""_role" && { echo "   FAIL elevated-role JWT embedded"; FOUND=1; }
done
[ "$FOUND" = "1" ] && fail=1

echo "5. esbuild parse of the babel block"
python3 - <<'PY'
import re
src = open('locale-v2.html', encoding='utf-8').read()
blocks = re.findall(r'<script type="text/babel"[^>]*>(.*?)</script>', src, flags=re.S)
open('/tmp/preflight.jsx', 'w').write(blocks[0])
PY
if npx --yes esbuild@0.23.0 /tmp/preflight.jsx --log-level=warning --outfile=/tmp/preflight.out.js 2>&1 | head -20; then
  [ -f /tmp/preflight.out.js ] || { echo "   FAIL parse"; fail=1; }
else
  echo "   FAIL parse"; fail=1
fi

echo
if [ "$fail" -eq 0 ]; then echo "✅ ALL CI CHECKS PASS — safe to push"; exit 0
else echo "❌ WOULD FAIL CI — fix before pushing"; exit 1; fi
