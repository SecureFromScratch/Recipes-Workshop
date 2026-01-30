#!/bin/bash
# Reset script to clean up the development environment

set -e

echo "🧹 Cleaning up development environment..."
echo ""

cd /workspaces/Recipes-Workshop/src/Recipes.Api

# Stop and remove containers
echo "Stopping containers..."
docker compose down 2>/dev/null || true

# Remove volumes
echo "Removing volumes..."
docker volume rm recipesapi_mssql_data 2>/dev/null || true
docker volume rm recipesapi_localstack_data 2>/dev/null || true

# Remove migrations
echo "Removing migrations..."
rm -rf /workspaces/Recipes-Workshop/src/Recipes.Api/Migrations 2>/dev/null || true

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "To rebuild your environment, run:"
echo "  bash /workspaces/Recipes-Workshop/.devcontainer/post-create.sh"
echo ""
