#!/usr/bin/env python3
"""Build the report as styled HTML and PDF using bundled Pandoc + Microsoft Edge."""

from __future__ import annotations

import pathlib
import subprocess
import sys
import time

import pypandoc

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs" / "stereo_block_matching_feasibility_report.md"
CSS = ROOT / "tools" / "report.css"
HTML = ROOT / "docs" / "stereo_block_matching_feasibility_report.html"
PDF = ROOT / "docs" / "stereo_block_matching_feasibility_report.pdf"
EDGE_CANDIDATES = [
    pathlib.Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"),
    pathlib.Path(r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"),
]


def main() -> int:
    if not SOURCE.exists():
        raise FileNotFoundError(SOURCE)

    source_text = SOURCE.read_text(encoding="utf-8")
    # The Markdown starts with a repository-friendly title block. The PDF gets
    # a dedicated cover, so begin the Pandoc body at the first separator.
    if "\n---\n" in source_text:
        source_text = source_text.split("\n---\n", 1)[1]

    pypandoc.convert_text(
        source_text,
        "html5",
        format="markdown+tex_math_dollars+tex_math_single_backslash",
        outputfile=str(HTML),
        extra_args=[
            "--standalone",
            "--toc",
            "--toc-depth=3",
            "--mathml",
            "--embed-resources",
            f"--css={CSS}",
            "--metadata=lang:en",
            "--metadata=pagetitle:Stereo Block-Matching Accelerator Report",
        ],
    )

    html_text = HTML.read_text(encoding="utf-8")
    cover = """
<section class="title-page">
  <div class="cover-kicker">DIGITAL SYSTEM DESIGN · SEMESTER PROJECT</div>
  <h1>Scalable Shared-Memory<br>Stereo Block-Matching Accelerator</h1>
  <p class="cover-subtitle">Architecture, Nios V integration, feasibility, dataset strategy, verification, and implementation roadmap</p>
  <div class="cover-rule"></div>
  <dl class="cover-meta">
    <dt>Target platform</dt><dd>Terasic DE2-115 · Cyclone IV EP4CE115</dd>
    <dt>Compute system</dt><dd>Nios V CPU + parameterized SAD accelerator + shared SDRAM</dd>
    <dt>Team</dt><dd>Three members</dd>
    <dt>Current progress</dt><dd>Nios V Hello World verified on the FPGA</dd>
  </dl>
  <p class="cover-note">Feasibility and architecture report</p>
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

    if PDF.exists():
        PDF.unlink()

    command = [
        str(edge),
        "--headless",
        "--disable-gpu",
        "--no-pdf-header-footer",
        f"--print-to-pdf={PDF}",
        HTML.resolve().as_uri(),
    ]
    completed = subprocess.run(command, check=False, capture_output=True, text=True)
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
