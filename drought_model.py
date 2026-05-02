"""Drought severity LSTM classifier.

predict_drought(location, date) -> severity label in
    {"no risk", "slight risk", "moderate", "severe", "extreme"}.
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

from .location import drought_stations, nearest_drought_station

SCRIPTS_DIR = Path(__file__).resolve().parent
MODELS_DIR = SCRIPTS_DIR.parent
ROOT = MODELS_DIR.parent
DATA = ROOT / "datasets" / "droughtData" / "ca_drought_master.csv"
MODEL_PATH = MODELS_DIR / "final_models" / "drought_model.pt"

SEVERITY_MAP = {"D0": "no risk", "D1": "slight risk", "D2": "moderate", "D3": "severe", "D4": "extreme"}
SEVERITY_ORDER = ["no risk", "slight risk", "moderate", "severe", "extreme"]
SEVERITY_TO_IDX = {s: i for i, s in enumerate(SEVERITY_ORDER)}
D_COLS = ["D0", "D1", "D2", "D3", "D4"]
DROUGHT_COLS = ["None", *D_COLS]
COVERAGE_THRESHOLD = 50.0

# LSTM hyperparameters.
SEQ_LEN = 12               # 12-month look-back.
PER_STEP_FEATURES = ["None", "D0", "D1", "D2", "D3", "D4", "month_sin", "month_cos"]
NUM_FEATURES = len(PER_STEP_FEATURES)
STATION_EMB_DIM = 8
HIDDEN_DIM = 64
NUM_LAYERS = 2
DROPOUT = 0.35
NUM_CLASSES = len(SEVERITY_ORDER)
EPOCHS = 30
BATCH_SIZE = 512
LR = 1e-3
WEIGHT_DECAY = 5e-4
PATIENCE = 5               # early stopping on validation accuracy.
VAL_FRAC = 0.10            # last 10% of train (by date) used for early-stop validation.


class DroughtLSTM(nn.Module):
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
        self.head = nn.Linear(HIDDEN_DIM, NUM_CLASSES)

    def forward(self, seq: torch.Tensor, station_idx: torch.Tensor) -> torch.Tensor:
        emb = self.station_emb(station_idx).unsqueeze(1).expand(-1, seq.size(1), -1)
        x = torch.cat([seq, emb], dim=-1)
        out, _ = self.lstm(x)
        return self.head(out[:, -1, :])


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


def _compute_severity(grouped: pd.DataFrame) -> np.ndarray:
    above = grouped[D_COLS].values >= COVERAGE_THRESHOLD
    worst_idx = np.where(above.any(axis=1), above.shape[1] - 1 - above[:, ::-1].argmax(axis=1), -1)
    labels = np.array(["no risk"] * len(grouped), dtype=object)
    has_d = worst_idx >= 0
    labels[has_d] = [SEVERITY_MAP[D_COLS[i]] for i in worst_idx[has_d]]
    return labels


def _load_dataset() -> pd.DataFrame:
    df = pd.read_csv(DATA, dtype={"station": str})
    df["station"] = df["station"].str.zfill(6)
    df["Date"] = pd.to_datetime(df["Date"], format="%m/%d/%Y", errors="coerce")
    df = df.dropna(subset=["Date"])
    df["year"] = df["Date"].dt.year
    df["month"] = df["Date"].dt.month
    meta = {s.station_id: s for s in drought_stations()}
    df = df[df["station"].isin(meta)].copy()
    grouped = (
        df.groupby(["station", "year", "month"], as_index=False)
        .agg({c: "mean" for c in DROUGHT_COLS})
    )
    grouped["severity"] = _compute_severity(grouped)
    grouped["month_sin"] = np.sin(2 * np.pi * grouped["month"] / 12)
    grouped["month_cos"] = np.cos(2 * np.pi * grouped["month"] / 12)
    grouped = grouped.sort_values(["station", "year", "month"]).reset_index(drop=True)
    return grouped


def _build_sequences(df: pd.DataFrame, station_to_idx: dict[str, int]):
    """Sliding-window sequences per station. Each sample = 12 months -> next month label."""
    seqs, targets, station_ids, ym = [], [], [], []
    for station, sub in df.groupby("station"):
        if station not in station_to_idx:
            continue
        sub = sub.sort_values(["year", "month"]).reset_index(drop=True)
        if len(sub) < SEQ_LEN + 1:
            continue
        feats = sub[PER_STEP_FEATURES].values.astype(np.float32)
        sevs = sub["severity"].values
        years = sub["year"].values
        months = sub["month"].values
        for i in range(SEQ_LEN, len(sub)):
            seqs.append(feats[i - SEQ_LEN:i])
            targets.append(SEVERITY_TO_IDX[sevs[i]])
            station_ids.append(station_to_idx[station])
            ym.append((int(years[i]), int(months[i])))
    return np.stack(seqs), np.array(targets, dtype=np.int64), np.array(station_ids, dtype=np.int64), ym


def _time_split_indices(ym: list[tuple[int, int]], test_frac: float = 0.15):
    arr = np.array(ym)
    order = np.lexsort((arr[:, 1], arr[:, 0]))  # sort by year then month
    cutoff = int(len(order) * (1.0 - test_frac))
    return order[:cutoff], order[cutoff:]


def train(save: bool = True):
    df = _load_dataset()
    stations = sorted(df["station"].unique())
    station_to_idx = {s: i for i, s in enumerate(stations)}

    seqs, targets, st_ids, ym = _build_sequences(df, station_to_idx)
    train_idx, test_idx = _time_split_indices(ym, 0.15)

    # Carve a validation slice off the END of train (by date) for early stopping.
    train_ym = [ym[i] for i in train_idx]
    train_arr = np.array(train_ym)
    train_order = np.lexsort((train_arr[:, 1], train_arr[:, 0]))
    val_cut = int(len(train_idx) * (1.0 - VAL_FRAC))
    train_only_idx = train_idx[train_order[:val_cut]]
    val_idx = train_idx[train_order[val_cut:]]

    mean = seqs[train_only_idx].reshape(-1, NUM_FEATURES).mean(axis=0)
    std = seqs[train_only_idx].reshape(-1, NUM_FEATURES).std(axis=0) + 1e-6
    seqs_n = (seqs - mean) / std

    counts = np.bincount(targets[train_only_idx], minlength=NUM_CLASSES).astype(np.float32)
    weights = counts.sum() / (NUM_CLASSES * np.maximum(counts, 1))
    class_weights = torch.tensor(weights, dtype=torch.float32)

    device = _device()
    model = DroughtLSTM(len(stations)).to(device)
    opt = torch.optim.AdamW(model.parameters(), lr=LR, weight_decay=WEIGHT_DECAY)
    loss_fn = nn.CrossEntropyLoss(weight=class_weights.to(device))

    Xtr = torch.tensor(seqs_n[train_only_idx], dtype=torch.float32)
    ytr = torch.tensor(targets[train_only_idx], dtype=torch.long)
    str_tr = torch.tensor(st_ids[train_only_idx], dtype=torch.long)
    Xval = torch.tensor(seqs_n[val_idx], dtype=torch.float32).to(device)
    yval = torch.tensor(targets[val_idx], dtype=torch.long).to(device)
    sval = torch.tensor(st_ids[val_idx], dtype=torch.long).to(device)
    Xte = torch.tensor(seqs_n[test_idx], dtype=torch.float32).to(device)
    yte = torch.tensor(targets[test_idx], dtype=torch.long).to(device)
    ste_te = torch.tensor(st_ids[test_idx], dtype=torch.long).to(device)

    loader = DataLoader(TensorDataset(Xtr, str_tr, ytr), batch_size=BATCH_SIZE, shuffle=True)

    print(
        f"drought LSTM training | n_train={len(train_only_idx)} n_val={len(val_idx)} n_test={len(test_idx)}"
        f" | n_stations={len(stations)} | device={device}"
    )
    best_val_acc = -1.0
    best_state = None
    no_improve = 0
    for epoch in range(EPOCHS):
        model.train()
        total = 0.0
        for seq, st, y in loader:
            seq, st, y = seq.to(device), st.to(device), y.to(device)
            logits = model(seq, st)
            loss = loss_fn(logits, y)
            opt.zero_grad()
            loss.backward()
            opt.step()
            total += loss.item() * y.size(0)
        model.eval()
        with torch.no_grad():
            val_pred = model(Xval, sval).argmax(-1)
            val_acc = (val_pred == yval).float().mean().item()
            test_pred = model(Xte, ste_te).argmax(-1)
            test_acc = (test_pred == yte).float().mean().item()
        improved = val_acc > best_val_acc
        marker = " *" if improved else ""
        print(
            f"  epoch {epoch+1:>2}/{EPOCHS}  train_loss={total/len(Xtr):.4f}"
            f"  val_acc={val_acc:.3f}  test_acc={test_acc:.3f}{marker}"
        )
        if improved:
            best_val_acc = val_acc
            best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}
            no_improve = 0
        else:
            no_improve += 1
            if no_improve >= PATIENCE:
                print(f"  early stop at epoch {epoch+1} (no val improvement in {PATIENCE} epochs)")
                break

    if best_state is not None:
        model.load_state_dict(best_state)
    model.eval()
    with torch.no_grad():
        pred = model(Xte, ste_te).argmax(-1)
        final_acc = (pred == yte).float().mean().item()
    print(f"drought LSTM best test acc (time split): {final_acc:.3f}  best_val_acc={best_val_acc:.3f}")

    history = df[["station", "year", "month"] + PER_STEP_FEATURES].copy()
    if save:
        torch.save(
            {
                "state_dict": model.state_dict(),
                "n_stations": len(stations),
                "station_to_idx": station_to_idx,
                "mean": mean.astype(np.float32),
                "std": std.astype(np.float32),
                "history": history,
            },
            MODEL_PATH,
        )
    return model


@lru_cache(maxsize=1)
def _load():
    if not MODEL_PATH.exists():
        train()
    ckpt = torch.load(MODEL_PATH, map_location="cpu", weights_only=False)
    model = DroughtLSTM(ckpt["n_stations"])
    model.load_state_dict(ckpt["state_dict"])
    model.eval()
    return {
        "model": model,
        "station_to_idx": ckpt["station_to_idx"],
        "mean": ckpt["mean"],
        "std": ckpt["std"],
        "history": ckpt["history"],
    }


def _build_input_sequence(history: pd.DataFrame, station_id: str, year: int, month: int) -> np.ndarray:
    """Return a (SEQ_LEN, NUM_FEATURES) array for the 12 months ending just before (year, month).
    If history is short, repeat the earliest available row to pad."""
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


def predict_drought(location, date) -> str:
    """Return drought severity label."""
    ckpt = _load()
    station = nearest_drought_station(location)
    if station.station_id not in ckpt["station_to_idx"]:
        raise ValueError(f"station {station.station_id} not in trained set")
    year, month = _parse_date(date)
    seq = _build_input_sequence(ckpt["history"], station.station_id, year, month)
    seq = (seq - ckpt["mean"]) / ckpt["std"]
    seq_t = torch.tensor(seq[None], dtype=torch.float32)
    st_t = torch.tensor([ckpt["station_to_idx"][station.station_id]], dtype=torch.long)
    with torch.no_grad():
        logits = ckpt["model"](seq_t, st_t)
    return SEVERITY_ORDER[int(logits.argmax(-1).item())]


if __name__ == "__main__":
    train()
