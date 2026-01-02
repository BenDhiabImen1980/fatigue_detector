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

# ============================================
# 1. INITIALISATION DE L'APP EN PREMIER
# ============================================
app = FastAPI(title="Fatigue Face Detection API BY IMEN")

# ============================================
# 2. CHARGEMENT DU MODÈLE
# ============================================
MODEL_PATH = "Model/Fatig_model.h5"

try:
    model = load_model(MODEL_PATH)
    print(f"✅ Modèle chargé depuis : {MODEL_PATH}")
except Exception as e:
    print(f"⚠️  Erreur chargement modèle : {e}")
    model = None

# ============================================
# 3. CONFIGURATION CORS
# ============================================
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ============================================
# 4. SCHÉMAS PYDANTIC
# ============================================
class ApiHealthResponse(BaseModel):
    status: str

class ModelHealthResponse(BaseModel):
    model_loaded: bool
    model_path: str
    input_shape: list | None

# ============================================
# 5. FONCTIONS UTILITAIRES
# ============================================
def preprocess_image(img_bytes):
    """Prétraite une image pour le modèle"""
    img = Image.open(io.BytesIO(img_bytes)).convert("RGB")
    img = img.resize((256, 256))
    img_array = image.img_to_array(img) / 255.0
    img_array = np.expand_dims(img_array, axis=0)
    return img_array

# ============================================
# 6. ENDPOINTS API (MAINTENANT QUE 'app' EST DÉFINI)
# ============================================

# Health API
@app.get("/health", response_model=ApiHealthResponse, tags=["Health"])
def health_api():
    """Vérifie si l'API FastAPI est vivante"""
    return {"status": "healthy"}

# Health Model
@app.get("/health/model", response_model=ModelHealthResponse, tags=["Health"])
def health_model():
    """Vérifie si le modèle ML est chargé"""
    if model is None:
        raise HTTPException(
            status_code=503,
            detail="Modele non charge"
        )

    return {
        "model_loaded": True,
        "model_path": MODEL_PATH,
        "input_shape": list(model.input_shape) if model else None
    }

# Predict - Version corrigée pour afficher les 2 probabilités
@app.post("/predict", tags=["Prediction"])
async def predict(file: UploadFile = File(...)):
    """Analyse une image pour détecter la fatigue"""
    if model is None:
        raise HTTPException(status_code=503, detail="Modele non chargé")

    try:
        # Lecture de l'image
        img_bytes = await file.read()
        img_array = preprocess_image(img_bytes)

        # Prédiction
        pred = model.predict(img_array, verbose=0)
        pred = pred[0]  # Prendre le premier batch
        
        print(f"🔍 DEBUG - Prédiction brute: {pred}")  # Pour voir la forme

        # Gestion des différents formats de sortie
        if len(pred) == 2:
            # Cas [prob_fatigue, prob_non_fatigue]
            prob_fatigue = round(float(pred[0]) * 100, 2)
            prob_non_fatigue = round(float(pred[1]) * 100, 2)
        elif len(pred) == 1:
            # Cas [prob_fatigue]
            prob_fatigue = round(float(pred[0]) * 100, 2)
            prob_non_fatigue = round(100 - prob_fatigue, 2)
        else:
            # Format inattendu
            prob_fatigue = round(float(pred[0]) * 100, 2)
            prob_non_fatigue = round(100 - prob_fatigue, 2)

        # Déterminer le résultat
        result = "Fatigué" if prob_fatigue >= 60 else "Non Fatigué"

        return {
            "prediction": result,
            "probabilities": {
                "fatigue": f"{prob_fatigue}%",
                "non_fatigue": f"{prob_non_fatigue}%"
            },
            "threshold_used": "60%"
        }

    except Exception as e:
        return JSONResponse(
            content={"error": str(e)},
            status_code=500
        )

# ============================================
# 7. POINT D'ENTRÉE PRINCIPAL
# ============================================
if __name__ == "__main__":
    print(f"🚀 Démarrage de l'API Fatigue Detection sur http://0.0.0.0:8000")
    print(f"📚 Documentation: http://localhost:8000/docs")
    print(f"❤️  Health check: http://localhost:8000/health")
    uvicorn.run(app, host="0.0.0.0", port=8000)