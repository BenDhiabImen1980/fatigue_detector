#!/usr/bin/env bash
set -euo pipefail

echo "🌩️  Déploiement Azure - Régions Container Apps uniquement"
echo "=========================================================="
echo ""

# ============================================
# CONFIGURATION
# ============================================
DOCKERHUB_USERNAME="bendhiab"
IMAGE_NAME="fatigue-api"
IMAGE_TAG="v1"
RESOURCE_GROUP="res_fatigue_detect"  
CONTAINER_APP_NAME="fatigue-detector" 
CONTAINERAPPS_ENV="env-fatigue-detector"
TARGET_PORT=8000

DOCKERHUB_IMAGE="$DOCKERHUB_USERNAME/$IMAGE_NAME:$IMAGE_TAG"

# ============================================
# RÉGIONS CONTAINER APPS VALIDES (liste officielle)
# ============================================
# Source : az containerapp env create --help
CONTAINER_APP_REGIONS=(
    "westus2"
    "southeastasia"
    "swedencentral"
    "canadacentral"
    "westeurope"
    "northeurope"
    "eastus"
    "eastus2"
    "eastasia"
    "australiaeast"
    "germanywestcentral"
    "japaneast"
    "uksouth"
    "westus"
    "centralus"
    "northcentralus"
    "southcentralus"
    "koreacentral"
    "brazilsouth"
    "westus3"
    "francecentral"
    "southafricanorth"
    "norwayeast"
    "switzerlandnorth"
    "uaenorth"
    "canadaeast"
    "westcentralus"
    "ukwest"
    "centralindia"
    "japanwest"
    "australiasoutheast"
    "francesouth"
    "spaincentral"
    "italynorth"
    "polandcentral"
    "southindia"
)

REGION_COUNT=${#CONTAINER_APP_REGIONS[@]}

echo "📋 Régions Container Apps disponibles : $REGION_COUNT"
echo ""

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
# DÉTECTION DE LA RÉGION FONCTIONNELLE
# ============================================
echo "🔍 Test des régions Container Apps (avec Log Analytics)..."
echo ""

WORKING_REGION=""
TEST_RG="test-region-$RANDOM"
TESTED=0
FAILED=0

for region in "${CONTAINER_APP_REGIONS[@]}"; do
    TESTED=$((TESTED + 1))
    echo -n "   [$TESTED/$REGION_COUNT] $region... "
    
    # Créer un RG temporaire
    if ! az group create -n "$TEST_RG" -l "$region" >/dev/null 2>&1; then
        echo "❌ Bloqué (RG)"
        FAILED=$((FAILED + 1))
        continue
    fi
    
    # Tester Log Analytics
    TEST_LAW="test-law-$RANDOM"
    if az monitor log-analytics workspace create \
        -g "$TEST_RG" \
        -n "$TEST_LAW" \
        -l "$region" \
        --query "name" -o tsv >/dev/null 2>&1; then
        echo "✅ DISPONIBLE !"
        WORKING_REGION="$region"
        
        # Nettoyer immédiatement
        az group delete -n "$TEST_RG" --yes --no-wait 2>/dev/null || true
        break
    else
        echo "❌ Bloqué (Log Analytics)"
        FAILED=$((FAILED + 1))
    fi
    
    # Nettoyer le RG de test
    az group delete -n "$TEST_RG" --yes --no-wait 2>/dev/null || true
    sleep 2
done

echo ""
echo "📊 Résumé des tests :"
echo "   Testées  : $TESTED/$REGION_COUNT"
echo "   Échouées : $FAILED"

if [ -z "$WORKING_REGION" ]; then
    echo ""
    echo "❌ ERREUR : Aucune région Container Apps disponible !"
    echo "   Toutes les $TESTED régions testées sont bloquées"
    echo ""
    echo "💡 Solutions :"
    echo "   1. Contactez le support Azure Éducation"
    echo "   2. Vérifiez les quotas de votre abonnement"
    echo "   3. Essayez avec un autre compte Azure"
    echo ""
    echo "📋 Régions testées :"
    for r in "${CONTAINER_APP_REGIONS[@]}"; do
        echo "      - $r"
    done
    exit 1
fi

echo ""
echo "🎯 Région trouvée : $WORKING_REGION"
LOCATION="$WORKING_REGION"

# ============================================
# SUPPRESSION DE L'ANCIEN RG (si autre région)
# ============================================
echo ""
echo "🧹 Vérification du Resource Group existant..."

if az group show -n "$RESOURCE_GROUP" >/dev/null 2>&1; then
    EXISTING_LOCATION=$(az group show -n "$RESOURCE_GROUP" --query location -o tsv | tr -d '\r')
    
    if [ "$EXISTING_LOCATION" != "$LOCATION" ]; then
        echo "   ⚠️  RG existe en $EXISTING_LOCATION (≠ $LOCATION)"
        echo "   🗑️  Suppression nécessaire..."
        az group delete -n "$RESOURCE_GROUP" --yes --no-wait
        
        echo "   ⏳ Attente de la suppression (60 sec)..."
        sleep 60
        
        # Vérification
        MAX_WAIT=120
        WAITED=0
        while az group show -n "$RESOURCE_GROUP" >/dev/null 2>&1; do
            if [ $WAITED -ge $MAX_WAIT ]; then
                echo "   ⚠️  La suppression prend du temps..."
                break
            fi
            echo -n "."
            sleep 10
            WAITED=$((WAITED + 10))
        done
        echo ""
        echo "   ✅ RG supprimé"
    else
        echo "   ✅ RG déjà dans la bonne région ($LOCATION)"
    fi
else
    echo "   ✅ Aucun RG existant"
fi

# ============================================
# DÉPLOIEMENT AZURE
# ============================================
echo ""
echo "🚀 Déploiement Azure en $LOCATION..."
echo ""

# Azure CLI check
az account show --query "{name:name}" -o json >/dev/null

# Extensions
if ! az extension show --name containerapp >/dev/null 2>&1; then
    echo "   📦 Installation extension containerapp..."
    az extension add --name containerapp --upgrade -y --only-show-errors
else
    echo "   ✅ Extension containerapp OK"
fi

# Providers
echo "   📝 Enregistrement des providers..."
az provider register --namespace Microsoft.App --wait
az provider register --namespace Microsoft.OperationalInsights --wait

# Resource Group
echo "   📁 Création Resource Group..."
az group create -n "$RESOURCE_GROUP" -l "$LOCATION" >/dev/null || true
echo "   ✅ RG: $RESOURCE_GROUP ($LOCATION)"

# Log Analytics
LAW_NAME="law-fatigue-$RANDOM"
echo "   📊 Création Log Analytics..."

if ! az monitor log-analytics workspace create \
    -g "$RESOURCE_GROUP" \
    -n "$LAW_NAME" \
    -l "$LOCATION" >/dev/null 2>&1; then
    echo "   ❌ ERREUR lors de la création de Log Analytics"
    echo "   Région testée : $LOCATION"
    echo "   Note : Cette région a pourtant réussi le test initial !"
    exit 1
fi

sleep 10

LAW_ID=$(az monitor log-analytics workspace show \
    --resource-group "$RESOURCE_GROUP" \
    --workspace-name "$LAW_NAME" \
    --query customerId -o tsv | tr -d '\r')

LAW_KEY=$(az monitor log-analytics workspace get-shared-keys \
    --resource-group "$RESOURCE_GROUP" \
    --workspace-name "$LAW_NAME" \
    --query primarySharedKey -o tsv | tr -d '\r')

echo "   ✅ Log Analytics: $LAW_NAME"

# Container Apps Environment
echo "   🌍 Création Container Apps Environment..."

# Supprimer l'ancien env s'il existe
az containerapp env delete \
    -n "$CONTAINERAPPS_ENV" \
    -g "$RESOURCE_GROUP" \
    --yes --no-wait 2>/dev/null || true

sleep 5

az containerapp env create \
    -n "$CONTAINERAPPS_ENV" \
    -g "$RESOURCE_GROUP" \
    -l "$LOCATION" \
    --logs-workspace-id "$LAW_ID" \
    --logs-workspace-key "$LAW_KEY" >/dev/null

echo "   ✅ Environment: $CONTAINERAPPS_ENV"

# Container App
echo "   🐳 Déploiement Container App depuis Docker Hub..."
echo "      Image: $DOCKERHUB_IMAGE"

# Supprimer l'ancienne app si elle existe
az containerapp delete \
    -n "$CONTAINER_APP_NAME" \
    -g "$RESOURCE_GROUP" \
    --yes --no-wait 2>/dev/null || true

sleep 5

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
    --max-replicas 3 \
    --cpu 0.5 \
    --memory 1.0Gi >/dev/null

echo "   ✅ Container App: $CONTAINER_APP_NAME"

# ============================================
# RÉSULTAT FINAL
# ============================================
echo ""
echo "⏳ Attente du démarrage de l'application (30 sec)..."
sleep 30

APP_URL=$(az containerapp show \
    -n "$CONTAINER_APP_NAME" \
    -g "$RESOURCE_GROUP" \
    --query properties.configuration.ingress.fqdn -o tsv | tr -d '\r')

echo ""
echo "=========================================="
echo "✅ DÉPLOIEMENT RÉUSSI !"
echo "=========================================="
echo ""
echo "📍 Région : $LOCATION"
echo "   (Trouvée après avoir testé $TESTED régions Container Apps)"
echo ""
echo "🌐 URLs de l'application :"
echo "   API      : https://$APP_URL"
echo "   Health   : https://$APP_URL/health"
echo "   Docs     : https://$APP_URL/docs"
echo ""
echo "📦 Docker Hub (intact) :"
echo "   https://hub.docker.com/r/$DOCKERHUB_USERNAME/$IMAGE_NAME"
echo ""
echo "📊 Ressources Azure :"
echo "   Resource Group : $RESOURCE_GROUP"
echo "   Location       : $LOCATION"
echo "   Container App  : $CONTAINER_APP_NAME"
echo "   Environment    : $CONTAINERAPPS_ENV"
echo "   Log Analytics  : $LAW_NAME"
echo ""
echo "🔧 Commandes utiles :"
echo "   Logs       : az containerapp logs show -n $CONTAINER_APP_NAME -g $RESOURCE_GROUP --follow"
echo "   Restart    : az containerapp restart -n $CONTAINER_APP_NAME -g $RESOURCE_GROUP"
echo "   Scale      : az containerapp update -n $CONTAINER_APP_NAME -g $RESOURCE_GROUP --min-replicas 2"
echo "   Delete     : az group delete --name $RESOURCE_GROUP --yes --no-wait"
echo ""
echo "=========================================="