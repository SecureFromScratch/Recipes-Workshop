#!/bin/bash
# Test script to verify the devcontainer setup

echo "Testing devcontainer setup..."
echo ""

# Test 1: Check if dotnet-ef is installed
echo -n "✓ Checking dotnet-ef tool... "
if command -v dotnet-ef &> /dev/null; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

# Test 2: Check if Angular CLI is installed
echo -n "✓ Checking Angular CLI... "
if command -v ng &> /dev/null; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

# Test 3: Check if Docker is available
echo -n "✓ Checking Docker... "
if docker ps &> /dev/null; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

# Test 4: Check if LocalStack is running
echo -n "✓ Checking LocalStack... "
if docker ps | grep -q "recipes-localstack"; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

# Test 5: Check if SQL Server is running
echo -n "✓ Checking SQL Server... "
if docker ps | grep -q "recipes-sqlserver"; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

# Test 6: Check if secrets are configured
echo -n "✓ Checking AWS secrets... "
if aws --endpoint-url=http://localhost:4566 secretsmanager get-secret-value \
    --secret-id recipes/dev/sa-password --region us-east-1 &> /dev/null; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

# Test 7: Check if database tables exist
echo -n "✓ Checking database tables... "
SA_PASSWORD=$(aws --endpoint-url=http://localhost:4566 secretsmanager get-secret-value \
    --secret-id recipes/dev/sa-password --query SecretString --output text --region us-east-1)

TABLES_COUNT=$(docker exec recipes-sqlserver /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "$SA_PASSWORD" -d Recipes -C -h-1 \
    -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.tables WHERE name IN ('Users', 'Recipe')" 2>&1 | tr -d '[:space:]')

if [ "$TABLES_COUNT" = "2" ]; then
    echo "OK"
else
    echo "FAILED (found $TABLES_COUNT tables, expected 2)"
    exit 1
fi

# Test 8: Check if recipes_app user can login
echo -n "✓ Checking recipes_app user... "
if docker exec recipes-sqlserver /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U recipes_app -P "StrongP4ssword123" -d Recipes -C \
    -Q "SELECT 1" &> /dev/null; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

echo ""
echo "✅ All tests passed! Your development environment is ready."
echo ""
