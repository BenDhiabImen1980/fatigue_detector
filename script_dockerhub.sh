#!/usr/bin/env bash
set -euo pipefail

#################################
# VARIABLES
#################################
RESOURCE_GROUP="res_fatigue_detect"  
LOCATION="eastus"
CONTAINER_APP_NAME="fatigue-detector" 
CONTAINERAPPS_ENV="env-fatigue-detector"
IMAGE_NAME="fatigue-api"
IMAGE_TAG="v1"
TARGET_PORT=8000

# Docker Hub credentials (À REMPLIR)
DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-your_dockerhub_username}"
DOCKERHUB_PASSWORD="${DOCKERHUB_PASSWORD:-your_dockerhub_password}"

#################################
# Vérification des credentials Docker Hub
#################################
if [ "$DOCKERHUB_USERNAME" = "your_dockerhub_username" ] || [ -z "$DOCKERHUB_USERNAME" ]; then
    echo "❌ ERREUR: Configurez vos credentials Docker Hub"
    echo ""
    echo "Méthode 1 - Variables d'environnement (recommandé) :"
    echo "  export DOCKERHUB_USERNAME='votre_username'"
    echo "  export DOCKERHUB_PASSWORD='votre_password'"
    echo "  ./script_dockerhub.sh"
    echo ""
    echo "Méthode 2 - Modifier le script :"
    echo "  Éditez ce fichier et remplacez 'your_dockerhub_username' et 'your_dockerhub_password'"
    echo ""
    echo "Pas de compte Docker Hub ? Créez-en un gratuitement sur https://hub.docker.com"
    exit 1
fi

#################################
# 0) Contexte Azure + Extensions
#################################
echo "Vérification du contexte Azure..."
az account show --query "{name:name, cloudName:cloudName}" -o json >/dev/null

echo "Vérification/installation des extensions Azure CLI..."
if ! az extension show --name containerapp >/dev/null 2>&1; then
    az extension add --name containerapp --upgrade -y --only-show-errors
else
    az extension update --name containerapp -y --only-show-errors 2>/dev/null || true
fi

#################################
# 1) Providers
#################################
echo "Register providers..."
az provider register --namespace Microsoft.App --wait
az provider register --namespace Microsoft.OperationalInsights --wait

#################################
# 2) Resource Group
#################################
echo "Création du groupe de ressources..."
az group create -n "$RESOURCE_GROUP" -l "$LOCATION" >/dev/null || true
echo "✅ RG OK: $RESOURCE_GROUP ($LOCATION)"

#################################
# 3) Build + Push vers Docker Hub
#################################
echo "Connexion à Docker Hub..."
echo "$DOCKERHUB_PASSWORD" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin

DOCKERHUB_IMAGE="$DOCKERHUB_USERNAME/$IMAGE_NAME:$IMAGE_TAG"
echo "Build de l'image..."
docker build -t "$DOCKERHUB_IMAGE" .

echo "Push vers Docker Hub..."
docker tag "$DOCKERHUB_IMAGE" "$DOCKERHUB_USERNAME/$IMAGE_NAME:latest"
docker push "$DOCKERHUB_IMAGE"
docker push "$DOCKERHUB_USERNAME/$IMAGE_NAME:latest"
echo "✅ Image pushée sur Docker Hub: $DOCKERHUB_IMAGE"

#################################
# 4) Log Analytics
#################################
LAW_NAME="law-fatigue-$RANDOM"
echo "Création Log Analytics: $LAW_NAME"
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
echo "✅ Log Analytics OK"

#################################
# 5) Container Apps Environment
#################################
echo "Création Container Apps Environment..."
if ! az containerapp env show -n "$CONTAINERAPPS_ENV" -g "$RESOURCE_GROUP" >/dev/null 2>&1; then
  az containerapp env create \
    -n "$CONTAINERAPPS_ENV" \
    -g "$RESOURCE_GROUP" \
    -l "$LOCATION" \
    --logs-workspace-id "$LAW_ID" \
    --logs-workspace-key "$LAW_KEY" >/dev/null
fi
echo "✅ Environment OK"

#################################
# 6) Déploiement Container App (depuis Docker Hub)
#################################
echo "Déploiement Container App depuis Docker Hub..."

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
echo "✅ Container App déployée"

#################################
# 7) URL API
#################################
APP_URL=$(az containerapp show \
    -n "$CONTAINER_APP_NAME" \
    -g "$RESOURCE_GROUP" \
    --query properties.configuration.ingress.fqdn -o tsv | tr -d '\r')

echo ""
echo "=========================================="
echo "✅ DÉPLOIEMENT RÉUSSI (Docker Hub)"
echo "=========================================="
echo "Region         : $LOCATION"
echo "Resource Group : $RESOURCE_GROUP"
echo "Docker Hub     : $DOCKERHUB_USERNAME/$IMAGE_NAME:$IMAGE_TAG"
echo ""
echo "URLs de l'application :"
echo "  API      : https://$APP_URL"
echo "  Health   : https://$APP_URL/health"
echo "  Docs     : https://$APP_URL/docs"
echo ""
echo "Pour supprimer :"
echo "  az group delete --name $RESOURCE_GROUP --yes --no-wait"
echo "=========================================="