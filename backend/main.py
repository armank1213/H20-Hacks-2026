from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Union
import pickle
import uvicorn
import numpy as np
import os
from backend.station_mapper import get_nearest_station, haversine_distance, STATION_COORDINATES

app = FastAPI()
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_DIR = os.path.join(BASE_DIR, "..", "models")
print(f"Current working directory: {os.getcwd()}")

MODEL_LOAD_ERRORS = {}

def load_model(file_name, allow_dict=False):
    model_path = os.path.join(MODEL_DIR, file_name)
    if os.path.exists(model_path):
        try:
            with open(model_path, 'rb') as f:
                obj = pickle.load(f)
            if isinstance(obj, dict):
                if allow_dict:
                    return obj
                for key in ("model", "estimator", "regressor", "classifier", "rf"):
                    candidate = obj.get(key)
                    if hasattr(candidate, "predict"):
                        return candidate
                for candidate in obj.values():
                    if hasattr(candidate, "predict"):
                        return candidate
                error_msg = f"No estimator with predict() found in {model_path}"
                print(error_msg)
                MODEL_LOAD_ERRORS[file_name] = error_msg
                return None
            return obj
        except Exception as e:
            error_msg = f"Error loading {model_path}: {e}"
            print(error_msg)
            MODEL_LOAD_ERRORS[file_name] = error_msg
            return None
    else:
        error_msg = f"File not found: {model_path}"
        print(error_msg)
        MODEL_LOAD_ERRORS[file_name] = error_msg
        return None

reservoir_bundle = load_model('reservoir_model.pkl', allow_dict=True)
drought_severity_model = load_model('drought_model.pkl')
snowfall_model = load_model('snow_model.pkl')
class InputData(BaseModel):
    features: list[Union[float, str]]
    


@app.post('/predict')
async def predict(data: InputData):
    
    print(f"Received features: {data.features}")

    if not data.features:
        raise HTTPException(status_code=400, detail="Features list cannot be empty.")

    station_id = None
    start_idx = 0
    nearest_station = None

    if isinstance(data.features[0], str):
        station_id = data.features[0].strip().upper()
        start_idx = 1
        if station_id in STATION_COORDINATES:
            info = STATION_COORDINATES[station_id]
            nearest_station = {
                "station_id": station_id,
                "station_name": info["name"],
                "station_lat": info["lat"],
                "station_lon": info["lon"],
                "distance_miles": 0.0,
            }
    else:
        if len(data.features) < 2:
            raise HTTPException(
                status_code=400,
                detail="Expected latitude and longitude as the first two values when station_id is not provided."
            )
        lat, lon = float(data.features[0]), float(data.features[1])
        nearest_station = get_nearest_station(lat, lon)
        station_id = nearest_station["station_id"] if nearest_station else None
        start_idx = 2

    numeric_features = [float(v) for v in data.features[start_idx:]]
    if not numeric_features:
        raise HTTPException(
            status_code=400,
            detail="No numeric model features provided after station_id/lat/lon."
        )
    
    if reservoir_bundle is None or drought_severity_model is None or snowfall_model is None:
        missing = []
        if reservoir_bundle is None:
            missing.append("reservoir_model.pkl")
        if drought_severity_model is None:
            missing.append("drought_model.pkl")
        if snowfall_model is None:
            missing.append("snow_model.pkl")
        raise HTTPException(
            status_code=500, 
            detail={
                "message": "One or more models are missing on the server. Check the 'models' folder.",
                "missing_models": missing,
                "load_errors": MODEL_LOAD_ERRORS,
            }
        )

    try:
        warnings = []

        reservoir_models = reservoir_bundle.get("models", {}) if isinstance(reservoir_bundle, dict) else {}
        reservoir_model = reservoir_models.get(station_id)
        if reservoir_model is None:
            raise HTTPException(
                status_code=400,
                detail=f"No reservoir model found for station_id '{station_id}'."
            )

        reservoir_expected = len(reservoir_bundle.get("feature_names", [])) if isinstance(reservoir_bundle, dict) else None
        drought_expected = len(getattr(drought_severity_model, "feature_cols", [])) or getattr(
            getattr(drought_severity_model, "estimator", None), "n_features_in_", None
        )
        snow_expected = len(getattr(snowfall_model, "feature_cols", [])) or getattr(
            getattr(snowfall_model, "estimator", None), "n_features_in_", None
        )

        cursor = 0
        res_pred = drought_pred = snow_pred = None

        if reservoir_expected and len(numeric_features) >= cursor + reservoir_expected:
            res_feats = numeric_features[cursor:cursor + reservoir_expected]
            cursor += reservoir_expected
            res_pred = reservoir_model.predict(np.array([res_feats]))
        else:
            warnings.append(
                f"reservoir features: expected {reservoir_expected}, got {len(numeric_features) - cursor}"
            )

        if drought_expected and len(numeric_features) >= cursor + drought_expected:
            drought_feats = numeric_features[cursor:cursor + drought_expected]
            cursor += drought_expected
            drought_pred = drought_severity_model.predict(np.array([drought_feats]))
        else:
            warnings.append(
                f"drought features: expected {drought_expected}, got {len(numeric_features) - cursor}"
            )

        if snow_expected and len(numeric_features) >= cursor + snow_expected:
            snow_feats = numeric_features[cursor:cursor + snow_expected]
            cursor += snow_expected
            snow_pred = snowfall_model.predict(np.array([snow_feats]))
        else:
            warnings.append(
                f"snow features: expected {snow_expected}, got {len(numeric_features) - cursor}"
            )
        
        return {
            "nearest_station": nearest_station,
            "reservoir_prediction": res_pred.tolist() if res_pred is not None else None,
            "drought_severity_prediction": drought_pred.tolist() if drought_pred is not None else None,
            "snowfall_prediction": snow_pred.tolist() if snow_pred is not None else None,
            "warnings": warnings,
        }

    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Prediction Error: {str(e)}")

@app.get('/')
async def root():
    return {"message": "H2O Hackathon Server is Running"}
