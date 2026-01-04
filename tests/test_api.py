# tests/test_api.py
import io
import numpy as np
from fastapi.testclient import TestClient
from unittest.mock import patch, MagicMock
from PIL import Image

# Mock TensorFlow AVANT l'import de App.main
sys.modules['tensorflow'] = Mock()
sys.modules['tensorflow.keras'] = Mock()
sys.modules['tensorflow.keras.models'] = Mock()
sys.modules['tensorflow.keras.preprocessing'] = Mock()
sys.modules['tensorflow.keras.preprocessing.image'] = Mock()


from App.main import app

client = TestClient(app)


# --------------------------------------------------
# Utilitaire : image factice
# --------------------------------------------------
def create_fake_image():
    img = Image.new("RGB", (256, 256), color=(255, 255, 255))
    buf = io.BytesIO()
    img.save(buf, format="JPEG")
    buf.seek(0)
    return buf


# --------------------------------------------------
# TEST 1 : Health API
# --------------------------------------------------
def test_health_api():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


# --------------------------------------------------
# TEST 2 : Health Model (model NON chargé)
# --------------------------------------------------
def test_health_model_not_loaded():
    with patch("App.main.model", None):
        response = client.get("/health/model")
        assert response.status_code == 503


# --------------------------------------------------
# TEST 3 : Health Model (model chargé)
# --------------------------------------------------
def test_health_model_loaded():
    fake_model = MagicMock()
    fake_model.input_shape = (None, 256, 256, 3)

    with patch("App.main.model", fake_model):
        response = client.get("/health/model")
        assert response.status_code == 200
        assert response.json()["model_loaded"] is True


# --------------------------------------------------
# TEST 4 : Predict sans modèle (503)
# --------------------------------------------------
def test_predict_without_model():
    image = create_fake_image()

    with patch("App.main.model", None):
        response = client.post(
            "/predict",
            files={"file": ("test.jpg", image, "image/jpeg")}
        )

    assert response.status_code == 503


# --------------------------------------------------
# TEST 5 : Predict avec modèle mocké
# --------------------------------------------------
def test_predict_with_mock_model():
    image = create_fake_image()

    fake_model = MagicMock()
    # Simulation sortie modèle : [fatigue, non_fatigue]
    fake_model.predict.return_value = np.array([[0.7, 0.3]])

    with patch("App.main.model", fake_model):
        response = client.post(
            "/predict",
            files={"file": ("test.jpg", image, "image/jpeg")}
        )

    assert response.status_code == 200
    body = response.json()

    assert "prediction" in body
    assert "probabilities" in body
    assert body["prediction"] in ["Fatigué", "Non Fatigué"]
