#!/usr/bin/env python3
import os
import secrets
from pathlib import Path

from flask import Flask, jsonify, render_template, request
from pymongo import MongoClient
from pymongo.errors import PyMongoError

# --------------------------------------------------
# Paths and application setup
# --------------------------------------------------

ENV_FILE = Path(os.environ.get("SERVICE9_ENV_FILE", "/etc/hackshield/service9.env"))

app = Flask(__name__)


def load_env_file():
    config = {}
    if ENV_FILE.exists():
        try:
            for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                config[key.strip()] = value.strip()
        except OSError:
            pass
    return config


CONFIG = load_env_file()
MONGO_URI = os.environ.get(
    "MONGO_URI",
    CONFIG.get("MONGO_URI", "mongodb://127.0.0.1:27017/")
)
DB_NAME = os.environ.get(
    "MONGO_DB_NAME",
    CONFIG.get("MONGO_DB_NAME", "blockstar_internal")
)
COLLECTION_NAME = "builds"

mongo_client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=3000)
db = mongo_client[DB_NAME]
builds = db[COLLECTION_NAME]


# --------------------------------------------------
# Portal UI & Health Check
# --------------------------------------------------

@app.get("/")
def home():
    return render_template("index.html")


@app.get("/health")
def health():
    return {"status": "ok"}


# --------------------------------------------------
# Repository Catalog API
# --------------------------------------------------

@app.get("/api/builds")
def list_builds():
    catalog = []
    try:
        cursor = builds.find(
            {"active": {"$ne": False}},
            {
                "_id": 0,
                "game_id": 1,
                "name": 1,
                "build": 1,
                "platform": 1,
                "size_mb": 1,
                "classified": 1,
            },
        ).sort("display_order", 1)

        for doc in cursor:
            if doc.get("classified"):
                catalog.append({
                    "game_id": doc["game_id"],
                    "name": "CLASSIFIED PROJECT",
                    "build": "ACCESS RESTRICTED",
                    "platform": "—",
                    "size_mb": None,
                    "classified": True,
                })
            else:
                catalog.append(doc)
    except PyMongoError:
        return jsonify({"status": "error", "message": "Database unavailable."}), 500

    return jsonify({"builds": catalog})


# --------------------------------------------------
# Build Manifest Dispatch API
# --------------------------------------------------

@app.post("/api/download_build")
def download_build():
    payload = request.get_json(silent=True)
    if not payload:
        return jsonify({"status": "error", "message": "Expected a JSON body."}), 400

    game_id = payload.get("game_id")
    dev_token = payload.get("dev_token")

    if game_id is None or dev_token is None:
        return jsonify({
            "status": "error",
            "message": "Both 'game_id' and 'dev_token' are required.",
        }), 400

    try:
        record = builds.find_one({"game_id": game_id, "dev_token": dev_token})
    except PyMongoError:
        return jsonify({"status": "error", "message": "Lookup failed."}), 500

    if not record:
        return jsonify({
            "status": "error",
            "message": "No build found for that game ID / dev token combination.",
        }), 404

    response = {
        "status": "success",
        "message": "Build access granted.",
        "game": record.get("name"),
        "build": record.get("build"),
        "download_url": (
            f"https://cdn.blockstar-internal.local/builds/"
            f"{record.get('game_id')}/package.zip?sig={secrets.token_hex(16)}"
        ),
    }
    if record.get("classified"):
        response["flag"] = record.get("flag")

    return jsonify(response)


# --------------------------------------------------
# Error handling
# --------------------------------------------------

@app.errorhandler(404)
def not_found(_error):
    return jsonify({"status": "error", "message": "Endpoint not found"}), 404


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5002))
    app.run(host="0.0.0.0", port=port, threaded=True, debug=False)
