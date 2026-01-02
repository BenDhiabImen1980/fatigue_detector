#!/bin/bash
# Méthodesimple 

# Liste toutes les régions recommandées
echo "Régions disponibles chez toi :"
az account list-locations \
  --query "[?metadata.regionCategory=='Recommended'].name" \
  -o tsv | head -5

# Prendre la première
REGION=$(az account list-locations \
  --query "[?metadata.regionCategory=='Recommended'].name" \
  -o tsv | head -1)

echo "✅ proposition de la région : $REGION"