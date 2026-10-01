#!/usr/bin/env python3
"""Check the static site's local links and basic document accessibility."""

from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit


class Page(HTMLParser):
    def __init__(self, source):
        super().__init__()
        self.ids = set()
        self.links = []
        self.h1_count = 0
        self.lang = None
        self.viewport = False
        self.feed(source)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            assert attrs["id"] not in self.ids, f"Duplicate id: {attrs['id']}"
            self.ids.add(attrs["id"])
        if tag == "html":
            self.lang = attrs.get("lang")
        if tag == "h1":
            self.h1_count += 1
        if tag == "meta" and attrs.get("name") == "viewport":
            self.viewport = True
        if tag == "img":
            assert "alt" in attrs, "Image needs an alt attribute"
        for name in ("href", "src"):
            if name in attrs:
                self.links.append(attrs[name])


def main():
    root = Path(__file__).resolve().parents[1] / "docs/site"
    for required in ("index.html", "support.html", "privacy.html"):
        assert (root / required).is_file(), f"Missing {required}"
    pages = {p.resolve(): Page(p.read_text()) for p in root.rglob("*.html")}
    for path, page in pages.items():
        assert page.lang == "ja", f"{path.name}: missing Japanese language"
        assert page.h1_count == 1, f"{path.name}: expected one h1"
        assert page.viewport, f"{path.name}: missing mobile viewport"
        for link in page.links:
            assert link.strip(), f"{path.name}: empty link"
            url = urlsplit(link)
            if url.scheme or url.netloc:
                assert url.scheme in ("https", "mailto", "data"), f"Unsafe URL: {link}"
                continue
            assert not url.path.startswith("/"), f"Project Pages needs relative links: {link}"
            target = (path.parent / unquote(url.path)).resolve() if url.path else path
            assert target.is_relative_to(root.resolve()), f"Link escapes site: {link}"
            if target.is_dir():
                target /= "index.html"
            assert target.is_file(), f"{path.name}: missing target {link}"
            if url.fragment and target in pages:
                assert unquote(url.fragment) in pages[target].ids, f"Broken anchor: {link}"
    print(f"Website verified: {len(pages)} pages, local links, images, anchors, document basics")


if __name__ == "__main__":
    main()
