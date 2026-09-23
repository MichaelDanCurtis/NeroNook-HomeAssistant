#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/test-home/config
chmod 700 build/test-home build/test-home/config
if [ ! -f build/test-home/config/configuration.yaml ]; then
    cp Testing/HomeAssistant/configuration.yaml build/test-home/config/configuration.yaml
fi
docker compose -f Testing/HomeAssistant/compose.yaml up -d
python3 - <<'PY'
import time,urllib.request
until=time.monotonic()+60
while time.monotonic()<until:
    try:
        with urllib.request.urlopen('http://127.0.0.1:18123/api/onboarding',timeout=2) as r:
            if r.status==200:break
    except Exception:time.sleep(1)
else:raise SystemExit('Test home did not become ready in 60 seconds. Inspect its container log.')
print('Home Assistant test server is ready at http://127.0.0.1:18123')
PY
python3 Testing/HomeAssistant/bootstrap.py
