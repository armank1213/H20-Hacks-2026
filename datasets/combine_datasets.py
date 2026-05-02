"""Combine per-station CSVs into a single master CSV per dataset.

Drought master: station,Date,None,D0,D1,D2,D3,D4
Snow master:    station,datetime,snow.water.eq.inches
"""

import csv
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DROUGHT_DIR = ROOT / "droughtData" / "ca_drought" / "data"
SNOW_DIR = ROOT / "snowDepth" / "ca_snow" / "data_sane"
DROUGHT_OUT = ROOT / "droughtData" / "ca_drought_master.csv"
SNOW_OUT = ROOT / "snowDepth" / "ca_snow_master.csv"

DROUGHT_FILE_RE = re.compile(r"^ca_atlas_(\d+)\.csv$")


def combine_drought() -> int:
    rows_written = 0
    with DROUGHT_OUT.open("w", newline="") as fout:
        writer = csv.writer(fout)
        writer.writerow(["station", "Date", "None", "D0", "D1", "D2", "D3", "D4"])
        for path in sorted(DROUGHT_DIR.glob("ca_atlas_*.csv")):
            m = DROUGHT_FILE_RE.match(path.name)
            if not m:
                continue
            station = m.group(1)
            with path.open(newline="") as fin:
                reader = csv.reader(fin)
                header = next(reader, None)
                if header != ["Date", "None", "D0", "D1", "D2", "D3", "D4"]:
                    raise ValueError(f"unexpected drought header in {path}: {header}")
                for row in reader:
                    if not row:
                        continue
                    writer.writerow([station, *row])
                    rows_written += 1
    return rows_written


def combine_snow() -> int:
    rows_written = 0
    with SNOW_OUT.open("w", newline="") as fout:
        writer = csv.writer(fout)
        writer.writerow(["station", "datetime", "snow.water.eq.inches"])
        for path in sorted(SNOW_DIR.glob("*.csv")):
            station = path.stem
            with path.open(newline="") as fin:
                reader = csv.reader(fin)
                header = next(reader, None)
                if header != ["datetime", "snow.water.eq.inches"]:
                    raise ValueError(f"unexpected snow header in {path}: {header}")
                for row in reader:
                    if not row:
                        continue
                    writer.writerow([station, *row])
                    rows_written += 1
    return rows_written


if __name__ == "__main__":
    d = combine_drought()
    s = combine_snow()
    print(f"drought rows: {d} -> {DROUGHT_OUT}")
    print(f"snow rows: {s} -> {SNOW_OUT}")
