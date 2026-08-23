#!/usr/bin/env python3
"""Download exactly the two official PP-OCRv5 mobile ONNX models."""

from __future__ import annotations

import argparse
from pathlib import Path
import shutil


MODEL_NAMES = (
    "PP-OCRv5_mobile_det_onnx",
    "PP-OCRv5_mobile_rec_onnx",
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--destination", type=Path, required=True)
    args = parser.parse_args()

    args.destination.mkdir(parents=True, exist_ok=True)
    for name in MODEL_NAMES:
        source = args.source.expanduser().resolve() / name
        destination = args.destination.resolve() / name
        if not (source / "inference.onnx").is_file():
            raise SystemExit(
                f"Missing {name}. Run adapter.py once with the official model names "
                "to let PaddleOCR download it, then retry."
            )
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(source, destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
