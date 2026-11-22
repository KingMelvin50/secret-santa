#!/bin/sh
# Renders tools/share-image.html into share.jpg: the 1200×630 picture chat apps show next to the link.
# Needs Google Chrome on a Mac. Run it again whenever the title or the heads change:
#
#   sh tools/make-share-image.sh
set -e
cd "$(dirname "$0")/.."

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
if [ ! -x "$CHROME" ]; then
  echo "Couldn't find Google Chrome. Install it, or set CHROME=/path/to/a/chromium-based/browser, or open"
  echo "tools/share-image.html in any browser at exactly 1200×630 and save a screenshot as share.jpg."
  exit 1
fi

TMP="$(mktemp -d)"
"$CHROME" --headless=new --hide-scrollbars --user-data-dir="$TMP/profile" --force-device-scale-factor=1 \
  --window-size=1200,630 --virtual-time-budget=8000 --screenshot="$TMP/share.png" \
  "file://$PWD/tools/share-image.html" >/dev/null 2>&1
if command -v sips >/dev/null 2>&1; then
  sips -s format jpeg -s formatOptions 88 "$TMP/share.png" --out share.jpg >/dev/null
else
  cp "$TMP/share.png" share.png
  echo "No 'sips' here, so the picture was saved as share.png: convert it to share.jpg (or point the"
  echo "og:image and twitter:image lines in index.html at share.png)."
fi
rm -rf "$TMP"
echo "Wrote share.jpg. Open it and check it looks right."
