#!/bin/zsh
# Checks user-facing string literals against the copy standard in "OffRecord Design.md" (Voice).
#
#   scripts/copy-lint.sh
#
# Scans Swift string literals in the app, widget, watch, and JournalKit sources and fails on
# banned punctuation, words, and privacy reassurance outside the places the standard allows.
# Log lines, identifiers, #Preview blocks, and the screenshot/UI-test seeders are skipped.
# Add `copy-lint:ignore` to a line to skip it on purpose (for example, an LLM instruction that
# lists the banned words).

set -euo pipefail
cd "${0:A:h}/.."

python3 - <<'PY'
import re, sys
from pathlib import Path

ROOTS = ["OffRecord", "OffRecordWidget", "OffRecordWatch", "OffRecordWatchWidget",
         "OffRecordSystemShared", "OffRecordShared", "Packages/JournalKit/Sources"]
# ProactiveReflectionModels.swift in ReflectionKit duplicates OffRecord/ProactiveReflection.swift, which
# shadows it in the app; drop it from this list once the two are consolidated.
SKIP_FILES = {"ScreenshotDataSeeder.swift", "UITestDataSeeder.swift", "ProactiveReflectionModels.swift"}
SKIP_LINE = re.compile(r"[Ll]ogger\.|Logger\(|print\(|os_log|privacy: \.public|accessibilityIdentifier|systemName:|forKey:|"
                       r"UserDefaults|NSPredicate|copy-lint:ignore|^\s*//")

# Places the standard allows privacy reassurance.
PRIVACY_FILES = {"OnboardingView.swift", "HomePrivacyExplanationView.swift", "SettingsView.swift",
                 "OffRecordSettingsComponents.swift", "SpeechTranscriptionConsent.swift",
                 "ShareableInsightCardView.swift", "BackupExportView.swift",
                 "FridayActiveChatHeader.swift"}

RULES = [
    ("em dash", re.compile(r"—|\\u\{2014\}")),
    ("three dots (use …)", re.compile(r"\.\.\.")),
    ("bullet separator (use ·)", re.compile(r"•")),
    ("exclamation mark", re.compile(r"![\"\s]|!$")),
    ("please", re.compile(r"\b[Pp]lease\b")),
    ("gentle", re.compile(r"\b[Gg]entl")),
    ("journey", re.compile(r"\b[Jj]ourney")),
    ("unlock (marketing)", re.compile(r"[Uu]nlock (deeper|more|your (full )?potential)")),
    ("safe space", re.compile(r"safe space")),
    ("Friday noticed", re.compile(r"Friday noticed", re.I)),
    ("diary", re.compile(r"\b[Dd]iary\b")),
    ("old product name", re.compile(r"DAILYVOX|AI Voice Diary|AI Voice Journal", re.I)),
    ("voice note (say recording)", re.compile(r"\b[Vv]oice (note|moment)")),
    ("engineering term", re.compile(r"[Ss]emantic [Mm]emory|[Ee]mbeddings?\b|lexical|Indexed chunks")),
    ("cheerleading", re.compile(r"[Kk]eep it up")),
]
PRIVACY = re.compile(r"on this device|on your device|stays? on (this|your)|\blocally\b|[Oo]n-device", re.I)
RULE_EXCEPTIONS = {"diary": {"JournalSpotlightIndexer.swift"}}

LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')
problems = []

for root in ROOTS:
    for path in sorted(Path(root).rglob("*.swift")):
        if path.name in SKIP_FILES or "Tests" in path.parts:
            continue
        depth = None  # brace depth while inside a #Preview block
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if depth is None and line.lstrip().startswith("#Preview"):
                depth = 0
            if depth is not None:
                depth += line.count("{") - line.count("}")
                if depth <= 0 and "}" in line:
                    depth = None
                continue
            if SKIP_LINE.search(line):
                continue
            for literal in LITERAL.findall(line):
                if not re.search(r"[A-Za-z]", literal) or " " not in literal and "…" not in literal and not re.search(r"[—•!]", literal):
                    continue  # identifiers, keys, and single tokens
                for name, pattern in RULES:
                    if pattern.search(literal) and path.name not in RULE_EXCEPTIONS.get(name, ()):
                        problems.append(f"{path}:{number}: {name}: \"{literal}\"")
                if PRIVACY.search(literal) and path.name not in PRIVACY_FILES:
                    problems.append(f"{path}:{number}: privacy reassurance outside allowed places: \"{literal}\"")

for problem in problems:
    print(problem)
print(f"\n{len(problems)} copy issue(s)." if problems else "Copy lint passed.")
sys.exit(1 if problems else 0)
PY
