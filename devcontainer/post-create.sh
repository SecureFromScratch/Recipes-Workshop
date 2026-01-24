#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   SecureFromScratch - Recipes Workshop Setup             ║"
echo "║   Setting up your development environment...             ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Function for status messages
print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Step 1: Install Entity Framework Tools
print_step "Installing Entity Framework Core tools..."
dotnet tool install --global dotnet-ef --version 8.0.* > /dev/null 2>&1 || true
export PATH="$PATH:$HOME/.dotnet/tools"
echo 'export PATH="$PATH:$HOME/.dotnet/tools"' >> ~/.bashrc
print_success "EF Core tools installed"

# Step 2: Install Angular CLI
print_step "Installing Angular CLI..."
npm install -g @angular/cli > /dev/null 2>&1
print_success "Angular CLI installed"

# Step 3: Start Docker services
print_step "Starting LocalStack..."
cd src/Recipes.Api
docker compose up -d localstack > /dev/null 2>&1
print_success "LocalStack container started"

# Step 4: Wait for LocalStack to be ready
print_step "Waiting for LocalStack to initialize..."
sleep 10

# Check LocalStack health
for i in {1..30}; do
    if curl -s http://localhost:4566/_localstack/health > /dev/null 2>&1; then
        print_success "LocalStack is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        print_error "LocalStack failed to start"
        exit 1
    fi
    sleep 2
done

# Step 5: Configure AWS CLI
print_step "Configuring AWS CLI for LocalStack..."
aws configure set aws_access_key_id localstack
aws configure set aws_secret_access_key localstack
aws configure set default.region us-east-1
print_success "AWS CLI configured"

# Step 6: Create AWS Secrets
print_step "Creating AWS Secrets Manager secrets..."

# SA Password
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
    --name recipes/dev/sa-password \
    --secret-string "StrongP4ssword123" \
    > /dev/null 2>&1
print_success "Created secret: recipes/dev/sa-password"

# Database Connection String
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
    --name recipes/dev/app-db-connection \
    --secret-string "Server=localhost,14333;Database=Recipes;User Id=recipes_app;Password=StrongP4ssword123;TrustServerCertificate=true;" \
    > /dev/null 2>&1
print_success "Created secret: recipes/dev/app-db-connection"

# JWT Configuration (with proper JSON escaping)
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
    --name recipes/dev/jwt-config \
    --secret-string '{"Secret":"ThisIsAStrongJwtSecretKey1234567","Issuer":"recipes-api","Audience":"recipes-client"}' \
    > /dev/null 2>&1
print_success "Created secret: recipes/dev/jwt-config"

# Step 7: Install .NET packages
print_step "Installing NuGet packages (this may take 2-3 minutes)..."
cd ../..
dotnet restore > /dev/null 2>&1
print_success "NuGet packages installed"

# Step 8: Install npm packages
print_step "Installing npm packages (this may take 3-5 minutes)..."
cd src/recipes-ui
npm install > /dev/null 2>&1
print_success "npm packages installed"

# Step 9: Setup database
print_step "Setting up SQL Server and database..."
cd ../Recipes.Api

# Start SQL Server
docker compose up -d sqlserver > /dev/null 2>&1
print_success "SQL Server container started"

# Wait for SQL Server
print_step "Waiting for SQL Server to be ready..."
sleep 20

# Get SA password from secrets
SA_PASSWORD=$(aws --endpoint-url=http://localhost:4566 secretsmanager get-secret-value \
    --secret-id recipes/dev/sa-password \
    --query SecretString \
    --output text)

# Test SQL Server connection
for i in {1..10}; do
    if docker exec recipes-sqlserver /opt/mssql-tools18/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASSWORD" -C -Q "SELECT 1" > /dev/null 2>&1; then
        print_success "SQL Server is ready"
        break
    fi
    if [ $i -eq 10 ]; then
        print_error "SQL Server failed to start"
        exit 1
    fi
    sleep 5
done

# Run init-db.sql
print_step "Initializing database..."
docker exec -i recipes-sqlserver /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "$SA_PASSWORD" -C \
    -i /init/init-db.sql > /dev/null 2>&1
print_success "Database initialized"

# Step 10: Create and apply migrations
print_step "Creating Entity Framework migrations..."

# Remove old migrations if they exist
if [ -d "Migrations" ]; then
    rm -rf Migrations
    print_warning "Removed old migrations"
fi

# Create fresh migration
dotnet ef migrations add InitialCreate > /dev/null 2>&1
print_success "Migration created"

# Apply migration
print_step "Applying migration to database..."
CONN_STRING="Server=localhost,14333;Database=Recipes;User Id=sa;Password=$SA_PASSWORD;TrustServerCertificate=true;"
dotnet ef database update --connection "$CONN_STRING" > /dev/null 2>&1

# Verify tables were created
TABLES_COUNT=$(docker exec recipes-sqlserver /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "$SA_PASSWORD" -d Recipes -C -h-1 \
    -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.tables WHERE name IN ('Users', 'Recipe')" 2>&1 | tr -d '[:space:]')

if [ "$TABLES_COUNT" = "2" ]; then
    print_success "Database migration applied successfully"
    print_success "Tables created: Users, Recipe"
else
    print_error "Migration may have failed - tables not detected"
    print_warning "You may need to run migrations manually"
fi

# Final setup
cd ../..

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   ✅ SETUP COMPLETE!                                     ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}Your development environment is ready!${NC}"
echo ""
echo "🚀 Quick Start:"
echo "   1. Press F5 to start debugging (API + BFF)"
echo "   2. Open terminal and run:"
echo "      cd src/recipes-ui && ng serve --host 0.0.0.0"
echo "   3. Click on the 'PORTS' tab below"
echo "   4. Click the globe icon next to port 4200"
echo ""
echo "📚 Useful Commands:"
echo "   • View running containers: docker ps"
echo "   • Restart database: cd src/Recipes.Api && docker compose restart sqlserver"
echo "   • View API at: http://localhost:5000/swagger"
echo ""
echo "🆘 Need Help?"
echo "   • Check README.md for documentation"
echo "   • Ask your instructor"
echo ""
echo "Happy Coding! 🎉"
echo ""
