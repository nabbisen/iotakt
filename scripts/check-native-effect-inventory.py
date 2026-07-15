#!/usr/bin/env python3
"""Verify RFC 064's repository-derived native-effect inventory."""

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
RUNTIME = ROOT / "runtime" / "IotaktRuntime"
INVENTORY = ROOT / "docs" / "src" / "native-effect-inventory.tsv"
STABILITY = ROOT / "docs" / "src" / "api-stability.md"

DECL = re.compile(
    r"^(?:(?:private|protected|partial|noncomputable)\s+)*"
    r"(?:def|abbrev)\s+([A-Za-z_][A-Za-z0-9_']*)\b"
)
BOUNDARY = re.compile(
    r"^(?:inductive|structure|class|instance|theorem|lemma|axiom|namespace|end)\b"
)
EFFECT = re.compile(
    r"\b(?:"
    r"Epoll\.(?:create|wait|register|modify|deregister|close)|"
    r"Socket\.(?:socketTcpRaw|setReuseAddrRaw|bindIPv4Raw|listenRaw|"
    r"acceptRaw|accept|setNonblockRaw|setCloexecRaw|closeFdRaw|closeFd|"
    r"socketUdpRaw|socketpairRaw|connectIPv4Raw|connectIPv4|"
    r"getSocketErrorRaw|checkConnect)|"
    r"Io\.(?:recv|send)"
    r")\b"
)
CLASSES = {"checked-stable", "unsafe-internal", "unreachable"}
STABLE_MARKER = re.compile(r"native-effect-stable:\s*([^\s]+)")


def key(path: Path, symbol: str) -> str:
    return f"{path.relative_to(ROOT).as_posix()}::{symbol}"


def discover() -> dict[str, set[str]]:
    found: dict[str, set[str]] = {}
    for path in sorted(RUNTIME.rglob("*.lean")):
        if "/Native/" in path.as_posix():
            continue
        current: str | None = None
        block_depth = 0
        for raw_line in path.read_text(encoding="utf-8").splitlines():
            code: list[str] = []
            index = 0
            while index < len(raw_line):
                if raw_line.startswith("/-", index):
                    block_depth += 1
                    index += 2
                elif raw_line.startswith("-/", index) and block_depth > 0:
                    block_depth -= 1
                    index += 2
                elif block_depth == 0 and raw_line.startswith("--", index):
                    break
                else:
                    if block_depth == 0:
                        code.append(raw_line[index])
                    index += 1
            line = "".join(code)
            match = DECL.match(line)
            if match:
                current = match.group(1)
            elif BOUNDARY.match(line):
                current = None
            if current is None:
                continue
            for effect in EFFECT.findall(line):
                found.setdefault(key(path, current), set()).add(effect)
    return found


def read_inventory() -> dict[str, dict[str, str]]:
    if not INVENTORY.is_file():
        raise ValueError(f"missing inventory: {INVENTORY.relative_to(ROOT)}")
    with INVENTORY.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        required = {
            "symbol", "classification", "resolver", "native_effect",
            "test_ids", "justification",
        }
        if set(reader.fieldnames or ()) != required:
            raise ValueError(
                "inventory header must be exactly: " + ", ".join(sorted(required))
            )
        rows: dict[str, dict[str, str]] = {}
        for line_no, row in enumerate(reader, start=2):
            symbol = row["symbol"].strip()
            if not symbol:
                raise ValueError(f"line {line_no}: empty symbol")
            if symbol in rows:
                raise ValueError(f"line {line_no}: duplicate symbol {symbol}")
            row = {name: value.strip() for name, value in row.items()}
            if row["classification"] not in CLASSES:
                raise ValueError(
                    f"line {line_no}: invalid classification {row['classification']}"
                )
            if not row["native_effect"] or not row["justification"]:
                raise ValueError(f"line {line_no}: effect and justification are required")
            if row["classification"] == "checked-stable":
                if not row["resolver"] or not row["test_ids"]:
                    raise ValueError(
                        f"line {line_no}: checked-stable row needs resolver and test_ids"
                    )
            rows[symbol] = row
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--list", action="store_true", help="list discovered symbols")
    args = parser.parse_args()
    discovered = discover()
    if args.list:
        for symbol, effects in sorted(discovered.items()):
            print(f"{symbol}\t{','.join(sorted(effects))}")
        return 0

    try:
        rows = read_inventory()
    except ValueError as error:
        print(f"native-effect inventory: FAIL: {error}", file=sys.stderr)
        return 1

    missing = sorted(set(discovered) - set(rows))
    stale = sorted(
        symbol for symbol, row in rows.items()
        if symbol not in discovered and row["classification"] != "unreachable"
        and not symbol.startswith("indirect::")
    )
    checked = {
        symbol for symbol, row in rows.items()
        if row["classification"] == "checked-stable"
    }
    markers = set(STABLE_MARKER.findall(STABILITY.read_text(encoding="utf-8")))
    missing_markers = sorted(checked - markers)
    unknown_markers = sorted(markers - checked)

    evidence_paths = (
        sorted((ROOT / "runtime" / "examples").rglob("*.lean"))
        + sorted(path for path in (ROOT / "scripts").iterdir() if path.is_file())
        + [ROOT / "runtime" / "lakefile.lean"]
    )
    test_corpus = "\n".join(
        path.read_text(encoding="utf-8", errors="replace")
        for path in evidence_paths
    )
    missing_test_ids: list[tuple[str, str]] = []
    for symbol in checked:
        for test_id in rows[symbol]["test_ids"].split(","):
            if test_id and test_id not in test_corpus:
                missing_test_ids.append((symbol, test_id))

    if missing:
        print("native-effect inventory: FAIL: unclassified discovered paths:", file=sys.stderr)
        for symbol in missing:
            print(f"  {symbol}: {','.join(sorted(discovered[symbol]))}", file=sys.stderr)
    if stale:
        print("native-effect inventory: FAIL: rows no longer discovered:", file=sys.stderr)
        for symbol in stale:
            print(f"  {symbol}", file=sys.stderr)
    if missing_markers:
        print("native-effect inventory: FAIL: checked rows absent from stable markers:", file=sys.stderr)
        for symbol in missing_markers:
            print(f"  {symbol}", file=sys.stderr)
    if unknown_markers:
        print("native-effect inventory: FAIL: stable markers not checked in inventory:", file=sys.stderr)
        for symbol in unknown_markers:
            print(f"  {symbol}", file=sys.stderr)
    if missing_test_ids:
        print("native-effect inventory: FAIL: unbound checked test identifiers:", file=sys.stderr)
        for symbol, test_id in missing_test_ids:
            print(f"  {symbol}: {test_id}", file=sys.stderr)
    if missing or stale or missing_markers or unknown_markers or missing_test_ids:
        return 1

    counts = {classification: 0 for classification in sorted(CLASSES)}
    for row in rows.values():
        counts[row["classification"]] += 1
    print(
        "native-effect inventory: PASS: "
        f"{len(discovered)} discovered direct paths, {len(rows)} classified rows "
        f"({counts['checked-stable']} checked-stable, "
        f"{counts['unsafe-internal']} unsafe-internal, "
        f"{counts['unreachable']} unreachable)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
