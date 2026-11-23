import base64
import hmac
import json
import os
import re
import secrets
import sqlite3
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

if __name__ == "__main__" and sys.argv[1:] == ["keys"]:
    print("KOI_TOKEN_A=" + secrets.token_urlsafe(32))
    print("KOI_TOKEN_B=" + secrets.token_urlsafe(32))
    print("Shared message key (enter on both Macs, not on server): "
          + base64.b64encode(secrets.token_bytes(32)).decode())
    raise SystemExit

TOKENS = tuple(os.environ.get(f"KOI_TOKEN_{side}", "") for side in ("A", "B"))
SOCIAL_IDS = re.compile(r"[a-zA-Z0-9_-]{1,48}\Z")
SOCIAL = json.loads(os.environ.get("KOI_FRIEND_MAILBOXES", "{}"))
DATABASE = os.environ.get("KOI_DATABASE", "koi-mailbox.sqlite3")
MESSAGE_ID = re.compile(r"[0-9a-fA-F-]{36}\Z")


def database():
    return sqlite3.connect(DATABASE, timeout=5)


class Mailbox(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def respond(self, status, value=None):
        data = json.dumps(value, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def account(self):
        authorization = self.headers.get("Authorization", "").encode()
        for index, token in enumerate(TOKENS):
            if token and hmac.compare_digest(authorization, ("Bearer " + token).encode()):
                return index
        self.respond(401)
        return None

    def social_user(self):
        authorization = self.headers.get("Authorization", "").encode()
        for user, token in SOCIAL.items():
            if hmac.compare_digest(authorization, ("Bearer " + token).encode()):
                return user
        self.respond(401)
        return None

    def social_message(self, method):
        user = self.social_user()
        if user is None:
            return
        if method == "GET" and self.path == "/friends":
            with database() as db:
                rows = db.execute(
                    "SELECT id, sender, payload FROM friend_mail WHERE recipient=? ORDER BY rowid",
                    (user,),
                ).fetchall()
            self.respond(200, [dict(zip(("id", "sender", "payload"), row)) for row in rows])
            return
        target = self.path.removeprefix("/friends/")
        if method == "DELETE" and MESSAGE_ID.fullmatch(target):
            with database() as db:
                db.execute("DELETE FROM friend_mail WHERE recipient=? AND id=?", (user, target))
            self.respond(200)
            return
        if method != "POST" or target not in SOCIAL or target == user:
            self.respond(404)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 4096:
                self.respond(413)
                return
            envelope = json.loads(self.rfile.read(length))
            message_id, payload = envelope["id"], envelope["payload"]
            if not MESSAGE_ID.fullmatch(message_id) or not 28 <= len(base64.b64decode(payload, validate=True)) <= 2048:
                raise ValueError
        except (ValueError, TypeError, KeyError):
            self.respond(400)
            return
        with database() as db:
            db.execute("BEGIN IMMEDIATE")
            existing = db.execute(
                "SELECT 1 FROM friend_mail WHERE recipient=? AND sender=? AND id=?", (target, user, message_id)
            ).fetchone()
            queued = db.execute("SELECT COUNT(*) FROM friend_mail WHERE recipient=? AND sender=?",
                                (target, user)).fetchone()[0]
            if existing:
                status = 200
            elif queued >= 50:
                status = 429
            else:
                db.execute("INSERT INTO friend_mail VALUES (?, ?, ?, ?)", (target, user, message_id, payload))
                status = 201
        self.respond(status)

    def do_GET(self):
        if self.path == "/friends" or self.path.startswith("/friends/"):
            self.social_message("GET")
            return
        user = self.account()
        if user is None:
            return
        if self.path == "/pair":
            with database() as db:
                db.execute("INSERT OR IGNORE INTO partner VALUES (?, unixepoch())", (user,))
                count, start, now = db.execute(
                    "SELECT COUNT(*), MAX(joined), unixepoch() FROM partner"
                ).fetchone()
                sent = db.execute("SELECT MAX(sent) FROM gifts WHERE sender=?", (user,)).fetchone()[0]
            self.respond(200, {"linkedSince": start if count == 2 else None,
                               "serverTime": now, "giftAfter": sent + 604800 if sent else 0})
            return
        if self.path == "/gifts":
            with database() as db:
                rows = db.execute("SELECT id, payload FROM gifts WHERE sender=? ORDER BY sent",
                                  (1 - user,)).fetchall()
            self.respond(200, [dict(zip(("id", "payload"), row)) for row in rows])
            return
        if self.path != "/messages":
            self.respond(404)
            return
        with database() as db:
            row = db.execute(
                "SELECT id, payload FROM mail WHERE recipient=? AND payload IS NOT NULL ORDER BY rowid LIMIT 1",
                (user,),
            ).fetchone()
        self.respond(200, dict(zip(("id", "payload"), row)) if row else None)

    def do_POST(self):
        if self.path == "/friends" or self.path.startswith("/friends/"):
            self.social_message("POST")
            return
        user = self.account()
        if user is None:
            return
        if self.path not in ("/messages", "/gifts"):
            self.respond(404)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 4096:
                self.respond(413)
                return
            item = json.loads(self.rfile.read(length))
            message_id, payload = item["id"], item["payload"]
            if not MESSAGE_ID.fullmatch(message_id) or not 28 <= len(base64.b64decode(payload, validate=True)) <= 2048:
                raise ValueError
        except (ValueError, KeyError, TypeError):
            self.respond(400)
            return
        if self.path == "/gifts":
            with database() as db:
                db.execute("BEGIN IMMEDIATE")
                already = db.execute("SELECT 1 FROM gifts WHERE sender=? AND id=?",
                                     (user, message_id)).fetchone()
                recent = db.execute("SELECT 1 FROM gifts WHERE sender=? AND sent > unixepoch() - 604800",
                                     (user,)).fetchone()
                linked = db.execute("SELECT COUNT(*) FROM partner").fetchone()[0] == 2
                if already:
                    status = 200
                elif not linked:
                    status = 409
                elif recent:
                    status = 429
                else:
                    db.execute("INSERT INTO gifts VALUES (?, ?, ?, unixepoch())",
                               (user, message_id, payload))
                    status = 201
            self.respond(status)
            return
        recipient = 1 - user
        with database() as db:
            db.execute("BEGIN IMMEDIATE")
            duplicate = db.execute("SELECT 1 FROM mail WHERE recipient=? AND id=?", (recipient, message_id)).fetchone()
            queued = db.execute(
                "SELECT COUNT(*) FROM mail WHERE recipient=? AND payload IS NOT NULL", (recipient,)
            ).fetchone()[0]
            if duplicate:
                status = 200
            elif queued >= 100:
                status = 429
            else:
                db.execute("INSERT INTO mail VALUES (?, ?, ?, NULL)", (recipient, message_id, payload))
                status = 201
        self.respond(status)

    def do_DELETE(self):
        if self.path == "/friends" or self.path.startswith("/friends/"):
            self.social_message("DELETE")
            return
        user = self.account()
        if user is None:
            return
        message_id = self.path.removeprefix("/messages/")
        if not self.path.startswith("/messages/") or not MESSAGE_ID.fullmatch(message_id):
            self.respond(404)
            return
        with database() as db:
            db.execute(
                "UPDATE mail SET payload=NULL, dismissed=unixepoch() WHERE recipient=? AND id=? AND payload IS NOT NULL",
                (user, message_id),
            )
            db.execute("DELETE FROM mail WHERE dismissed < unixepoch() - 604800")
        self.respond(200)


if __name__ == "__main__":
    if not isinstance(SOCIAL, dict) or any(
        not SOCIAL_IDS.fullmatch(name) or not isinstance(token, str) or len(token) < 32
        for name, token in SOCIAL.items()
    ) or len(set(SOCIAL.values())) != len(SOCIAL):
        sys.exit("Set KOI_FRIEND_MAILBOXES to a JSON object of mailbox IDs and distinct private tokens.")
    if (any(TOKENS) or not SOCIAL) and (any(len(token) < 32 for token in TOKENS) or TOKENS[0] == TOKENS[1]):
        sys.exit("Set two distinct tokens generated with python3 relay.py keys.")
    os.umask(0o077)
    with database() as db:
        db.execute("""CREATE TABLE IF NOT EXISTS mail(
            recipient INTEGER NOT NULL, id TEXT NOT NULL, payload TEXT, dismissed INTEGER,
            PRIMARY KEY(recipient, id)
        )""")
        db.execute("CREATE TABLE IF NOT EXISTS partner (side INTEGER PRIMARY KEY, joined INTEGER NOT NULL)")
        db.execute("""CREATE TABLE IF NOT EXISTS gifts (
            sender INTEGER NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL, sent INTEGER NOT NULL,
            PRIMARY KEY(sender, id)
        )""")
        db.execute("CREATE INDEX IF NOT EXISTS gifts_by_sender_time ON gifts(sender, sent)")
        db.execute("""CREATE TABLE IF NOT EXISTS friend_mail (
            recipient TEXT NOT NULL, sender TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL,
            PRIMARY KEY(recipient, sender, id)
        )""")
    ThreadingHTTPServer(("127.0.0.1", int(os.environ.get("KOI_PORT", 8765))), Mailbox).serve_forever()
