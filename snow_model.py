"""Snow water equivalent LSTM regressor.

predict_snow(location, date) -> float (inches of snow water equivalent).
location: (lat, lon) tuple or station id/name.
date:     (year, month), "YYYY-MM", or datetime.
"""

from __future__ import annotations

from datetime import date as date_t, datetime
from functools import lru_cache
from pathlib import Path

import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset

from .location import nearest_snow_station, snow_stations

SCRIPTS_DIR = Path(__file__).resolve().parent
MODELS_DIR = SCRIPTS_DIR.parent
ROOT = MODELS_DIR.parent
DATA = ROOT / "datasets" / "snowDepth" / "ca_snow_master.csv"
MODEL_PATH = MODELS_DIR / "final_models" / "snow_model.pt"

# Sierra snowpack ~0.5% per year decline trend (rough approximation).
SNOW_WARMING_RATE = 0.005

# LSTM hyperparameters.
SEQ_LEN = 24                 # 24-month look-back covers two winters.
PER_STEP_FEATURES = ["swe", "month_sin", "month_cos"]
NUM_FEATURES = len(PER_STEP_FEATURES)
STATION_EMB_DIM = 8
HIDDEN_DIM = 64
NUM_LAYERS = 2
DROPOUT = 0.15
EPOCHS = 40
BATCH_SIZE = 256
LR = 1e-3


class SnowLSTM(nn.Module):
    def __init__(self, n_stations: int):
        super().__init__()
        self.station_emb = nn.Embedding(n_stations, STATION_EMB_DIM)
        self.lstm = nn.LSTM(
            input_size=NUM_FEATURES + STATION_EMB_DIM,
            hidden_size=HIDDEN_DIM,
            num_layers=NUM_LAYERS,
            batch_first=True,
            dropout=DROPOUT if NUM_LAYERS > 1 else 0.0,
        )
        self.head = nn.Linear(HIDDEN_DIM, 1)

    def forward(self, seq: torch.Tensor, station_idx: torch.Tensor) -> torch.Tensor:
        emb = self.station_emb(station_idx).unsqueeze(1).expand(-1, seq.size(1), -1)
        x = torch.cat([seq, emb], dim=-1)
        out, _ = self.lstm(x)
        return self.head(out[:, -1, :]).squeeze(-1)


def _parse_date(d) -> tuple[int, int]:
    if isinstance(d, (datetime, date_t)):
        return d.year, d.month
    if isinstance(d, str):
        parts = d.split("-")
        if len(parts) >= 2:
            return int(parts[0]), int(parts[1])
        raise ValueError(f"bad date: {d}")
    if isinstance(d, (tuple, list)) and len(d) == 2:
        return int(d[0]), int(d[1])
    raise ValueError(f"bad date: {d}")


def _device():
    if torch.backends.mps.is_available():
        return torch.device("mps")
    if torch.cuda.is_available():
        return torch.device("cuda")
    return torch.device("cpu")


def _load_dataset() -> pd.DataFrame:
    """Load monthly SWE per station. Fill missing months in the station window with 0
    (reasonable since CA off-season SWE is ~0)."""
    df = pd.read_csv(DATA, parse_dates=["datetime"])
    df = df.dropna(subset=["snow.water.eq.inches"])
    df["year"] = df["datetime"].dt.year
    df["month"] = df["datetime"].dt.month
    meta = {s.station_id: s for s in snow_stations()}
    df = df[df["station"].isin(meta)].copy()
    grouped = (
        df.groupby(["station", "year", "month"], as_index=False)["snow.water.eq.inches"].mean()
        .rename(columns={"snow.water.eq.inches": "swe"})
    )

    # Build a continuous monthly grid per station (first observed month → last observed month)
    # filled with 0 for months without measurements.
    full = []
    for station, sub in grouped.groupby("station"):
        sub = sub.sort_values(["year", "month"])
        start = (int(sub["year"].iloc[0]), int(sub["month"].iloc[0]))
        end = (int(sub["year"].iloc[-1]), int(sub["month"].iloc[-1]))
        months = pd.date_range(
            start=f"{start[0]}-{start[1]:02d}-01",
            end=f"{end[0]}-{end[1]:02d}-01",
            freq="MS",
        )
        grid = pd.DataFrame({
            "station": station,
            "year": months.year,
            "month": months.month,
        })
        merged = grid.merge(sub, on=["station", "year", "month"], how="left")
        merged["swe"] = merged["swe"].fillna(0.0)
        full.append(merged)
    full_df = pd.concat(full, ignore_index=True)
    full_df["month_sin"] = np.sin(2 * np.pi * full_df["month"] / 12)
    full_df["month_cos"] = np.cos(2 * np.pi * full_df["month"] / 12)
    full_df = full_df.sort_values(["station", "year", "month"]).reset_index(drop=True)
    return full_df


def _build_sequences(df: pd.DataFrame, station_to_idx: dict[str, int], observed: set[tuple[str, int, int]]):
    """Sliding-window sequences. Only keep targets where SWE was actually observed (not synthetic 0-fill)."""
    seqs, targets, station_ids, ym = [], [], [], []
    for station, sub in df.groupby("station"):
        if station not in station_to_idx:
            continue
        sub = sub.sort_values(["year", "month"]).reset_index(drop=True)
        if len(sub) < SEQ_LEN + 1:
            continue
        feats = sub[PER_STEP_FEATURES].values.astype(np.float32)
        years = sub["year"].values
        months = sub["month"].values
        for i in range(SEQ_LEN, len(sub)):
            key = (station, int(years[i]), int(months[i]))
            if key not in observed:
                continue
            seqs.append(feats[i - SEQ_LEN:i])
            targets.append(float(sub["swe"].iloc[i]))
            station_ids.append(station_to_idx[station])
            ym.append((int(years[i]), int(months[i])))
    return np.stack(seqs), np.array(targets, dtype=np.float32), np.array(station_ids, dtype=np.int64), ym


def _time_split_indices(ym: list[tuple[int, int]], test_frac: float = 0.15):
    arr = np.array(ym)
    order = np.lexsort((arr[:, 1], arr[:, 0]))
    cutoff = int(len(order) * (1.0 - test_frac))
    return order[:cutoff], order[cutoff:]


def train(save: bool = True):
    df = _load_dataset()
    observed = set()
    raw = pd.read_csv(DATA, parse_dates=["datetime"]).dropna(subset=["snow.water.eq.inches"])
    raw = raw[raw["station"].isin({s.station_id for s in snow_stations()})]
    raw["year"] = raw["datetime"].dt.year
    raw["month"] = raw["datetime"].dt.month
    for _, r in raw[["station", "year", "month"]].drop_duplicates().iterrows():
        observed.add((r["station"], int(r["year"]), int(r["month"])))

    stations = sorted(df["station"].unique())
    station_to_idx = {s: i for i, s in enumerate(stations)}

    seqs, targets, st_ids, ym = _build_sequences(df, station_to_idx, observed)
    train_idx, test_idx = _time_split_indices(ym, 0.15)

    mean = seqs[train_idx].reshape(-1, NUM_FEATURES).mean(axis=0)
    std = seqs[train_idx].reshape(-1, NUM_FEATURES).std(axis=0) + 1e-6
    seqs_n = (seqs - mean) / std
    target_mean = float(targets[train_idx].mean())
    target_std = float(targets[train_idx].std() + 1e-6)
    targets_n = (targets - target_mean) / target_std

    device = _device()
    model = SnowLSTM(len(stations)).to(device)
    opt = torch.optim.AdamW(model.parameters(), lr=LR, weight_decay=1e-4)
    loss_fn = nn.SmoothL1Loss()

    Xtr = torch.tensor(seqs_n[train_idx], dtype=torch.float32)
    ytr = torch.tensor(targets_n[train_idx], dtype=torch.float32)
    str_tr = torch.tensor(st_ids[train_idx], dtype=torch.long)
    Xte = torch.tensor(seqs_n[test_idx], dtype=torch.float32).to(device)
    yte = torch.tensor(targets[test_idx], dtype=torch.float32).to(device)
    ste_te = torch.tensor(st_ids[test_idx], dtype=torch.long).to(device)

    loader = DataLoader(TensorDataset(Xtr, str_tr, ytr), batch_size=BATCH_SIZE, shuffle=True)

    print(
        f"snow LSTM training | n_train={len(train_idx)} n_test={len(test_idx)}"
        f" | n_stations={len(stations)} | device={device}"
    )
    for epoch in range(EPOCHS):
        model.train()
        total = 0.0
        for seq, st, y in loader:
            seq, st, y = seq.to(device), st.to(device), y.to(device)
            pred = model(seq, st)
            loss = loss_fn(pred, y)
            opt.zero_grad()
            loss.backward()
            opt.step()
            total += loss.item() * y.size(0)
        if (epoch + 1) % 5 == 0 or epoch == 0:
            model.eval()
            with torch.no_grad():
                pred = model(Xte, ste_te) * target_std + target_mean
                mae = (pred - yte).abs().mean().item()
            print(f"  epoch {epoch+1:>2}/{EPOCHS}  train_loss={total/len(Xtr):.4f}  test_MAE={mae:.3f}")

    model.eval()
    with torch.no_grad():
        pred = model(Xte, ste_te) * target_std + target_mean
        mae = (pred - yte).abs().mean().item()
    print(f"snow LSTM final test MAE (time split): {mae:.3f} inches")

    history = df[["station", "year", "month"] + PER_STEP_FEATURES].copy()
    baseline_year = int(np.array([y for y, _ in ym])[train_idx].mean()) if len(train_idx) else 2000
    if save:
        torch.save(
            {
                "state_dict": model.state_dict(),
                "n_stations": len(stations),
                "station_to_idx": station_to_idx,
                "mean": mean.astype(np.float32),
                "std": std.astype(np.float32),
                "target_mean": target_mean,
                "target_std": target_std,
                "history": history,
                "baseline_year": baseline_year,
            },
            MODEL_PATH,
        )
    return model


@lru_cache(maxsize=1)
def _load():
    if not MODEL_PATH.exists():
        train()
    ckpt = torch.load(MODEL_PATH, map_location="cpu", weights_only=False)
    model = SnowLSTM(ckpt["n_stations"])
    model.load_state_dict(ckpt["state_dict"])
    model.eval()
    return {
        "model": model,
        "station_to_idx": ckpt["station_to_idx"],
        "mean": ckpt["mean"],
        "std": ckpt["std"],
        "target_mean": ckpt["target_mean"],
        "target_std": ckpt["target_std"],
        "history": ckpt["history"],
        "baseline_year": ckpt["baseline_year"],
    }


def warming_factor(year: int, baseline_year: int) -> float:
    """Multiplicative factor: snowpack shrinks ~SNOW_WARMING_RATE per year past baseline."""
    return max(0.0, 1.0 - SNOW_WARMING_RATE * (year - baseline_year))


def _build_input_sequence(history: pd.DataFrame, station_id: str, year: int, month: int) -> np.ndarray:
    sub = history[history["station"] == station_id].sort_values(["year", "month"])
    prior = sub[(sub["year"] < year) | ((sub["year"] == year) & (sub["month"] < month))]
    if prior.empty:
        prior = sub
    seq_rows = prior.iloc[-SEQ_LEN:]
    if len(seq_rows) < SEQ_LEN:
        pad_count = SEQ_LEN - len(seq_rows)
        pad = pd.concat([seq_rows.iloc[[0]]] * pad_count, ignore_index=True)
        seq_rows = pd.concat([pad, seq_rows], ignore_index=True)
    return seq_rows[PER_STEP_FEATURES].values.astype(np.float32)


def predict_snow(location, date) -> float:
    """Return predicted snow water equivalent in inches."""
    ckpt = _load()
    station = nearest_snow_station(location)
    if station.station_id not in ckpt["station_to_idx"]:
        raise ValueError(f"station {station.station_id} not in trained set")
    year, month = _parse_date(date)
    seq = _build_input_sequence(ckpt["history"], station.station_id, year, month)
    seq = (seq - ckpt["mean"]) / ckpt["std"]
    seq_t = torch.tensor(seq[None], dtype=torch.float32)
    st_t = torch.tensor([ckpt["station_to_idx"][station.station_id]], dtype=torch.long)
    with torch.no_grad():
        pred_norm = ckpt["model"](seq_t, st_t).item()
    base = max(0.0, pred_norm * ckpt["target_std"] + ckpt["target_mean"])
    return base * warming_factor(year, ckpt["baseline_year"])


if __name__ == "__main__":
    train()
