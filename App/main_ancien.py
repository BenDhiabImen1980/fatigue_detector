from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uvicorn

from tensorflow.keras.models import load_model
from tensorflow.keras.preprocessing import image

import numpy as np
import io
from PIL import Image

# Initialisation API
app = FastAPI(title="Fatigue Face Detection API BY IMEN")

# Chargement du modèle
MODEL_PATH = "Model/Fatig_model.h5"

try:
    model = load_model(MODEL_PATH)
except Exception:
    model = None

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Schémas Pydantic
class ApiHealthResponse(BaseModel):
    status: str


class ModelHealthResponse(BaseModel):
    model_loaded: bool
    model_path: str
    input_shape: list | None

# Utils
def preprocess_image(img_bytes):
    img = Image.open(io.BytesIO(img_bytes)).convert("RGB")
    img = img.resize((256, 256))
    img_array = image.img_to_array(img) / 255.0
    img_array = np.expand_dims(img_array, axis=0)
    return img_array

# Health API
@app.get("/health", response_model=ApiHealthResponse, tags=["Health"])
def health_api():
    """
    Vérifie si l'API FastAPI est vivante
    """
    return {"status": "healthy"}


# Health Model
@app.get("/health/model", response_model=ModelHealthResponse, tags=["Health"])
def health_model():
    """
    Vérifie si le modèle ML est chargé
    """
    if model is None:
        raise HTTPException(
            status_code=503,
            detail="Modele non charge"
        )

    return {
        "model_loaded": True,
        "model_path": MODEL_PATH,
        "input_shape": list(model.input_shape)
    }

# Predict
@app.post("/predict", tags=["Prediction"])
async def predict(file: UploadFile = File(...)):
    if model is None:
        raise HTTPException(status_code=503, detail="Modele non chargé")

    try:
        img_bytes = await file.read()
        img_array = preprocess_image(img_bytes)

        pred = model.predict(img_array)
        fatigue_prob = round(float(pred[0][0]),2)

        result = "Fatigué" if fatigue_prob > 0.6 else "Non Fatigué"

        return {
            "prediction": result,
            "probability": fatigue_prob
        }

    except Exception as e:
        return JSONResponse(
            content={"error": str(e)},
            status_code=500
        )

# Run
if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
