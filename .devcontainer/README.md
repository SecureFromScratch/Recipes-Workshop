# DevContainer Setup Guide

This project uses VS Code DevContainers to provide a consistent development environment.

## Prerequisites

- Docker Desktop installed and running
- Visual Studio Code with the "Dev Containers" extension installed
- Git

## What Gets Installed

When you open this project in a DevContainer, the following components are automatically set up:

### Tools & Runtimes

- ✅ .NET 8.0 SDK
- ✅ Node.js 20
- ✅ Angular CLI
- ✅ Entity Framework Core tools
- ✅ Docker (Docker-in-Docker)
- ✅ AWS CLI

### Services (via Docker Compose)

- ✅ SQL Server 2022 (port 14333)
- ✅ LocalStack for AWS Secrets Manager (port 4566)

### Database Setup

- ✅ Recipes database created
- ✅ `sa` user configured
- ✅ `recipes_app` user created
- ✅ Entity Framework migrations applied
- ✅ Tables: `Users`, `Recipe`

### AWS Secrets Manager (LocalStack)

- ✅ `recipes/dev/sa-password` - SQL Server SA password
- ✅ `recipes/dev/app-db-connection` - Application connection string
- ✅ `recipes/dev/jwt-config` - JWT configuration

## Setup Process

1. **Open the project in VS Code**
2. **Click "Reopen in Container"** when prompted (or use Command Palette: "Dev Containers: Reopen in Container")
3. **Wait for setup to complete** (~5-10 minutes on first run)
   - The `post-create.sh` script runs automatically
   - Watch the terminal output for progress

## Troubleshooting

### Setup Failed?

If the setup fails, you can:

1. **Check the logs**: Look at the terminal output for error messages
2. **Reset and retry**:

   ```bash
   bash /workspaces/Recipes-Workshop/.devcontainer/reset-environment.sh
   bash /workspaces/Recipes-Workshop/.devcontainer/post-create.sh
   ```

3. **Verify the setup**:
   ```bash
   bash /workspaces/Recipes-Workshop/.devcontainer/test-setup.sh
   ```

### Line Ending Issues?

If you see errors like `$'\r': command not found`, your files have Windows line endings.

**Fix it**:

```bash
# Convert all shell scripts to Unix line endings
find /workspaces/Recipes-Workshop -name "*.sh" -exec dos2unix {} \; 2>/dev/null || \
find /workspaces/Recipes-Workshop -name "*.sh" -exec sed -i 's/\r$//' {} \;
```

The `.gitattributes` file in this project ensures all files use LF endings going forward.

### SQL Server Won't Start?

If SQL Server fails with password errors:

```bash
cd /workspaces/Recipes-Workshop/src/Recipes.Api
docker compose down
docker volume rm recipesapi_mssql_data
MSSQL_SA_PASSWORD="StrongP4ssword123" docker compose up -d sqlserver
```

### LocalStack Connection Issues?

```bash
cd /workspaces/Recipes-Workshop/src/Recipes.Api
docker compose restart localstack
sleep 10
# Recreate secrets
bash /workspaces/Recipes-Workshop/.devcontainer/post-create.sh
```

## Manual Commands

### View Running Services

```bash
docker ps
```

### Check LocalStack Health

```bash
curl http://localhost:4566/_localstack/health
```

### Query Database

```bash
# Get SA password from secrets
SA_PASSWORD=$(aws --endpoint-url=http://localhost:4566 \
  secretsmanager get-secret-value \
  --secret-id recipes/dev/sa-password \
  --query SecretString --output text --region us-east-1)

# Connect to SQL Server
docker exec -it recipes-sqlserver /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "$SA_PASSWORD" -C -d Recipes
```

### Recreate Migrations

```bash
cd /workspaces/Recipes-Workshop/src/Recipes.Api
rm -rf Migrations
dotnet ef migrations add InitialCreate
dotnet ef database update
```

### View Container Logs

```bash
# SQL Server logs
docker logs recipes-sqlserver

# LocalStack logs
docker logs recipes-localstack
```

## Running the Application

### API

```bash
cd /workspaces/Recipes-Workshop/src/Recipes.Api
dotnet run
```

Access Swagger at: http://localhost:5000/swagger

### BFF (Backend for Frontend)

```bash
cd /workspaces/Recipes-Workshop/src/Recipes.Bff
dotnet run
```

### Angular UI

```bash
cd /workspaces/Recipes-Workshop/src/recipes-ui
npm start
```

Access the UI at: http://localhost:4200

## Files Changed

This setup includes the following fixes and improvements:

1. **`.gitattributes`** - Forces LF line endings for all text files
2. **`docker-compose.yml`** - Removed obsolete `version` field, added default password
3. **`.devcontainer/post-create.sh`** - Improved with:
   - Better SQL Server password handling
   - Container cleanup on password mismatch
   - Extended timeout for SQL Server startup
   - Better error messages and logging
4. **`.devcontainer/test-setup.sh`** - New script to verify setup
5. **`.devcontainer/reset-environment.sh`** - New script to clean up environment

## Need Help?

- Check the main [README.md](../README.md) for project documentation
- Review the [PREREQUISITES.md](../PREREQUISITES.md) for detailed requirements
- Ask your instructor during the workshop
