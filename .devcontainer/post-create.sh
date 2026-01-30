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
cd /workspaces/Recipes-Workshop/src/Recipes.Api
docker compose up -d localstack > /dev/null 2>&1
print_success "LocalStack container started"

# Step 4: Wait for LocalStack to be ready
print_step "Waiting for LocalStack to initialize (15 seconds)..."
sleep 15

# Check LocalStack health with retries
for i in {1..10}; do
    if curl -s http://localhost:4566/_localstack/health > /dev/null 2>&1; then
        print_success "LocalStack is ready"
        break
    fi
    if [ $i -eq 10 ]; then
        print_error "LocalStack failed to start"
        exit 1
    fi
    sleep 3
done

# Step 5: Configure AWS CLI
print_step "Configuring AWS CLI for LocalStack..."
aws configure set aws_access_key_id localstack
aws configure set aws_secret_access_key localstack
aws configure set default.region us-east-1
print_success "AWS CLI configured"

# Step 6: Create AWS Secrets
print_step "Creating AWS Secrets Manager secrets..."

# Create secrets (ignore errors if they already exist)
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
    --name recipes/dev/sa-password \
    --secret-string "StrongP4ssword123" \
    > /dev/null 2>&1 || true
print_success "Created secret: recipes/dev/sa-password"

aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
    --name recipes/dev/app-db-connection \
    --secret-string "Server=localhost,14333;Database=Recipes;User Id=recipes_app;Password=StrongP4ssword123;TrustServerCertificate=true;" \
    > /dev/null 2>&1 || true
print_success "Created secret: recipes/dev/app-db-connection"

aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
    --name recipes/dev/jwt-config \
    --secret-string '{"Secret":"ThisIsAStrongJwtSecretKey1234567","Issuer":"recipes-api","Audience":"recipes-client"}' \
    > /dev/null 2>&1 || true
print_success "Created secret: recipes/dev/jwt-config"

# Step 7: Install .NET packages
print_step "Installing NuGet packages (this may take 2-3 minutes)..."
cd /workspaces/Recipes-Workshop
dotnet restore > /dev/null 2>&1
print_success "NuGet packages installed"

# Step 8: Install npm packages
print_step "Installing npm packages (this may take 3-5 minutes)..."
cd /workspaces/Recipes-Workshop/src/recipes-ui
npm install > /dev/null 2>&1
print_success "npm packages installed"

# Step 9: Setup SQL Server and Database
print_step "Setting up SQL Server and database..."
cd /workspaces/Recipes-Workshop/src/Recipes.Api

# Get SA password from secrets
SA_PASSWORD=$(aws --endpoint-url=http://localhost:4566 secretsmanager get-secret-value \
    --secret-id recipes/dev/sa-password \
    --query SecretString \
    --output text)

if [ -z "$SA_PASSWORD" ]; then
    print_error "Failed to retrieve SA password from secrets"
    exit 1
fi

# Check if SQL Server container exists and remove it if password doesn't match
if docker ps -a --format '{{.Names}}' | grep -q "^recipes-sqlserver$"; then
    print_step "Checking existing SQL Server container..."
    # Try to connect with the expected password
    if ! docker exec recipes-sqlserver /opt/mssql-tools18/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASSWORD" -C -Q "SELECT 1" > /dev/null 2>&1; then
        print_warning "SQL Server password mismatch detected, recreating container..."
        docker compose down sqlserver > /dev/null 2>&1
        docker volume rm recipesapi_mssql_data > /dev/null 2>&1 || true
    fi
fi

# Start SQL Server with correct password
export MSSQL_SA_PASSWORD="$SA_PASSWORD"
docker compose up -d sqlserver > /dev/null 2>&1
print_success "SQL Server container started"

# Wait for SQL Server with proper health check
print_step "Waiting for SQL Server to be ready..."
READY=0
for i in {1..30}; do
    if docker exec recipes-sqlserver /opt/mssql-tools18/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASSWORD" -C -Q "SELECT 1" > /dev/null 2>&1; then
        READY=1
        print_success "SQL Server is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        print_error "SQL Server failed to start after 150 seconds"
        print_step "Container logs:"
        docker logs --tail 50 recipes-sqlserver
        exit 1
    fi
    sleep 5
done

if [ $READY -eq 0 ]; then
    print_error "SQL Server is not ready"
    exit 1
fi

# Step 10: Initialize database
print_step "Initializing database and users..."
docker exec -i recipes-sqlserver /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "$SA_PASSWORD" -C \
    -i /init/init-db.sql > /dev/null 2>&1

if [ $? -eq 0 ]; then
    print_success "Database and users created"
else
    print_error "Database initialization failed"
    exit 1
fi

# Step 11: Check if tables already exist
print_step "Checking if database tables already exist..."
EXISTING_TABLES=$(docker exec recipes-sqlserver /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "$SA_PASSWORD" -d Recipes -C -h-1 \
    -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.tables WHERE name IN ('Users', 'Recipe')" 2>&1 | tr -d '[:space:]')

if [ "$EXISTING_TABLES" = "2" ]; then
    print_success "Tables already exist, skipping migrations"
else
    # Step 12: Create and apply migrations
    print_step "Creating Entity Framework migrations..."

    # Remove old migrations if they exist
    if [ -d "Migrations" ]; then
        rm -rf Migrations
        print_warning "Removed old migrations"
    fi

    # Create fresh migration
    dotnet ef migrations add InitialCreate > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        print_success "Migration created"
    else
        print_error "Migration creation failed"
        exit 1
    fi

    # Apply migration
    print_step "Applying migration to database..."
    CONN_STRING="Server=localhost,14333;Database=Recipes;User Id=sa;Password=$SA_PASSWORD;TrustServerCertificate=true;"

    # First attempt
    if dotnet ef database update --connection "$CONN_STRING" > /dev/null 2>&1; then
        print_success "Migration applied successfully"
    else
        print_warning "First migration attempt failed, trying with verbose output..."
        if ! dotnet ef database update --connection "$CONN_STRING"; then
            print_error "Migration failed on retry"
            exit 1
        fi
    fi
fi

# Step 13: Verify tables were created
print_step "Verifying database tables..."
TABLES_COUNT=$(docker exec recipes-sqlserver /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "$SA_PASSWORD" -d Recipes -C -h-1 \
    -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.tables WHERE name IN ('Users', 'Recipe')" 2>&1 | tr -d '[:space:]')

if [ "$TABLES_COUNT" = "2" ]; then
    print_success "Database tables verified: Users, Recipe"
elif [ "$TABLES_COUNT" = "1" ]; then
    print_error "Only 1 table found, expected 2"
    print_step "Current tables in database:"
    docker exec recipes-sqlserver /opt/mssql-tools18/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASSWORD" -d Recipes -C \
        -Q "SELECT name FROM sys.tables ORDER BY name"
    exit 1
else
    print_error "Tables not found in database"
    print_step "Current tables in database:"
    docker exec recipes-sqlserver /opt/mssql-tools18/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASSWORD" -d Recipes -C \
        -Q "SELECT name FROM sys.tables ORDER BY name"
    exit 1
fi

# Step 14: Verify recipes_app can login
print_step "Verifying recipes_app user can login..."
if docker exec recipes-sqlserver /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U recipes_app -P "StrongP4ssword123" -d Recipes -C \
    -Q "SELECT 1" > /dev/null 2>&1; then
    print_success "recipes_app login verified"
else
    print_error "recipes_app cannot login!"
    exit 1
fi

# Clean up environment variable
unset MSSQL_SA_PASSWORD

# Final setup
cd /workspaces/Recipes-Workshop

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
