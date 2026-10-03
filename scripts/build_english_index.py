#!/usr/bin/env python3
"""Read the formal English CSV and write a private, rebuildable lookup index."""
import argparse
import csv
import hashlib
import io
import json
import os
import tempfile
import unicodedata
from pathlib import Path

FIELDS = ["id", "item", "type", "meaning", "source_sentence", "usage", "review_note", "source_article", "last_seen"]


def normalize(text):
    text = unicodedata.normalize("NFKC", text).strip()
    text = text.replace("’", "'").replace("‘", "'")
    return " ".join(text.casefold().split())


def build(source, output):
    before = source.stat()
    if before.st_size > 16 * 1024 * 1024:
        raise ValueError("English CSV exceeds the 16 MiB read budget")
    raw = source.read_bytes()
    after = source.stat()
    if (before.st_mtime_ns, before.st_size) != (after.st_mtime_ns, after.st_size):
        raise ValueError("English CSV changed during reading; retry after the writer finishes")
    reader = csv.DictReader(io.StringIO(raw.decode("utf-8-sig"), newline=""))
    if not set(FIELDS).issubset(reader.fieldnames or []):
        raise ValueError("English CSV schema is missing required fields")
    entries = {}
    rows = 0
    for row in reader:
        rows += 1
        key = normalize(row.get("item") or "")
        if not key or not row.get("id") or not row.get("meaning") or row.get("type") == "句型":
            continue
        entry = {field: row.get(field, "") for field in FIELDS}
        entries.setdefault(key, []).append(entry)
    for matches in entries.values():
        matches.sort(key=lambda row: (row["last_seen"], row["id"]), reverse=True)
    result = {"schemaVersion": 1, "source": str(source.resolve()),
              "sourceMtime": int(after.st_mtime), "sourceSize": after.st_size,
              "sourceSha256": hashlib.sha256(raw).hexdigest(), "rows": rows,
              "keys": len(entries), "entries": entries}
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".english-index-", dir=output.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as file:
            json.dump(result, file, ensure_ascii=False, separators=(",", ":"))
            file.flush()
            os.fsync(file.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, output)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return {"rows": rows, "keys": len(entries)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(build(args.source, args.output)))
