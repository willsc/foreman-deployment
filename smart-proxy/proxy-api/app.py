from flask import Flask, jsonify
import os

app = Flask(__name__)


def features():
    names = ["tftp", "httpboot"]
    if os.environ.get("PROXY_DHCP_MODE", "managed") in {"managed", "external"}:
        names.append("dhcp")
    return names


def feature_map():
    result = {}
    for name in features():
        settings = {}
        if name == "httpboot":
            settings = {"http_port": 8081}
        result[name] = {
            "capabilities": [],
            "settings": settings,
            "state": "running",
        }
    return result


@app.get("/")
def root():
    return jsonify({"service": "custom-smart-proxy-api", "status": "ok"})


@app.get("/version")
def version():
    return jsonify({"version": "3.18-custom"})


@app.get("/features")
def feature_list_v1():
    return jsonify(features())


@app.get("/v2/features")
def feature_list_v2():
    return jsonify(feature_map())
