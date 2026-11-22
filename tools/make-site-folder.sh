#!/bin/sh
# Copies just the files that belong online into _site/, for hosts where you drag and drop a folder.
# (The original photos and the tools stay behind.)
#
#   sh tools/make-site-folder.sh
set -e
cd "$(dirname "$0")/.."
rm -rf _site
mkdir _site
cp -R index.html config.js heads _site/
[ -f share.jpg ] && cp share.jpg _site/
[ -f vercel.json ] && cp vercel.json _site/
echo "Made _site/ with: $(ls _site | tr '\n' ' ')"
echo "Upload that folder, and nothing else."
