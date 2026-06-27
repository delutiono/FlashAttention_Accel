#!/usr/bin/env python3
"""Parse a Genus report directory into a compact PPA summary."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


REPORT_FILES = {
    "area": "area.rpt",
    "timing": "timing.rpt",
    "power": "power.rpt",
    "qor": "qor.rpt",
    "check_design": "check_design.rpt",
}

FLOAT_RE = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"


def _read_text(path: Path) -> str | None:
    if not path.is_file():
        return None
    return path.read_text(encoding="utf-8", errors="replace")


def _missing(path: Path) -> dict[str, Any]:
    return {"status": "missing", "path": str(path)}


def _first_float(patterns: list[str], text: str) -> float | None:
    for pattern in patterns:
        match = re.search(pattern, text, flags=re.IGNORECASE | re.MULTILINE)
        if match:
            return float(match.group(1))
    return None


def _first_int(patterns: list[str], text: str) -> int | None:
    for pattern in patterns:
        match = re.search(pattern, text, flags=re.IGNORECASE | re.MULTILINE)
        if match:
            return int(match.group(1))
    return None


def _parse_area(path: Path) -> dict[str, Any]:
    text = _read_text(path)
    if text is None:
        return _missing(path)
    return {
        "status": "ok",
        "path": str(path),
        "instance_count": _first_int(
            [
                r"\b(?:instance|inst(?:ance)?s?)\s*(?:count)?\s*[:=]\s*(\d+)",
                r"\bnumber\s+of\s+instances\s*[:=]\s*(\d+)",
            ],
            text,
        ),
        "combinational_area": _first_float(
            [rf"\bcombinational\s+area\s*[:=]?\s*({FLOAT_RE})"],
            text,
        ),
        "noncombinational_area": _first_float(
            [
                rf"\bnon[-\s]?combinational\s+area\s*[:=]?\s*({FLOAT_RE})",
                rf"\bsequential\s+area\s*[:=]?\s*({FLOAT_RE})",
            ],
            text,
        ),
        "net_area": _first_float([rf"\bnet\s+area\s*[:=]?\s*({FLOAT_RE})"], text),
        "total_cell_area": _first_float(
            [
                rf"\btotal\s+cell\s+area\s*[:=]?\s*({FLOAT_RE})",
                rf"\bcell\s+area\s*[:=]?\s*({FLOAT_RE})",
                rf"\btotal\s+area\s*[:=]?\s*({FLOAT_RE})",
            ],
            text,
        ),
    }


def _parse_timing(path: Path) -> dict[str, Any]:
    text = _read_text(path)
    if text is None:
        return _missing(path)

    explicit_wns = _first_float(
        [
            rf"\bWNS(?:\s*\([^)]*\))?\s*[:=]\s*({FLOAT_RE})",
            rf"\bworst\s+negative\s+slack\s*[:=]\s*({FLOAT_RE})",
        ],
        text,
    )
    explicit_tns = _first_float(
        [
            rf"\bTNS(?:\s*\([^)]*\))?\s*[:=]\s*({FLOAT_RE})",
            rf"\btotal\s+negative\s+slack\s*[:=]\s*({FLOAT_RE})",
        ],
        text,
    )
    slack_values = [
        float(value)
        for value in re.findall(
            rf"\bslack\b(?:\s*\([^)]*\))?\s*[:=]?\s*({FLOAT_RE})",
            text,
            flags=re.IGNORECASE,
        )
    ]
    wns = explicit_wns if explicit_wns is not None else (min(slack_values) if slack_values else None)
    tns = explicit_tns if explicit_tns is not None else (sum(value for value in slack_values if value < 0.0) if slack_values else None)
    violating_paths = _first_int(
        [
            r"\b(?:num(?:ber)?\s+of\s+)?violating\s+paths\s*[:=]\s*(\d+)",
            r"\bviolations\s*[:=]\s*(\d+)",
        ],
        text,
    )
    if violating_paths is None and slack_values:
        violating_paths = sum(1 for value in slack_values if value < 0.0)

    return {
        "status": "ok",
        "path": str(path),
        "wns": wns,
        "tns": tns,
        "violating_paths": violating_paths,
    }


def _parse_power(path: Path) -> dict[str, Any]:
    text = _read_text(path)
    if text is None:
        return _missing(path)
    return {
        "status": "ok",
        "path": str(path),
        "internal_power": _first_float([rf"\binternal\s+power\s*[:=]?\s*({FLOAT_RE})"], text),
        "switching_power": _first_float(
            [
                rf"\bswitching\s+power\s*[:=]?\s*({FLOAT_RE})",
                rf"\bdynamic\s+power\s*[:=]?\s*({FLOAT_RE})",
            ],
            text,
        ),
        "leakage_power": _first_float([rf"\bleakage\s+power\s*[:=]?\s*({FLOAT_RE})"], text),
        "total_power": _first_float([rf"\btotal\s+power\s*[:=]?\s*({FLOAT_RE})"], text),
    }


def _parse_qor(path: Path) -> dict[str, Any]:
    text = _read_text(path)
    if text is None:
        return _missing(path)
    return {
        "status": "ok",
        "path": str(path),
        "wns": _first_float([rf"\bWNS(?:\s*\([^)]*\))?\s*[:=]\s*({FLOAT_RE})"], text),
        "tns": _first_float([rf"\bTNS(?:\s*\([^)]*\))?\s*[:=]\s*({FLOAT_RE})"], text),
        "violating_paths": _first_int([r"\bviolating\s+paths\s*[:=]\s*(\d+)"], text),
        "cell_area": _first_float(
            [
                rf"\bcell\s+area\s*[:=]\s*({FLOAT_RE})",
                rf"\btotal\s+cell\s+area\s*[:=]\s*({FLOAT_RE})",
            ],
            text,
        ),
    }


def _parse_check_design(path: Path) -> dict[str, Any]:
    text = _read_text(path)
    if text is None:
        report = _missing(path)
        report["clean"] = False
        return report

    error_count = _first_int([r"\berrors?\s*[:=]\s*(\d+)"], text)
    warning_count = _first_int([r"\bwarnings?\s*[:=]\s*(\d+)"], text)
    if error_count is None:
        error_count = len(re.findall(r"^\s*(?:error|err)\b", text, flags=re.IGNORECASE | re.MULTILINE))
    if warning_count is None:
        warning_count = len(re.findall(r"^\s*(?:warning|warn)\b", text, flags=re.IGNORECASE | re.MULTILINE))

    return {
        "status": "ok",
        "path": str(path),
        "error_count": error_count,
        "warning_count": warning_count,
        "clean": error_count == 0 and warning_count == 0,
    }


def parse_report_dir(report_dir: Path | str) -> dict[str, Any]:
    """Parse known Genus reports below *report_dir*."""

    root = Path(report_dir)
    reports = {
        "area": _parse_area(root / REPORT_FILES["area"]),
        "timing": _parse_timing(root / REPORT_FILES["timing"]),
        "power": _parse_power(root / REPORT_FILES["power"]),
        "qor": _parse_qor(root / REPORT_FILES["qor"]),
        "check_design": _parse_check_design(root / REPORT_FILES["check_design"]),
    }
    area = reports["area"].get("total_cell_area")
    if area is None:
        area = reports["qor"].get("cell_area")
    wns = reports["qor"].get("wns")
    if wns is None:
        wns = reports["timing"].get("wns")
    tns = reports["qor"].get("tns")
    if tns is None:
        tns = reports["timing"].get("tns")
    total_power = reports["power"].get("total_power")

    return {
        "report_dir": str(root),
        "reports": reports,
        "summary": {
            "area": area,
            "wns": wns,
            "tns": tns,
            "total_power": total_power,
            "timing_violating_paths": reports["qor"].get("violating_paths")
            if reports["qor"].get("violating_paths") is not None
            else reports["timing"].get("violating_paths"),
            "check_design_clean": bool(reports["check_design"].get("clean")),
            "missing_reports": [name for name, report in reports.items() if report["status"] == "missing"],
        },
    }


def format_text_summary(payload: dict[str, Any]) -> str:
    summary = payload["summary"]
    lines = [
        f"REPORT_DIR {payload['report_dir']}",
        (
            "SUMMARY "
            f"area={summary['area']} "
            f"wns={summary['wns']} "
            f"tns={summary['tns']} "
            f"total_power={summary['total_power']} "
            f"violating_paths={summary['timing_violating_paths']} "
            f"check_design_clean={str(summary['check_design_clean']).lower()}"
        ),
    ]
    if summary["missing_reports"]:
        lines.append("MISSING " + ",".join(summary["missing_reports"]))
    for name, report in payload["reports"].items():
        lines.append(f"REPORT {name} status={report['status']} path={report['path']}")
    return "\n".join(lines)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report_dir", type=Path, help="Directory containing area/timing/power/qor/check_design reports")
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON")
    parser.add_argument(
        "--require-clean-check-design",
        action="store_true",
        help="Return nonzero if check_design.rpt is missing or contains warnings/errors",
    )
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    payload = parse_report_dir(args.report_dir)
    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        print(format_text_summary(payload))
    if args.require_clean_check_design and not payload["summary"]["check_design_clean"]:
        print("check_design is missing or not clean", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
