# ======================================================
# IMPORTATION DES LIBRAIRIES
# ======================================================
import os
import numpy as np
import matplotlib.pyplot as plt
from tensorflow import keras
from tensorflow.keras import layers
from tensorflow.keras.preprocessing.image import ImageDataGenerator
from tensorflow.keras.preprocessing import image

import mlflow
import mlflow.tensorflow


# ======================================================
# CONFIGURATION DES CHEMINS DU PROJET
# ======================================================
BASE_DIR = os.getcwd()

DATA_DIR = os.path.join(BASE_DIR, "Data", "etat_des_joueurs")
TRAIN_DIR = os.path.join(DATA_DIR, "TRAIN")
VAL_DIR = os.path.join(DATA_DIR, "VAL")

MODEL_DIR = os.path.join(BASE_DIR, "Model")
MODEL_PATH = os.path.join(MODEL_DIR, "Fatig_model.h5")

MLFLOW_DIR = os.path.join(BASE_DIR, "Ml_flow_runs")

os.makedirs(MODEL_DIR, exist_ok=True)
os.makedirs(MLFLOW_DIR, exist_ok=True)


# ======================================================
# CONFIGURATION MLflow
# ======================================================
mlflow.set_tracking_uri("./Ml_flow_runs")

mlflow.set_experiment("fatigue-face-detection")


# ======================================================
# PARAMETRES D'ENTRAINEMENT
# ======================================================
IMG_SIZE = (256, 256)
BATCH_SIZE = 32
EPOCHS = 4 #50
LEARNING_RATE = 0.001


# ======================================================
# PREPARATION DES DONNEES
# ======================================================
train_datagen = ImageDataGenerator(
    rescale=1./255,
    shear_range=0.2,
    zoom_range=0.2,
    horizontal_flip=True
)

val_datagen = ImageDataGenerator(rescale=1./255)

train_generator = train_datagen.flow_from_directory(
    TRAIN_DIR,
    target_size=IMG_SIZE,
    batch_size=BATCH_SIZE,
    class_mode="binary"
)

val_generator = val_datagen.flow_from_directory(
    VAL_DIR,
    target_size=IMG_SIZE,
    batch_size=BATCH_SIZE,
    class_mode="binary"
)


# ======================================================
# DEFINITION DU MODELE CNN
# ======================================================
model = keras.Sequential([
    layers.Conv2D(32, (3, 3), activation="relu", input_shape=(256, 256, 3)),
    layers.MaxPooling2D(2, 2),
    layers.Dropout(0.25),

    layers.Conv2D(64, (3, 3), activation="relu"),
    layers.MaxPooling2D(2, 2),
    layers.Dropout(0.25),

    layers.Conv2D(128, (3, 3), activation="relu"),
    layers.MaxPooling2D(2, 2),
    layers.Dropout(0.25),

    layers.Flatten(),
    layers.Dense(512, activation="relu"),
    layers.Dropout(0.5),
    layers.Dense(1, activation="sigmoid")
])


# ======================================================
# COMPILATION DU MODELE
# ======================================================
optimizer = keras.optimizers.Adam(learning_rate=LEARNING_RATE)

model.compile(
    optimizer=optimizer,
    loss="binary_crossentropy",
    metrics=["accuracy"]
)


# ======================================================
# ENTRAINEMENT + TRACKING MLflow
# ======================================================
with mlflow.start_run(run_name="cnn-fatigue-v1"):

    # 🔹 Log des hyperparamètres
    mlflow.log_params({
        "img_size": IMG_SIZE,
        "batch_size": BATCH_SIZE,
        "epochs": EPOCHS,
        "learning_rate": LEARNING_RATE,
        "optimizer": "Adam"
    })

    # 🔹 Entrainement
    history = model.fit(
        train_generator,
        epochs=EPOCHS,
        validation_data=val_generator
    )

    # 🔹 Evaluation
    val_loss, val_accuracy = model.evaluate(val_generator)

    mlflow.log_metric("val_loss", val_loss)
    mlflow.log_metric("val_accuracy", val_accuracy)

    # 🔹 Sauvegarde du modèle
    model.save(MODEL_PATH)
    #mlflow.tensorflow.log_model(model, artifact_path="model")

    # 🔹 Exemple de prédiction trackée
    val_images, val_labels = next(iter(val_generator))
    preds = model.predict(val_images)

    mlflow.log_metric("sample_prediction", float(preds[0][0]))

    # 🔹 Tags
    mlflow.set_tags({
        "task": "fatigue_detection",
        "model_type": "CNN",
        "input": "face_image"
    })

    print("\n==============================")
    print("ENTRAINEMENT TERMINE")
    print("==============================")
    print(f"Validation accuracy : {val_accuracy:.4f}")
    print(f"Model saved in      : {MODEL_PATH}")
    print("MLflow UI           : mlflow ui --backend-store-uri Ml_flow_runs --port 5000")
