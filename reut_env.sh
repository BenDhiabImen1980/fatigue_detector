#!/usr/bin/env bash
set -euo pipefail

echo "🌩️  Déploiement intelligent - Réutilisation de l'environment existant"
echo "===================================================================="
echo ""

# ============================================
# CONFIGURATION
# ============================================
DOCKERHUB_USERNAME="bendhiab"
IMAGE_NAME="fatigue-api"
IMAGE_TAG="v1"
CONTAINER_APP_NAME="fatigue-detector"
TARGET_PORT=8000

DOCKERHUB_IMAGE="$DOCKERHUB_USERNAME/$IMAGE_NAME:$IMAGE_TAG"

# ============================================
# CREDENTIALS DOCKER HUB
# ============================================
if [ -z "${DOCKERHUB_PASSWORD:-}" ]; then
    echo "⚠️  DOCKERHUB_PASSWORD non défini"
    read -sp "Token Docker Hub (pour pull) : " DOCKERHUB_PASSWORD
    echo ""
    export DOCKERHUB_PASSWORD
fi

# ============================================
# 1) RECHERCHE DE L'ENVIRONMENT EXISTANT
# ============================================
echo "1️⃣ Recherche de l'environment Container Apps existant..."
echo ""

EXISTING_ENVS=$(az containerapp env list --query "[].{Name:name, Location:location, RG:resourceGroup}" -o json 2>/dev/null || echo "[]")
ENV_COUNT=$(echo "$EXISTING_ENVS" | jq '. | length')

if [ "$ENV_COUNT" -eq 0 ]; then
    echo "❌ ERREUR : Aucun environment Container Apps trouvé !"
    echo "   Votre abonnement ne permet pas de créer un nouvel environment."
    echo "   Veuillez d'abord créer un environment manuellement avec :"
    echo "   az containerapp env create ..."
    exit 1
fi

# Prendre le premier environment trouvé
EXISTING_ENV_NAME=$(echo "$EXISTING_ENVS" | jq -r '.[0].Name')
LOCATION=$(echo "$EXISTING_ENVS" | jq -r '.[0].Location')
RESOURCE_GROUP=$(echo "$EXISTING_ENVS" | jq -r '.[0].RG')

echo "   ✅ Environment trouvé : $EXISTING_ENV_NAME"
echo "   📍 Région : $LOCATION"
echo "   📦 Resource Group : $RESOURCE_GROUP"
echo ""

# ============================================
# 2) VÉRIFICATION DU RESOURCE GROUP
# ============================================
echo "2️⃣ Vérification du Resource Group..."
if ! az group show -n "$RESOURCE_GROUP" >/dev/null 2>&1; then
    echo "❌ ERREUR : Resource Group '$RESOURCE_GROUP' non trouvé !"
    exit 1
fi
echo "   ✅ Resource Group accessible"
echo ""

# ============================================
# 3) DÉPLOIEMENT/MISE À JOUR DE LA CONTAINER APP
# ============================================
echo "3️⃣ Gestion de l'application Container App..."
echo ""

# Vérifier si l'application existe déjà
if az containerapp show -n "$CONTAINER_APP_NAME" -g "$RESOURCE_GROUP" >/dev/null 2>&1; then
    echo "   🔄 Application existante détectée : $CONTAINER_APP_NAME"
    
    # Vérifier si l'application est dans le bon environment
    CURRENT_ENV=$(az containerapp show -n "$CONTAINER_APP_NAME" -g "$RESOURCE_GROUP" \
        --query "properties.environmentId" -o tsv | grep -o '[^/]*$')
    
    if [ "$CURRENT_ENV" != "$EXISTING_ENV_NAME" ]; then
        echo "   ⚠️  L'application est dans un environment différent : $CURRENT_ENV"
        echo "   🗑️  Suppression de l'ancienne application..."
        az containerapp delete -n "$CONTAINER_APP_NAME" -g "$RESOURCE_GROUP" --yes --no-wait
        sleep 15
        
        echo "   🆕 Création de la nouvelle application dans l'environment correct..."
        az containerapp create -n "$CONTAINER_APP_NAME" -g "$RESOURCE_GROUP" \
            --environment "$EXISTING_ENV_NAME" \
            --image "$DOCKERHUB_IMAGE" \
            --ingress external \
            --target-port "$TARGET_PORT" \
            --registry-server docker.io \
            --registry-username "$DOCKERHUB_USERNAME" \
            --registry-password "$DOCKERHUB_PASSWORD" \
            --min-replicas 1 \
            --max-replicas 3 \
            --cpu 0.5 \
            --memory 1.0Gi >/dev/null
    else
        echo "   📦 Mise à jour de l'image Docker..."
        az containerapp update -n "$CONTAINER_APP_NAME" -g "$RESOURCE_GROUP" \
            --image "$DOCKERHUB_IMAGE" \
            --registry-server docker.io \
            --registry-username "$DOCKERHUB_USERNAME" \
            --registry-password "$DOCKERHUB_PASSWORD" >/dev/null
    fi
    
    echo "   ✅ Application mise à jour"
else
    echo "   🆕 Création de l'application : $CONTAINER_APP_NAME"
    echo "   📦 Déploiement de l'image : $DOCKERHUB_IMAGE"
    
    az containerapp create -n "$CONTAINER_APP_NAME" -g "$RESOURCE_GROUP" \
        --environment "$EXISTING_ENV_NAME" \
        --image "$DOCKERHUB_IMAGE" \
        --ingress external \
        --target-port "$TARGET_PORT" \
        --registry-server docker.io \
        --registry-username "$DOCKERHUB_USERNAME" \
        --registry-password "$DOCKERHUB_PASSWORD" \
        --min-replicas 1 \
        --max-replicas 3 \
        --cpu 0.5 \
        --memory 1.0Gi >/dev/null
    
    echo "   ✅ Application créée"
fi
echo ""

# ============================================
# 4) ATTENTE ET AFFICHAGE DU RÉSULTAT
# ============================================
echo "4️⃣ Récupération des informations..."
sleep 20

# Essayer plusieurs fois de récupérer l'URL
MAX_RETRIES=5
RETRY_COUNT=0
APP_URL=""

while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ -z "$APP_URL" ]; do
    echo "   Tentative $((RETRY_COUNT + 1))/$MAX_RETRIES..."
    APP_URL=$(az containerapp show \
        -n "$CONTAINER_APP_NAME" \
        -g "$RESOURCE_GROUP" \
        --query properties.configuration.ingress.fqdn -o tsv 2>/dev/null | tr -d '\r' || echo "")
    
    if [ -z "$APP_URL" ]; then
        sleep 10
        RETRY_COUNT=$((RETRY_COUNT + 1))
    fi
done

echo ""
echo "=========================================="
echo "✅ DÉPLOIEMENT RÉUSSI !"
echo "=========================================="
echo ""

if [ -n "$APP_URL" ]; then
    echo "🌐 API    : https://$APP_URL"
    echo "❤️ Health : https://$APP_URL/health"
    echo "📚 Docs   : https://$APP_URL/docs"
else
    echo "⚠️  URL non disponible immédiatement"
    echo "Pour récupérer l'URL plus tard :"
    echo "az containerapp show -n $CONTAINER_APP_NAME -g $RESOURCE_GROUP --query properties.configuration.ingress.fqdn"
fi

echo ""
echo "📋 Informations de déploiement :"
echo "   - Application : $CONTAINER_APP_NAME"
echo "   - Resource Group : $RESOURCE_GROUP"
echo "   - Environment : $EXISTING_ENV_NAME"
echo "   - Région : $LOCATION"
echo "   - Image : $DOCKERHUB_IMAGE"
echo "=========================================="

# Ajout d'une commande pour vérifier l'état
echo ""
echo "🔍 Vérification de l'état :"
az containerapp show -n "$CONTAINER_APP_NAME" -g "$RESOURCE_GROUP" \
    --query "{Name:name, State:properties.provisioningState, URL:properties.configuration.ingress.fqdn, Replicas:properties.template.scaleRules}" \
    -o table