
from flask import Flask, jsonify
import os
import socket

app = Flask(__name__)

APP_VERSION = os.getenv("APP_VERSION", "1.0")
APP_COLOR = os.getenv("APP_COLOR", "blue")


@app.route("/")
def home():
    return jsonify({
        "message": "Zero Downtime Deployment Application",
        "version": APP_VERSION,
        "environment": APP_COLOR,
        "hostname": socket.gethostname(),
        "status": "Running Successfully"
    })


@app.route("/health")
def health():
    return jsonify({
        "status": "healthy",
        "version": APP_VERSION
    }), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
