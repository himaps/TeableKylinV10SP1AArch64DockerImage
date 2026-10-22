#!/usr/bin/env python
"""Poll public check-run status for a commit (no auth needed).
Usage: python tools/watch-ci.py <sha> [attempts] [interval_s]

SSRF guard: https only, host pinned to api.github.com, resolved IP checked
against private/reserved/loopback ranges, redirects not followed.
"""
import ipaddress
import json
import socket
import sys
import time
import urllib.parse
import urllib.request

HOST = "api.github.com"
SHA = sys.argv[1]
ATTEMPTS = int(sys.argv[2]) if len(sys.argv) > 2 else 12
INTERVAL = int(sys.argv[3]) if len(sys.argv) > 3 else 45
URL = "https://%s/repos/himaps/TeableKylinV10SP1AArch64DockerImage/commits/%s/check-runs" % (HOST, SHA)


def check_url(url):
    parts = urllib.parse.urlsplit(url)
    if parts.scheme != "https" or parts.hostname != HOST:
        raise SystemExit("blocked non-allowlisted url: %s" % url)
    for ai in socket.getaddrinfo(parts.hostname, 443, proto=socket.IPPROTO_TCP):
        ip = ipaddress.ip_address(ai[4][0])
        if (ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved
                or ip.is_multicast or ip.is_unspecified):
            raise SystemExit("blocked: %s resolves to non-public %s" % (parts.hostname, ip))


def fetch():
    check_url(URL)
    req = urllib.request.Request(URL, headers={
        "Accept": "application/vnd.github+json",
        "User-Agent": "ci-watcher",
    })
    with urllib.request.urlopen(req, timeout=30) as r:
        if r.status != 200:
            raise SystemExit("HTTP %s" % r.status)
        return json.load(r)


for attempt in range(1, ATTEMPTS + 1):
    try:
        data = fetch()
        runs = data.get("check_runs", [])
        if not runs:
            print("[%d] no check-runs yet" % attempt)
        else:
            done = True
            for cr in runs:
                print("[%d] %s: %s / %s" % (attempt, cr["name"], cr["status"], cr.get("conclusion")))
                if cr["status"] != "completed":
                    done = False
            if done:
                print("ALL COMPLETED")
                sys.exit(0)
    except Exception as e:  # network is intermittent on this host
        print("[%d] fetch error: %s" % (attempt, e))
    time.sleep(INTERVAL)
print("TIMEOUT waiting for completion")
sys.exit(1)
