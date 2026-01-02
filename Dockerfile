# ============================================
# Dockerfile pour TensorFlow 2.14.0
# Python 3.10 + TensorFlow CPU
# ============================================

FROM python:3.10-slim-bookworm

# Variables d'environnement
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# ============================================
# 1. Installation des dépendances système
# ============================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# 2. Mise à jour de pip
# ============================================
RUN pip install --no-cache-dir --upgrade pip setuptools wheel

# ============================================
# 3. Installation de TensorFlow 2.14.0
# ORDRE CRITIQUE: numpy d'abord, puis TensorFlow
# ============================================
RUN pip install --no-cache-dir \
    numpy==1.24.3 \
    tensorflow-cpu==2.14.0

# ============================================
# 4. Vérification de TensorFlow
# ============================================
RUN python -c "\
import sys; \
import tensorflow as tf; \
from tensorflow.keras.models import load_model; \
print('=' * 50); \
print('✅ TensorFlow Version:', tf.__version__); \
print('✅ Python Version:', sys.version.split()[0]); \
print('✅ Keras importé avec succès'); \
print('=' * 50)\
"

# ============================================
# 5. Installation des dépendances Python
# ============================================
# Copier requirements.txt (sans tensorflow)
COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

# ============================================
# 6. Vérification des packages installés
# ============================================
RUN echo "Packages installés:" && \
    pip list | grep -E "tensorflow|numpy|keras|fastapi|uvicorn|pydantic"

# ============================================
# 7. Copie de l'application
# ============================================
COPY App ./App
COPY Model ./Model

# ============================================
# 8. Test final de l'application
# ============================================
RUN python -c "from tensorflow.keras.models import load_model; import fastapi; import uvicorn; print('✅ Tous les imports réussis')"

# ============================================
# 9. Configuration du serveur
# ============================================
EXPOSE 8000

# Healthcheck optionnel
#HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    #CMD python -c "import requests; requests.get('http://localhost:8000/health')" || exit 1

# Lancement de l'application
CMD ["uvicorn", "App.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]