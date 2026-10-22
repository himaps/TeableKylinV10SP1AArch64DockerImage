#!/usr/bin/env python
"""Sum compressed layer sizes of an image on the Aliyun mirror.
Usage: python tools/image-size.py <repo> <tag> [tag2 ...]

SSRF guard: https only, host pinned to the fixed registry, and the
resolved IP is checked against private/reserved/loopback ranges before
every request; redirects are not followed.
"""
import ipaddress
import json
import socket
import sys
import urllib.parse

REGISTRY = "registry.cn-shenzhen.aliyuncs.com"
AUTH_HOST = "dockerauth.cn-hangzhou.aliyuncs.com"
AUTH = "https://%s/auth?service=registry.aliyuncs.com:cn-shenzhen:26842" % AUTH_HOST
ACCEPT = ", ".join([
    "application/vnd.docker.distribution.manifest.v2+json",
    "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
    "application/vnd.oci.image.index.v1+json",
])
ALLOWED_HOSTS = {REGISTRY, AUTH_HOST}


def check_url(url):
    parts = urllib.parse.urlsplit(url)
    if parts.scheme != "https" or parts.hostname not in ALLOWED_HOSTS:
        raise SystemExit("blocked non-allowlisted url: %s" % url)
    addrs = {ai[4][0] for ai in socket.getaddrinfo(parts.hostname, 443, proto=socket.IPPROTO_TCP)}
    for a in addrs:
        ip = ipaddress.ip_address(a)
        if (ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved
                or ip.is_multicast or ip.is_unspecified):
            raise SystemExit("blocked: %s resolves to non-public %s" % (parts.hostname, a))


def get(url, token=None, accept=ACCEPT):
    check_url(url)
    # no redirects followed: urlopen raises on 3xx without a custom opener
    import urllib.request
    req = urllib.request.Request(url, headers={"Accept": accept})
    if token:
        req.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(req, timeout=30) as r:
        if r.status != 200:
            raise SystemExit("HTTP %s for %s" % (r.status, url))
        return json.load(r)


def size_of(repo, tag):
    tok = get(AUTH + "&scope=repository:%s:pull" % repo, accept="application/json")["token"]
    m = get("https://%s/v2/%s/manifests/%s" % (REGISTRY, repo, tag), tok)
    if "manifests" in m:  # index/list -> follow arm64
        arm = [mi for mi in m["manifests"]
               if mi.get("platform", {}).get("architecture") == "arm64"]
        if not arm:
            raise SystemExit("%s:%s has no arm64 entry" % (repo, tag))
        m = get("https://%s/v2/%s/manifests/%s" % (REGISTRY, repo, arm[0]["digest"]), tok)
    total = sum(l["size"] for l in m.get("layers", []))
    print("%s:%s  layers=%d  compressed=%.2f GiB" %
          (repo, tag, len(m.get("layers", [])), total / 1024 ** 3))


for arg in sys.argv[1:]:
    repo, tag = arg.rsplit(":", 1)
    size_of(repo, tag)
