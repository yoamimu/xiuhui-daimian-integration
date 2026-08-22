#!/usr/bin/env python3
"""pkg-config wrapper: rewrite CommandLineTools SDK paths to the active
Xcode SDK. Homebrew's system-library shims emit -isystem/-I paths pointing
at /Library/Developer/CommandLineTools/SDKs/MacOSX<N>.sdk; mixed with Xcode's
libc++ those break C++ standard header resolution on some toolchains."""
import os
import re
import subprocess
import sys

REAL = sys.argv[1]
args = sys.argv[2:]

r = subprocess.run([REAL] + args, capture_output=True)
sys.stderr.buffer.write(r.stderr)
if r.returncode != 0:
    sys.exit(r.returncode)

out = r.stdout.decode("utf-8", "replace")
sdk = os.environ.get("SDKROOT") or subprocess.run(
    ["xcrun", "--show-sdk-path"], capture_output=True, text=True
).stdout.strip()

if sdk:
    out = re.sub(
        r"/Library/Developer/CommandLineTools/SDKs/MacOSX[0-9][0-9.]*\.sdk",
        sdk.rstrip("/"),
        out,
    )

sys.stdout.write(out)
