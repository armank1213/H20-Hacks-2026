from __future__ import annotations

from typing import Any


def _find_estimator(state: dict[str, Any]):
    for name in ("model", "clf", "estimator", "regressor", "classifier", "rf"):
        obj = state.get(name)
        if hasattr(obj, "predict"):
            return obj
    for obj in state.values():
        if hasattr(obj, "predict"):
            return obj
    return None


class DroughtModel:
    def __init__(self, *args, **kwargs):
        self.__dict__.update(kwargs)

    def __setstate__(self, state: dict[str, Any]):
        self.__dict__.update(state)

    def predict(self, X):
        estimator = _find_estimator(self.__dict__)
        if estimator is None:
            raise ValueError("No underlying estimator found for drought model")
        return estimator.predict(X)
