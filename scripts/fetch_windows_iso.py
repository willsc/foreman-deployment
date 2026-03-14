#!/usr/bin/env python3
import argparse
import json
import re
import sys
import urllib.parse
import urllib.request


def get(url: str) -> str:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/134.0 Safari/537.36",
            "Accept-Language": "en-US,en;q=0.9",
        },
    )
    with urllib.request.urlopen(req, timeout=60) as response:
        return response.read().decode("utf-8", errors="ignore")


def extract_json_blob(html: str) -> dict:
    patterns = [
        r"window\.__INITIAL_STATE__\s*=\s*({.*?})\s*;</script>",
        r"window\.__NEXT_DATA__\s*=\s*({.*?})\s*;</script>",
    ]
    for pattern in patterns:
      match = re.search(pattern, html, re.DOTALL)
      if match:
          try:
              return json.loads(match.group(1))
          except json.JSONDecodeError:
              continue
    return {}


def walk(obj):
    if isinstance(obj, dict):
        for key, value in obj.items():
            yield key, value
            yield from walk(value)
    elif isinstance(obj, list):
        for item in obj:
            yield from walk(item)


def find_iso_link(data: dict) -> str | None:
    for key, value in walk(data):
        if isinstance(value, str) and "software-download.microsoft.com" in value and value.lower().endswith(".iso"):
            return value
        if isinstance(value, str) and "download.windowsupdate.com" in value and value.lower().endswith(".iso"):
            return value
    return None


def find_href_in_html(html: str) -> str | None:
    for match in re.finditer(r'href="([^"]+\.iso[^"]*)"', html, re.IGNORECASE):
        href = urllib.parse.unquote(match.group(1))
        if "microsoft" in href or "windowsupdate" in href:
            return href
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--download-page", required=True)
    parser.add_argument("--language", default="English International")
    args = parser.parse_args()

    html = get(args.download_page)
    data = extract_json_blob(html)
    link = find_iso_link(data) if data else None
    if not link:
        link = find_href_in_html(html)
    if not link:
        return 1

    sys.stdout.write(link)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
