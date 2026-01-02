#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Déploiement optimisé - Fatigue Detector"
echo "==========================================="
echo ""

# ============================================
# CONFIGURATION
# ============================================
DOCKERHUB_USERNAME="bendhiab"
IMAGE_NAME="fatigue-api"
IMAGE_TAG="v1"
RESOURCE_GROUP="res_fatigue_detect"  
LOCATION="eastus"
CONTAINER_APP_NAME="fatigue-detector" 
CONTAINERAPPS_ENV="env-fatigue-detector"
TARGET_PORT=8000

# ============================================
# VÉRIFICATION DES CREDENTIALS
# ============================================
if [ -z "${DOCKERHUB_PASSWORD:-}" ]; then
    echo "⚠️  DOCKERHUB_PASSWORD non défini"
    read -sp "Token Docker Hub (dckr_pat_xxx) : " DOCKERHUB_PASSWORD
    echo ""
    export DOCKERHUB_PASSWORD
fi

echo ""
echo "🔌 IMPORTANT :"
echo "   • Branchez le PC sur secteur"
echo "   • Désactivez la mise en veille"
echo "   • Connexion internet stable requise"
echo ""
read -p "Prêt ? Appuyez sur Entrée pour continuer..."

# ============================================
# 1) NETTOYAGE
# ============================================
echo ""
echo "1️⃣ Nettoyage des anciennes images..."
docker rmi "$DOCKERHUB_USERNAME/$IMAGE_NAME:$IMAGE_TAG" -f 2>/dev/null || true
docker rmi "$DOCKERHUB_USERNAME/$IMAGE_NAME:latest" -f 2>/dev/null || true

# ============================================
# 2) BUILD OPTIMISÉ
# ============================================
echo ""
echo "2️⃣ Build de l'image optimisée..."
echo "   ⏱️  Durée estimée : 5-10 minutes"
echo ""

docker build --no-cache -t "$DOCKERHUB_USERNAME/$IMAGE_NAME:$IMAGE_TAG" .

echo ""
echo "✅ Build terminé !"

# ============================================
# 3) VÉRIFICATION DE LA TAILLE
# ============================================
echo ""
echo "3️⃣ Vérification de la taille..."
IMAGE_SIZE=$(docker images "$DOCKERHUB_USERNAME/$IMAGE_NAME:$IMAGE_TAG" --format "{{.Size}}")
echo "   📦 Taille de l'image : $IMAGE_SIZE"

# Alerte si > 1.5 GB
SIZE_MB=$(docker images "$DOCKERHUB_USERNAME/$IMAGE_NAME:$IMAGE_TAG" --format "{{.Size}}" | sed 's/GB/*1024/;s/MB//' | bc 2>/dev/null || echo "0")
if (( $(echo "$SIZE_MB > 1500" | bc -l 2>/dev/null || echo 0) )); then
    echo "   ⚠️  Image volumineuse (> 1.5 GB). Vérifiez votre .dockerignore"
fi

# ============================================
# 4) CONNEXION DOCKER HUB
# ============================================
echo ""
echo "4️⃣ Connexion à Docker Hub..."
echo "$DOCKERHUB_PASSWORD" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin

# ============================================
# 5) PUSH VERS DOCKER HUB
# ============================================
echo ""
echo "5️⃣ Push vers Docker Hub..."
echo "   ⏱️  Durée estimée : 20-60 minutes selon connexion"
echo "   ⚠️  NE FERMEZ PAS LE PC !"
echo ""

docker tag "$DOCKERHUB_USERNAME/$IMAGE_NAME:$IMAGE_TAG" "$DOCKERHUB_USERNAME/$IMAGE_NAME:latest"
docker push "$DOCKERHUB_USERNAME/$IMAGE_NAME:$IMAGE_TAG" &
PUSH_PID=$!

# Barre de progression simple
while kill -0 $PUSH_PID 2>/dev/null; do
    echo -n "."
    sleep 5
done
wait $PUSH_PID

docker push "$DOCKERHUB_USERNAME/$IMAGE_NAME:latest"

echo ""
echo "✅ Push Docker Hub terminé !"

# ============================================
# 6) DÉPLOIEMENT AZURE
# ============================================
echo ""
echo "6️⃣ Déploiement sur Azure..."
echo ""

# Azure CLI check
az account show --query "{name:name}" -o json >/dev/null

# Extensions
if ! az extension show --name containerapp >/dev/null 2>&1; then
    echo "   📦 Installation extension containerapp..."
    az extension add --name containerapp --upgrade -y --only-show-errors
fi

# Providers
echo "   📝 Enregistrement des providers..."
az provider register --namespace Microsoft.App --wait
az provider register --namespace Microsoft.OperationalInsights --wait

# Resource Group
echo "   📁 Création Resource Group..."
az group create -n "$RESOURCE_GROUP" -l "$LOCATION" >/dev/null || true
echo "   ✅ RG OK: $RESOURCE_GROUP ($LOCATION)"

# Log Analytics
LAW_NAME="law-fatigue-$RANDOM"
echo "   📊 Création Log Analytics..."
az monitor log-analytics workspace create \
    -g "$RESOURCE_GROUP" \
    -n "$LAW_NAME" \
    -l "$LOCATION" >/dev/null
sleep 10

LAW_ID=$(az monitor log-analytics workspace show \
    --resource-group "$RESOURCE_GROUP" \
    --workspace-name "$LAW_NAME" \
    --query customerId -o tsv | tr -d '\r')

LAW_KEY=$(az monitor log-analytics workspace get-shared-keys \
    --resource-group "$RESOURCE_GROUP" \
    --workspace-name "$LAW_NAME" \
    --query primarySharedKey -o tsv | tr -d '\r')

echo "   ✅ Log Analytics OK"

# Container Apps Environment
echo "   🌍 Création Container Apps Environment..."
if ! az containerapp env show -n "$CONTAINERAPPS_ENV" -g "$RESOURCE_GROUP" >/dev/null 2>&1; then
  az containerapp env create \
    -n "$CONTAINERAPPS_ENV" \
    -g "$RESOURCE_GROUP" \
    -l "$LOCATION" \
    --logs-workspace-id "$LAW_ID" \
    --logs-workspace-key "$LAW_KEY" >/dev/null
fi
echo "   ✅ Environment OK"

# Container App
DOCKERHUB_IMAGE="$DOCKERHUB_USERNAME/$IMAGE_NAME:$IMAGE_TAG"
echo "   🐳 Déploiement Container App..."

if az containerapp show -n "$CONTAINER_APP_NAME" -g "$RESOURCE_GROUP" >/dev/null 2>&1; then
  az containerapp update \
    -n "$CONTAINER_APP_NAME" \
    -g "$RESOURCE_GROUP" \
    --image "$DOCKERHUB_IMAGE" \
    --registry-server docker.io \
    --registry-username "$DOCKERHUB_USERNAME" \
    --registry-password "$DOCKERHUB_PASSWORD" >/dev/null
else
  az containerapp create \
    -n "$CONTAINER_APP_NAME" \
    -g "$RESOURCE_GROUP" \
    --environment "$CONTAINERAPPS_ENV" \
    --image "$DOCKERHUB_IMAGE" \
    --ingress external \
    --target-port "$TARGET_PORT" \
    --registry-server docker.io \
    --registry-username "$DOCKERHUB_USERNAME" \
    --registry-password "$DOCKERHUB_PASSWORD" \
    --min-replicas 1 \
    --max-replicas 3 >/dev/null
fi

echo "   ✅ Container App OK"

# ============================================
# 7) RÉSULTAT FINAL
# ============================================
APP_URL=$(az containerapp show \
    -n "$CONTAINER_APP_NAME" \
    -g "$RESOURCE_GROUP" \
    --query properties.configuration.ingress.fqdn -o tsv | tr -d '\r')

echo ""
echo "=========================================="
echo "✅ DÉPLOIEMENT RÉUSSI !"
echo "=========================================="
echo ""
echo "📦 Docker Hub :"
echo "   https://hub.docker.com/r/$DOCKERHUB_USERNAME/$IMAGE_NAME"
echo ""
echo "🌐 URLs de l'application :"
echo "   API      : https://$APP_URL"
echo "   Health   : https://$APP_URL/health"
echo "   Docs     : https://$APP_URL/docs"
echo ""
echo "📊 Azure Resources :"
echo "   Resource Group : $RESOURCE_GROUP"
echo "   Location       : $LOCATION"
echo "   Container App  : $CONTAINER_APP_NAME"
echo ""
echo "🗑️  Pour supprimer :"
echo "   az group delete --name $RESOURCE_GROUP --yes --no-wait"
echo ""
echo "=========================================="