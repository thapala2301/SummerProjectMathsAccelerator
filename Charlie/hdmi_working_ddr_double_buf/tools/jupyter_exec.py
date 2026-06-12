#!/usr/bin/env python3

import argparse
import json
import os
import re
import sys
import time
import uuid

import requests
import websocket


def get_xsrf(html):
    match = re.search(r'name=["\']_xsrf["\']\s+value=["\']([^"\']+)["\']', html)
    if not match:
        raise RuntimeError("Could not find Jupyter _xsrf token")
    return match.group(1)


def login(session, base_url, password):
    login_url = f"{base_url}/login"
    response = session.get(login_url, timeout=10)
    response.raise_for_status()
    xsrf = get_xsrf(response.text)
    response = session.post(
        login_url,
        data={"_xsrf": xsrf, "password": password},
        headers={"Referer": login_url},
        timeout=10,
    )
    response.raise_for_status()
    if "login" in response.url.rstrip("/").split("/")[-1].lower():
        raise RuntimeError("Jupyter login did not complete")
    return xsrf


def start_kernel(session, base_url, xsrf):
    response = session.post(
        f"{base_url}/api/kernels",
        headers={"X-XSRFToken": xsrf},
        json={},
        timeout=10,
    )
    response.raise_for_status()
    return response.json()["id"]


def stop_kernel(session, base_url, xsrf, kernel_id):
    try:
        session.delete(
            f"{base_url}/api/kernels/{kernel_id}",
            headers={"X-XSRFToken": xsrf},
            timeout=5,
        )
    except requests.RequestException:
        pass


def execute(base_url, session, kernel_id, code, timeout_s):
    cookies = "; ".join(f"{key}={value}" for key, value in session.cookies.items())
    ws_url = base_url.replace("http://", "ws://").replace("https://", "wss://")
    ws_url = f"{ws_url}/api/kernels/{kernel_id}/channels"
    ws = websocket.create_connection(ws_url, header=[f"Cookie: {cookies}"], timeout=10)

    msg_id = uuid.uuid4().hex
    message = {
        "header": {
            "msg_id": msg_id,
            "username": "codex",
            "session": uuid.uuid4().hex,
            "msg_type": "execute_request",
            "version": "5.3",
        },
        "parent_header": {},
        "metadata": {},
        "content": {
            "code": code,
            "silent": False,
            "store_history": False,
            "user_expressions": {},
            "allow_stdin": False,
            "stop_on_error": True,
        },
        "channel": "shell",
        "buffers": [],
    }
    ws.send(json.dumps(message))

    deadline = time.monotonic() + timeout_s
    status = "unknown"
    try:
        while time.monotonic() < deadline:
            raw = ws.recv()
            msg = json.loads(raw)
            parent = msg.get("parent_header", {})
            if parent.get("msg_id") != msg_id:
                continue

            msg_type = msg.get("msg_type") or msg.get("header", {}).get("msg_type")
            content = msg.get("content", {})

            if msg_type == "stream":
                print(content.get("text", ""), end="")
            elif msg_type in ("display_data", "execute_result"):
                data = content.get("data", {})
                if "text/plain" in data:
                    print(data["text/plain"])
            elif msg_type == "error":
                print("\n".join(content.get("traceback", [])))
                status = "error"
            elif msg_type == "execute_reply":
                status = content.get("status", "unknown")
                break
    finally:
        ws.close()

    if status != "ok":
        raise RuntimeError(f"Jupyter execution ended with status {status}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://192.168.137.238:9090")
    parser.add_argument("--timeout", type=float, default=120.0)
    parser.add_argument("script")
    args = parser.parse_args()

    password = os.environ.get("PYNQ_JUPYTER_PASSWORD")
    if not password:
        raise RuntimeError("Set PYNQ_JUPYTER_PASSWORD before running this helper")

    with open(args.script, "r", encoding="utf-8") as f:
        code = f.read()

    session = requests.Session()
    xsrf = login(session, args.base_url.rstrip("/"), password)
    kernel_id = start_kernel(session, args.base_url.rstrip("/"), xsrf)
    try:
        execute(args.base_url.rstrip("/"), session, kernel_id, code, args.timeout)
    finally:
        stop_kernel(session, args.base_url.rstrip("/"), xsrf, kernel_id)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
