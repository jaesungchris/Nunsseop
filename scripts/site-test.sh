#!/bin/bash
# Checks docs/index.html in a headless browser. Needs Playwright:
#   npm i -g playwright && playwright install chromium-headless-shell
set -euo pipefail
cd "$(dirname "$0")/.."
NODE_PATH="$(npm root -g)" node scripts/site-test.cjs
