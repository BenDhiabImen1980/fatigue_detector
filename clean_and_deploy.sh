#!/usr/bin/env bash
set -euo pipefail

RESOURCE_GROUP="res_fatigue_detect"

echo "🧹 Nettoyage et déploiement"
echo "==========================="
echo ""

# ============================================
# 1) SUPPRESSION DU RESOURCE GROUP EXISTANT
# ============================================
echo "1️⃣ Vérification du Resource Group existant..."

if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
    echo "   ⚠️  Resource Group '$RESOURCE_GROUP' existe"
    echo ""
    read -p "   Voulez-vous le supprimer ? (y/N) : " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "   🗑️  Suppression en cours..."
        az group delete --name "$RESOURCE_GROUP" --yes --no-wait
        
        echo "   ⏳ Attente de la suppression complète (60 secondes)..."
        sleep 60
        
        # Vérification que c'est bien supprimé
        MAX_WAIT=120
        WAITED=0
        while az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; do
            if [ $WAITED -ge $MAX_WAIT ]; then
                echo "   ⚠️  Timeout : la suppression prend plus de temps que prévu"
                echo "   Continuez quand même ? (y/N) : "
                read -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    echo "   ❌ Déploiement annulé"
                    exit 1
                fi
                break
            fi
            echo "   ⏳ Attente... ($WAITED secondes)"
            sleep 10
            WAITED=$((WAITED + 10))
        done
        
        echo "   ✅ Resource Group supprimé"
    else
        echo "   ⚠️  Déploiement annulé"
        exit 0
    fi
else
    echo "   ✅ Aucun Resource Group existant"
fi

echo ""
echo "=========================================="
echo ""

# ============================================
# 2) LANCEMENT DU DÉPLOIEMENT OPTIMISÉ
# ============================================
echo "2️⃣ Lancement du déploiement optimisé..."
echo ""

if [ ! -f "./deploy_optimized.sh" ]; then
    echo "❌ ERREUR : deploy_optimized.sh introuvable"
    echo "   Créez d'abord ce fichier avec le contenu de l'artifact"
    exit 1
fi

# Exécuter le script de déploiement
./deploy_optimized.sh