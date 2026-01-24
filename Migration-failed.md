#!/usr/bin/env pwsh
# Database Setup and Migration Script for Windows
# Run this to setup/reset the database with migrations

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "   Database Setup & Migrations" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Navigate to API folder
$apiPath = Join-Path $PSScriptRoot "src\Recipes.Api"
if (-not (Test-Path $apiPath)) {
    $apiPath = ".\src\Recipes.Api"
}

if (-not (Test-Path $apiPath)) {
    Write-Host "[ERROR] Cannot find src\Recipes.Api folder!" -ForegroundColor Red
    Write-Host "Please run this script from the repository root." -ForegroundColor Yellow
    exit 1
}

Push-Location $apiPath

try {
    # Step 1: Get SA password from LocalStack
    Write-Host "[1/6] Getting SA password from Secrets Manager..." -ForegroundColor Green
    
    $saPasswordJson = aws --endpoint-url=http://localhost:4566 secretsmanager get-secret-value `
        --secret-id recipes/dev/sa-password `
        --query SecretString `
        --output text 2>$null
    
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($saPasswordJson)) {
        Write-Host "[ERROR] Failed to retrieve SA password from LocalStack!" -ForegroundColor Red
        Write-Host "Make sure LocalStack is running and secrets are created." -ForegroundColor Yellow
        exit 1
    }
    
    $SA_PASSWORD = $saPasswordJson
    Write-Host "      ✓ SA password retrieved" -ForegroundColor Gray
    
    # Step 2: Restart SQL Server with correct password
    Write-Host "`n[2/6] Restarting SQL Server..." -ForegroundColor Green
    
    # Stop SQL Server
    docker compose down sqlserver -v 2>$null | Out-Null
    Start-Sleep -Seconds 2
    
    # Set environment variable and start
    $env:MSSQL_SA_PASSWORD = $SA_PASSWORD
    docker compose up -d sqlserver 2>$null | Out-Null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to start SQL Server!" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "      ✓ SQL Server started" -ForegroundColor Gray
    Write-Host "      Waiting for SQL Server to be ready (20 seconds)..." -ForegroundColor Gray
    Start-Sleep -Seconds 20
    
    # Step 3: Test SQL Server connection
    Write-Host "`n[3/6] Testing SQL Server connection..." -ForegroundColor Green
    
    $connected = $false
    for ($i = 1; $i -le 10; $i++) {
        $testResult = docker exec recipes-sqlserver /opt/mssql-tools18/bin/sqlcmd `
            -S localhost -U sa -P "$SA_PASSWORD" -C -Q "SELECT 1" 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $connected = $true
            break
        }
        
        if ($i -lt 10) {
            Write-Host "      Attempt $i failed, retrying..." -ForegroundColor Gray
            Start-Sleep -Seconds 3
        }
    }
    
    if (-not $connected) {
        Write-Host "[ERROR] Cannot connect to SQL Server!" -ForegroundColor Red
        Write-Host "Check Docker logs: docker logs recipes-sqlserver" -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "      ✓ SQL Server is ready" -ForegroundColor Gray
    
    # Step 4: Initialize database
    Write-Host "`n[4/6] Initializing database..." -ForegroundColor Green
    
    $initResult = docker exec -i recipes-sqlserver /opt/mssql-tools18/bin/sqlcmd `
        -S localhost -U sa -P "$SA_PASSWORD" -C `
        -i /init/init-db.sql 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "      ✓ Database and users created" -ForegroundColor Gray
    } else {
        Write-Host "[WARNING] Database initialization had issues (may already exist)" -ForegroundColor Yellow
    }
    
    # Step 5: Create migrations
    Write-Host "`n[5/6] Creating Entity Framework migrations..." -ForegroundColor Green
    
    # Remove old migrations
    if (Test-Path "Migrations") {
        Remove-Item -Recurse -Force "Migrations"
        Write-Host "      ✓ Removed old migrations" -ForegroundColor Gray
    }
    
    # Create fresh migration
    dotnet ef migrations add InitialCreate 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "      ✓ Migration created" -ForegroundColor Gray
    } else {
        Write-Host "[ERROR] Failed to create migration!" -ForegroundColor Red
        dotnet ef migrations add InitialCreate
        exit 1
    }
    
    # Step 6: Apply migrations
    Write-Host "`n[6/6] Applying migration to database..." -ForegroundColor Green
    
    $connectionString = "Server=localhost,14333;Database=Recipes;User Id=sa;Password=$SA_PASSWORD;TrustServerCertificate=true;"
    
    dotnet ef database update --connection "$connectionString" 2>&1 | Out-Null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[WARNING] Migration failed, trying with verbose output..." -ForegroundColor Yellow
        dotnet ef database update --connection "$connectionString" --verbose
    }
    
    # Verify tables were created
    Write-Host "`n      Verifying tables..." -ForegroundColor Gray
    
    $tablesResult = docker exec recipes-sqlserver /opt/mssql-tools18/bin/sqlcmd `
        -S localhost -U sa -P "$SA_PASSWORD" -d Recipes -C -h-1 `
        -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.tables WHERE name IN ('Users', 'Recipe')" 2>&1
    
    $tableCount = ($tablesResult -replace '\s+', '').Trim()
    
    if ($tableCount -eq "2") {
        Write-Host "      ✓ Tables created: Users, Recipe" -ForegroundColor Gray
    } elseif ($tableCount -eq "1") {
        Write-Host "[WARNING] Only 1 table created (expected 2)" -ForegroundColor Yellow
        
        # Retry migration
        Write-Host "      Retrying migration..." -ForegroundColor Gray
        docker exec recipes-sqlserver /opt/mssql-tools18/bin/sqlcmd `
            -S localhost -U sa -P "$SA_PASSWORD" -d Recipes -C `
            -Q "DROP TABLE IF EXISTS __EFMigrationsHistory" 2>&1 | Out-Null
        
        Remove-Item -Recurse -Force "Migrations" -ErrorAction SilentlyContinue
        dotnet ef migrations add InitialCreate 2>&1 | Out-Null
        dotnet ef database update --connection "$connectionString" 2>&1 | Out-Null
        
        # Check again
        $tablesResult = docker exec recipes-sqlserver /opt/mssql-tools18/bin/sqlcmd `
            -S localhost -U sa -P "$SA_PASSWORD" -d Recipes -C -h-1 `
            -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.tables WHERE name IN ('Users', 'Recipe')" 2>&1
        
        $tableCount = ($tablesResult -replace '\s+', '').Trim()
        
        if ($tableCount -eq "2") {
            Write-Host "      ✓ Tables created on retry!" -ForegroundColor Gray
        } else {
            Write-Host "[ERROR] Tables still not created" -ForegroundColor Red
        }
    } else {
        Write-Host "[ERROR] Tables not created (found $tableCount, expected 2)" -ForegroundColor Red
        
        # Show what tables exist
        Write-Host "`n      Current tables:" -ForegroundColor Yellow
        docker exec recipes-sqlserver /opt/mssql-tools18/bin/sqlcmd `
            -S localhost -U sa -P "$SA_PASSWORD" -d Recipes -C `
            -Q "SELECT name FROM sys.tables ORDER BY name"
    }
    
    # Test recipes_app login
    Write-Host "`n      Testing recipes_app login..." -ForegroundColor Gray
    
    $loginTest = docker exec recipes-sqlserver /opt/mssql-tools18/bin/sqlcmd `
        -S localhost -U recipes_app -P "StrongP4ssword123" -d Recipes -C `
        -Q "SELECT 1" 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "      ✓ recipes_app login works" -ForegroundColor Gray
    } else {
        Write-Host "[WARNING] recipes_app cannot login" -ForegroundColor Yellow
    }
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "   ✓ DATABASE SETUP COMPLETE!" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    Write-Host "Tables in database:" -ForegroundColor White
    docker exec recipes-sqlserver /opt/mssql-tools18/bin/sqlcmd `
        -S localhost -U sa -P "$SA_PASSWORD" -d Recipes -C `
        -Q "SELECT name FROM sys.tables ORDER BY name"
    
    Write-Host "`nNext steps:" -ForegroundColor Cyan
    Write-Host "  1. Press F5 in VS Code to start the API" -ForegroundColor White
    Write-Host "  2. Test endpoints in Swagger (http://localhost:5000/swagger)" -ForegroundColor White
    Write-Host ""
    
} catch {
    Write-Host "`n[ERROR] Script failed: $_" -ForegroundColor Red
    exit 1
} finally {
    Pop-Location
}
