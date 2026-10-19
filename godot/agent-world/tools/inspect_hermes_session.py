#!/usr/bin/env python3
"""Read-only inspector for Hermes gateway sessions (UT-7 / AC-FW-04).

Agent conversation history is authoritative on the gateway side — Hermes keeps
it in ~/.hermes/state.db (sessions + messages tables). This tool answers the
QA question AC-FW-04 poses: did a given narration/prompt string reach the
agent's session verbatim?

Usage:
  tools/inspect_hermes_session.py list
  tools/inspect_hermes_session.py dump --session <id-or-key> [--last N] [--full]
  tools/inspect_hermes_session.py grep --needle "<verbatim string>" [--session <id-or-key>]

The database is opened read-only (SQLite URI mode) — the tool can never
mutate gateway state, so it is safe to run while the game and gateway are up.
"""

import argparse
import os
import sqlite3
import sys

DEFAULT_DB = os.path.join(os.path.expanduser("~"), ".hermes", "state.db")
PREVIEW_CHARS = 160


def connect(db_path: str) -> sqlite3.Connection:
    if not os.path.exists(db_path):
        sys.exit(f"error: no Hermes state db at {db_path}")
    con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    return con


def resolve_session(con: sqlite3.Connection, ref: str) -> str:
    """Accept a session id, session_key, or display_name; return the id."""
    row = con.execute(
        "SELECT id FROM sessions WHERE id = ? OR session_key = ? OR display_name = ? "
        "ORDER BY started_at DESC LIMIT 1",
        (ref, ref, ref),
    ).fetchone()
    if row is None:
        sys.exit(f"error: no session matches '{ref}' (try the 'list' command)")
    return row["id"]


def cmd_list(con: sqlite3.Connection, _args: argparse.Namespace) -> None:
    rows = con.execute(
        "SELECT id, display_name, session_key, message_count, started_at "
        "FROM sessions ORDER BY started_at DESC"
    ).fetchall()
    if not rows:
        print("no sessions")
        return
    for r in rows:
        print(f"{r['id']}  msgs={r['message_count']}  key={r['session_key'] or '-'}  "
              f"name={r['display_name'] or '-'}  started={r['started_at']}")


def cmd_dump(con: sqlite3.Connection, args: argparse.Namespace) -> None:
    sid = resolve_session(con, args.session)
    rows = con.execute(
        "SELECT role, content, timestamp FROM messages WHERE session_id = ? "
        "ORDER BY id DESC LIMIT ?",
        (sid, args.last),
    ).fetchall()
    for r in reversed(rows):
        content = r["content"] or ""
        if not args.full and len(content) > PREVIEW_CHARS:
            content = content[:PREVIEW_CHARS] + " …"
        print(f"[{r['timestamp']}] {r['role']}: {content}")


def cmd_grep(con: sqlite3.Connection, args: argparse.Namespace) -> None:
    """Verbatim substring search (AC-FW-04: verbatim-only check, no paraphrase)."""
    sql = ("SELECT m.session_id, m.role, m.timestamp, m.content FROM messages m "
           "WHERE instr(m.content, ?) > 0")
    params: list = [args.needle]
    if args.session:
        sql += " AND m.session_id = ?"
        params.append(resolve_session(con, args.session))
    rows = con.execute(sql + " ORDER BY m.id", params).fetchall()
    if not rows:
        print(f"NOT FOUND (verbatim): {args.needle!r}")
        sys.exit(1)
    for r in rows:
        idx = r["content"].index(args.needle)
        lo, hi = max(0, idx - 40), idx + len(args.needle) + 40
        print(f"session={r['session_id']} [{r['timestamp']}] {r['role']}: …{r['content'][lo:hi]}…")
    print(f"FOUND {len(rows)} verbatim occurrence(s)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--db", default=DEFAULT_DB, help=f"path to state.db (default: {DEFAULT_DB})")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("list", help="list sessions, newest first")

    p_dump = sub.add_parser("dump", help="print a session's recent messages")
    p_dump.add_argument("--session", required=True, help="session id, session_key, or display_name")
    p_dump.add_argument("--last", type=int, default=20, help="how many messages (default 20)")
    p_dump.add_argument("--full", action="store_true", help="print full message bodies")

    p_grep = sub.add_parser("grep", help="verbatim substring search across messages")
    p_grep.add_argument("--needle", required=True, help="exact string to find")
    p_grep.add_argument("--session", help="restrict to one session")

    args = parser.parse_args()
    con = connect(args.db)
    {"list": cmd_list, "dump": cmd_dump, "grep": cmd_grep}[args.command](con, args)


if __name__ == "__main__":
    main()
