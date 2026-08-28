#!/usr/bin/env python3
"""Build the detailed design-hierarchy specification as HTML and PDF."""

from __future__ import annotations

import pathlib
import subprocess
import sys
import time

import pypandoc

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs" / "design_hierarchy.md"
CSS = ROOT / "tools" / "report.css"
HTML = ROOT / "docs" / "design_hierarchy.html"
PDF = ROOT / "docs" / "design_hierarchy.pdf"
EDGE_CANDIDATES = [
    pathlib.Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"),
    pathlib.Path(r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"),
]


def main() -> int:
    if not SOURCE.exists():
        raise FileNotFoundError(SOURCE)

    pypandoc.convert_file(
        str(SOURCE),
        "html5",
        format="markdown+tex_math_dollars+tex_math_single_backslash",
        outputfile=str(HTML),
        extra_args=[
            "--standalone",
            "--toc",
            "--toc-depth=3",
            "--mathml",
            "--embed-resources",
            f"--resource-path={ROOT / 'docs'}",
            f"--css={CSS}",
            "--metadata=lang:en",
            "--metadata=pagetitle:Top-Down Stereo Accelerator Design Hierarchy",
        ],
    )

    html_text = HTML.read_text(encoding="utf-8")
    cover = """
<section class="title-page">
  <div class="cover-kicker">DIGITAL SYSTEM DESIGN · ARCHITECTURE SPECIFICATION</div>
  <h1>Top-Down Design Hierarchy</h1>
  <p class="cover-subtitle">Scalable shared-memory stereo block-matching accelerator: responsibilities, interfaces, implementation contracts, verification, and integration gates</p>
  <div class="cover-rule"></div>
  <dl class="cover-meta">
    <dt>Target platform</dt><dd>Terasic DE2-115 · Cyclone IV EP4CE115</dd>
    <dt>Compute system</dt><dd>Nios V CPU + parameterized SAD accelerator + shared SDRAM</dd>
    <dt>Abstraction</dt><dd>System mission → partition → subsystems → datapath → RTL → build gates</dd>
    <dt>Team</dt><dd>Three members with explicit integration boundaries</dd>
  </dl>
  <p class="cover-note">Top-down architecture and implementation specification</p>
</section>
"""
    toc_marker = '<nav id="TOC" role="doc-toc">'
    if toc_marker not in html_text:
        toc_marker = '<nav id="TOC">'
    html_text = html_text.replace(toc_marker, cover + toc_marker, 1)
    HTML.write_text(html_text, encoding="utf-8")

    edge = next((path for path in EDGE_CANDIDATES if path.exists()), None)
    if edge is None:
        print(f"HTML generated at {HTML}")
        print("Microsoft Edge was not found; PDF was not generated.", file=sys.stderr)
        return 2

    PDF.unlink(missing_ok=True)
    completed = subprocess.run(
        [
            str(edge),
            "--headless",
            "--disable-gpu",
            "--no-pdf-header-footer",
            f"--print-to-pdf={PDF}",
            HTML.resolve().as_uri(),
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        print(completed.stdout)
        print(completed.stderr, file=sys.stderr)
        return completed.returncode

    for _ in range(40):
        if PDF.exists() and PDF.stat().st_size > 1000:
            print(f"Generated {PDF} ({PDF.stat().st_size} bytes)")
            return 0
        time.sleep(0.25)

    print("Edge exited but the PDF did not appear.", file=sys.stderr)
    return 3


if __name__ == "__main__":
    raise SystemExit(main())
