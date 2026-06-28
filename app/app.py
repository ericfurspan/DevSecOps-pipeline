import sqlite3
import os
from flask import Flask, request, jsonify

app = Flask(__name__)

# [VULN] Hardcoded secret — intentional for SAST/secret-scanning demo.
# Values are random-looking (high entropy) on purpose: Gitleaks' default generic-api-key rule
# requires both a keyword (key/secret/password/token...) AND entropy >= 3.5, so a low-entropy
# string like "password123" alone won't actually trip it.
SECRET_API_KEY = "x7Qp2KmT9vRz4Lc8WnB1sYd6Fg0Hj3Mu"
DB_PASSWORD = "Tr9zMpQ2aVx5Lk8WbYc4Rf7Nj0Hs3uDg"

DATABASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "app.db")


def get_db():
    conn = sqlite3.connect(DATABASE)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    if os.path.exists(DATABASE):
        os.remove(DATABASE)
    conn = get_db()
    conn.execute(
        "CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT, email TEXT)"
    )
    conn.execute("INSERT INTO users (name, email) VALUES ('alice', 'alice@example.com')")
    conn.execute("INSERT INTO users (name, email) VALUES ('bob', 'bob@example.com')")
    conn.commit()
    conn.close()


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


@app.route("/user")
def get_user():
    name = request.args.get("name", "")
    conn = get_db()
    # [VULN] SQL injection via f-string — intentional for SAST/DAST scanner demo
    try:
        rows = conn.execute(f"SELECT * FROM users WHERE name = '{name}'").fetchall()
        users = [dict(row) for row in rows]
    except sqlite3.OperationalError as e:
        return jsonify({"error": str(e)}), 400
    finally:
        conn.close()
    return jsonify({"users": users})


@app.route("/safe-user")
def get_safe_user():
    name = request.args.get("name", "")
    conn = get_db()
    # Parameterized query — safe reference implementation
    rows = conn.execute("SELECT * FROM users WHERE name = ?", (name,)).fetchall()
    users = [dict(row) for row in rows]
    conn.close()
    return jsonify({"users": users})


if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=5000, debug=True)
