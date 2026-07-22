#!/usr/bin/env python3
"""Verify RFC 065's repository-derived receive-allocation inventory."""

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
RUNTIME = ROOT / "runtime" / "IotaktRuntime"
NATIVE_IO = ROOT / "runtime" / "native" / "iotakt_io.c"
INVENTORY = ROOT / "docs" / "src" / "receive-allocation-inventory.tsv"
STABILITY = ROOT / "docs" / "src" / "api-stability.md"

DECL = re.compile(
    r"^(?P<modifiers>(?:(?:private|protected|partial|noncomputable)\s+)*)"
    r"(?:def|abbrev)\s+(?P<name>[A-Za-z_][A-Za-z0-9_']*)\b"
)
BOUNDARY = re.compile(
    r"^(?:inductive|structure|class|instance|theorem|lemma|axiom|namespace|end)\b"
)
RECEIVE = re.compile(r"\b(?:Unsafe\.Io\.(?:recv|recvFrom)|recvRaw|recvFromRaw)\b")
C_RECEIVE = re.compile(
    r"LEAN_EXPORT\s+lean_obj_res\s+(?P<name>iotakt_recv(?:from)?)\s*\("
)
CLASSES = {"limit-enforced", "unsafe-internal", "unreachable"}
STABLE_MARKER = re.compile(r"receive-allocation-stable:\s*([^\s]+)")


def key(path: Path, symbol: str) -> str:
    return f"{path.relative_to(ROOT).as_posix()}::{symbol}"


def strip_comments(lines: list[str]) -> list[str]:
    result: list[str] = []
    block_depth = 0
    for raw_line in lines:
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
        result.append("".join(code))
    return result


def discover() -> dict[str, set[str]]:
    found: dict[str, set[str]] = {}
    for path in sorted(RUNTIME.rglob("*.lean")):
        current: str | None = None
        lines = path.read_text(encoding="utf-8").splitlines()
        for line in strip_comments(lines):
            match = DECL.match(line)
            if match:
                current = match.group("name")
            elif BOUNDARY.match(line):
                current = None
            if current is None:
                continue
            for receive in RECEIVE.findall(line):
                found.setdefault(key(path, current), set()).add(receive)

    native_text = NATIVE_IO.read_text(encoding="utf-8")
    for match in C_RECEIVE.finditer(native_text):
        name = match.group("name")
        found[key(NATIVE_IO, name)] = {"native allocation/syscall length"}
    return found


def read_inventory() -> dict[str, dict[str, str]]:
    if not INVENTORY.is_file():
        raise ValueError(f"missing inventory: {INVENTORY.relative_to(ROOT)}")
    with INVENTORY.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        required = {
            "symbol", "classification", "governing_limit",
            "allocation_or_length", "test_ids", "justification",
        }
        if set(reader.fieldnames or ()) != required:
            raise ValueError(
                "inventory header must be exactly: " + ", ".join(sorted(required))
            )
        rows: dict[str, dict[str, str]] = {}
        for line_no, raw_row in enumerate(reader, start=2):
            row = {name: value.strip() for name, value in raw_row.items()}
            symbol = row["symbol"]
            if not symbol:
                raise ValueError(f"line {line_no}: empty symbol")
            if symbol in rows:
                raise ValueError(f"line {line_no}: duplicate symbol {symbol}")
            if row["classification"] not in CLASSES:
                raise ValueError(
                    f"line {line_no}: invalid classification {row['classification']}"
                )
            if not row["allocation_or_length"] or not row["justification"]:
                raise ValueError(
                    f"line {line_no}: allocation_or_length and justification are required"
                )
            if row["classification"] == "limit-enforced":
                if not row["governing_limit"] or not row["test_ids"]:
                    raise ValueError(
                        f"line {line_no}: limit-enforced row needs governing_limit and test_ids"
                    )
            rows[symbol] = row
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--list", action="store_true", help="list discovered symbols")
    args = parser.parse_args()
    discovered = discover()
    if args.list:
        for symbol, paths in sorted(discovered.items()):
            print(f"{symbol}\t{','.join(sorted(paths))}")
        return 0

    try:
        rows = read_inventory()
    except ValueError as error:
        print(f"receive-allocation inventory: FAIL: {error}", file=sys.stderr)
        return 1

    missing = sorted(set(discovered) - set(rows))
    stale = sorted(
        symbol for symbol, row in rows.items()
        if symbol not in discovered and row["classification"] != "unreachable"
    )
    limited = {
        symbol for symbol, row in rows.items()
        if row["classification"] == "limit-enforced"
    }
    markers = set(STABLE_MARKER.findall(STABILITY.read_text(encoding="utf-8")))
    missing_markers = sorted(limited - markers)
    unknown_markers = sorted(markers - limited)

    evidence_paths = (
        sorted((ROOT / "runtime" / "examples").rglob("*.lean"))
        + sorted(path for path in (ROOT / "scripts").iterdir() if path.is_file())
    )
    test_corpus = "\n".join(
        path.read_text(encoding="utf-8", errors="replace")
        for path in evidence_paths
    )
    missing_test_ids: list[tuple[str, str]] = []
    for symbol in limited:
        for test_id in rows[symbol]["test_ids"].split(","):
            if test_id and test_id not in test_corpus:
                missing_test_ids.append((symbol, test_id))

    if missing:
        print(
            "receive-allocation inventory: FAIL: unclassified discovered paths:",
            file=sys.stderr,
        )
        for symbol in missing:
            print(f"  {symbol}: {','.join(sorted(discovered[symbol]))}", file=sys.stderr)
    if stale:
        print("receive-allocation inventory: FAIL: rows no longer discovered:", file=sys.stderr)
        for symbol in stale:
            print(f"  {symbol}", file=sys.stderr)
    if missing_markers:
        print(
            "receive-allocation inventory: FAIL: limited rows absent from stable markers:",
            file=sys.stderr,
        )
        for symbol in missing_markers:
            print(f"  {symbol}", file=sys.stderr)
    if unknown_markers:
        print(
            "receive-allocation inventory: FAIL: stable markers not limit-enforced:",
            file=sys.stderr,
        )
        for symbol in unknown_markers:
            print(f"  {symbol}", file=sys.stderr)
    if missing_test_ids:
        print(
            "receive-allocation inventory: FAIL: unbound limit test identifiers:",
            file=sys.stderr,
        )
        for symbol, test_id in missing_test_ids:
            print(f"  {symbol}: {test_id}", file=sys.stderr)
    if missing or stale or missing_markers or unknown_markers or missing_test_ids:
        return 1

    counts = {classification: 0 for classification in sorted(CLASSES)}
    for row in rows.values():
        counts[row["classification"]] += 1
    print(
        "receive-allocation inventory: PASS: "
        f"{len(discovered)} discovered paths, {len(rows)} classified rows "
        f"({counts['limit-enforced']} limit-enforced, "
        f"{counts['unsafe-internal']} unsafe-internal, "
        f"{counts['unreachable']} unreachable)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
