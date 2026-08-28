#!/usr/bin/env python3
"""Compile all standalone TikZ diagrams and render PNG copies for the report."""

from __future__ import annotations

import os
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
DIAGRAM_DIR = ROOT / "docs" / "diagrams"
DIAGRAMS = (
    "design_hierarchy",
    "system_architecture",
    "accelerator_hierarchy",
    "accelerator_pipeline",
    "sad_datapath_hierarchy",
    "rtl_module_tree",
    "execution_flow",
)


def find_tectonic() -> pathlib.Path:
    candidates = [
        os.environ.get("TECTONIC"),
        shutil.which("tectonic"),
        pathlib.Path.home()
        / "AppData/Local/fabric/cache/tectonic-0.17.0/tectonic.exe",
    ]
    for candidate in candidates:
        if candidate and pathlib.Path(candidate).exists():
            return pathlib.Path(candidate)
    raise FileNotFoundError(
        "Tectonic was not found. Install it or set the TECTONIC environment variable."
    )


def main() -> int:
    try:
        import pymupdf
    except ImportError as exc:
        raise RuntimeError("PyMuPDF is required for PNG rendering: pip install pymupdf") from exc

    tectonic = find_tectonic()
    for name in DIAGRAMS:
        source = DIAGRAM_DIR / f"{name}.tex"
        subprocess.run(
            [str(tectonic), "-X", "compile", source.name],
            cwd=DIAGRAM_DIR,
            check=True,
        )
        pdf = DIAGRAM_DIR / f"{name}.pdf"
        document = pymupdf.open(pdf)
        try:
            if document.page_count != 1:
                raise RuntimeError(f"{pdf} has {document.page_count} pages; expected one")
            pixmap = document[0].get_pixmap(
                matrix=pymupdf.Matrix(2.2, 2.2), alpha=False
            )
            png = DIAGRAM_DIR / f"{name}.png"
            pixmap.save(png)
            print(f"Generated {pdf.name} and {png.name}")
        finally:
            document.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
