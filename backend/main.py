from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import pickle
import uvicorn
import numpy as np

app = FastAPI()

def reservoir_load_model():
    try:
        with open('models/reservoir_model.pkl', 'rb') as f:
            reservoir_model = pickle.load(f)
    except FileNotFoundError:
        reservoir_model = None
        print(f"No model found at {'models/reservoir_model.pkl'}")
    return reservoir_model

reservoir_model = reservoir_load_model()

class InputData(BaseModel):
    features: list[float]

@app.post('/predict')
async def predict(data: InputData):
    
    return {"data sent my client": data.features}
    '''
    if reservoir_model is None:
        raise HTTPException(status_code=500, detail="Reservoir model not found")
    
    input_features = np.array([data.features])
    
    
    
    try:
        reservoir_prediction = reservoir_model.predict(input_features)
        return {"reservoir_prediction": reservoir_prediction.tolist()}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))'''
    
if __name__ == "__main__":
    uvicorn.run(app, host="localhost", port=8000)
    
    
    
