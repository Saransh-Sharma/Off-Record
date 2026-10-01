#!/usr/bin/env bash
# Checks public docs, App Store metadata, and the website for claims the app no longer makes.
#
#   scripts/claims-lint.sh
#
# copy-lint covers Swift string literals; this covers everything a reviewer or a visitor reads
# outside the app. Each rule names a claim that was true once and is wrong now, so a hit means
# the text drifted from the code. Add `claims-lint:ignore` to a line to skip it on purpose.

set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import re, sys
from pathlib import Path

FILES = [
    "README.md", "ARCHITECTURE.md", "ROADMAP.md", "SECURITY.md", "WEEKLY_REFLECTION.md",
    "SEMANTIC_MEMORY_FRIDAY.md", "SPEECH_ANALYZER_MIGRATION.md", "CHANGELOG.md",
    "marketing/research-paper-draft.md",
]
GLOBS = ["AppStore/*.md", "AppStore/metadata.json", "AppStore/Deliverfile", "website/public/**/*.html",
         "website/public/*.txt"]

RULES = [
    ("App Store ID of a different app (DailyVox)", re.compile(r"id6760454642")),
    ("placeholder domain", re.compile(r"offrecord\.example\.com")),
    ("retired product name", re.compile(r"DAILYVOX|DailyVox|AI Voice Diary")),
    ("Speech Recognition permission (SpeechAnalyzer needs microphone only)",
     re.compile(r"<td>Speech Recognition</td>|\|\s*Speech Recognition\s*\|")),
    ("server or online speech recognition", re.compile(r"NWPathMonitor|server-assisted transcription|online speech recognition", re.I)),
    ("entries are not AES-encrypted (only backups are)", re.compile(r"AES-256-GCM encrypted entries|Entries encrypted with AES", re.I)),
    ("backups use PBKDF2, not HKDF", re.compile(r"derivation (uses|using) HKDF", re.I)),
    ("iCloud is end-to-end encrypted only with Advanced Data Protection",
     re.compile(r"end-to-end encrypted by Apple\)", re.I)),
    ("mood count (the app has 8 moods)", re.compile(r"\b9 (Emotions|Moods)\b", re.I)),
    ("screenshot folder that does not exist", re.compile(r"screenshots/iPhone_67/")),
    ("minimum OS is iOS 26", re.compile(r"Platform-iOS%2017|Requires iOS 17|iOS 17\+ \| iPadOS")),
]

paths = [Path(p) for p in FILES if Path(p).exists()]
for pattern in GLOBS:
    paths.extend(sorted(Path(".").glob(pattern)))

problems = []
for path in paths:
    for number, line in enumerate(path.read_text(errors="ignore").splitlines(), 1):
        if "claims-lint:ignore" in line:
            continue
        for name, pattern in RULES:
            if pattern.search(line):
                problems.append(f"{path}:{number}: {name}")

for problem in problems:
    print(problem)
print(f"\n{len(problems)} stale claim(s) in {len(paths)} files." if problems else f"Claims lint passed ({len(paths)} files).")
sys.exit(1 if problems else 0)
PY
