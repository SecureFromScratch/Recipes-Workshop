#!/usr/bin/env pwsh
# Recipes Workshop - Automated Setup Script
# For use with the dedicated Recipes-Workshop repository

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "   Recipes Workshop - Automated Setup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Check if running on Windows
if (-not $IsWindows -and -not ($PSVersionTable.PSVersion.Major -ge 6 -and $PSVersionTable.Platform -eq "Win32NT")) {
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        # Running on Windows PowerShell (version 5.1 or earlier)
        $IsWindows = $true
    }
}

if (-not $IsWindows) {
    Write-Host "[ERROR] This script is designed for Windows. For other platforms, use GitHub Codespaces!" -ForegroundColor Red
    Write-Host "See: CODESPACES-QUICKSTART.md" -ForegroundColor Yellow
    exit 1
}

# Step 1: Check Docker Desktop
Write-Host "[1/10] Checking Docker Desktop..." -ForegroundColor Green
$dockerRunning = docker ps 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Docker Desktop is not running!" -ForegroundColor Red
    Write-Host "" -ForegroundColor Yellow
    Write-Host "Please:" -ForegroundColor Yellow
    Write-Host "  1. Install Docker Desktop: https://www.docker.com/products/docker-desktop" -ForegroundColor Gray
    Write-Host "  2. RESTART your computer (required after installation)" -ForegroundColor Gray
    Write-Host "  3. Start Docker Desktop" -ForegroundColor Gray
    Write-Host "  4. Wait for the whale icon to appear in the system tray" -ForegroundColor Gray
    Write-Host "  5. Run this script again" -ForegroundColor Gray
    Write-Host "" -ForegroundColor Yellow
    Write-Host "See PREREQUISITES.md for detailed instructions." -ForegroundColor Yellow
    exit 1
}
Write-Host "      ✓ Docker Desktop is running" -ForegroundColor Gray

# Step 2: Check PowerShell execution policy
Write-Host "`n[2/10] Checking PowerShell execution policy..." -ForegroundColor Green
$executionPolicy = Get-ExecutionPolicy -Scope CurrentUser
if ($executionPolicy -eq "Restricted") {
    Write-Host "      PowerShell execution policy is Restricted" -ForegroundColor Yellow
    Write-Host "      Would you like to change it to RemoteSigned? (Recommended)" -ForegroundColor Yellow
    $response = Read-Host "      Change policy? (Y/N)"
    
    if ($response -eq "Y" -or $response -eq "y") {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Write-Host "      ✓ Execution policy updated to RemoteSigned" -ForegroundColor Gray
    } else {
        Write-Host "[ERROR] Cannot continue with Restricted execution policy" -ForegroundColor Red
        Write-Host "Please run: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host "      ✓ Execution policy is $executionPolicy" -ForegroundColor Gray
}

# Step 3: Install .NET 8 SDK
Write-Host "`n[3/10] Checking .NET 8 SDK..." -ForegroundColor Green
$dotnetVersion = dotnet --version 2>&1
if ($LASTEXITCODE -ne 0 -or -not ($dotnetVersion -like "8.*")) {
    Write-Host "      Installing .NET 8 SDK via winget..." -ForegroundColor Gray
    winget install Microsoft.DotNet.SDK.8 --silent --accept-source-agreements --accept-package-agreements
    
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    
    # Wait for dotnet to be available
    $attempts = 0
    while ($attempts -lt 15) {
        $dotnetCheck = dotnet --version 2>&1
        if ($LASTEXITCODE -eq 0) { break }
        Start-Sleep -Seconds 1
        $attempts++
    }
    Write-Host "      ✓ .NET 8 SDK installed" -ForegroundColor Gray
} else {
    Write-Host "      ✓ .NET 8 SDK already installed (version $dotnetVersion)" -ForegroundColor Gray
}

# Step 4: Install Node.js
Write-Host "`n[4/10] Checking Node.js..." -ForegroundColor Green
$nodeVersion = node --version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "      Installing Node.js 20 LTS via winget..." -ForegroundColor Gray
    winget install OpenJS.NodeJS.LTS --silent --accept-source-agreements --accept-package-agreements
    
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    
    # Wait for node to be available
    $attempts = 0
    while ($attempts -lt 15) {
        $nodeCheck = node --version 2>&1
        if ($LASTEXITCODE -eq 0) { break }
        Start-Sleep -Seconds 1
        $attempts++
    }
    Write-Host "      ✓ Node.js installed" -ForegroundColor Gray
} else {
    Write-Host "      ✓ Node.js already installed (version $nodeVersion)" -ForegroundColor Gray
}

# Step 5: Clone repository (NEW DEDICATED REPO!)
Write-Host "`n[5/10] Setting up workshop repository..." -ForegroundColor Green
$repoPath = Join-Path $env:USERPROFILE "Recipes-Workshop"

if (Test-Path $repoPath) {
    Write-Host "      Repository already exists at: $repoPath" -ForegroundColor Yellow
    Write-Host "      Pulling latest changes..." -ForegroundColor Gray
    Push-Location $repoPath
    git pull
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[WARNING] Git pull failed. Continuing anyway..." -ForegroundColor Yellow
    }
    Pop-Location
} else {
    Write-Host "      Cloning repository..." -ForegroundColor Gray
    git clone https://github.com/SecureFromScratch/Recipes-Workshop.git $repoPath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to clone repository!" -ForegroundColor Red
        Write-Host "Please check:" -ForegroundColor Yellow
        Write-Host "  - Internet connection" -ForegroundColor Gray
        Write-Host "  - Repository URL is correct" -ForegroundColor Gray
        Write-Host "  - You have access to the repository" -ForegroundColor Gray
        exit 1
    }
}

# Navigate to repository
cd $repoPath
Write-Host "      ✓ Repository ready at: $repoPath" -ForegroundColor Gray

# Step 6: Start LocalStack
Write-Host "`n[6/10] Starting LocalStack..." -ForegroundColor Green
Push-Location src/Recipes.Api
docker compose up -d localstack
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Failed to start LocalStack!" -ForegroundColor Red
    Pop-Location
    exit 1
}
Pop-Location
Write-Host "      ✓ LocalStack started" -ForegroundColor Gray

# Wait for LocalStack
Write-Host "      Waiting for LocalStack to initialize (15 seconds)..." -ForegroundColor Gray
Start-Sleep -Seconds 15

# Step 7: Install AWS CLI
Write-Host "`n[7/10] Checking AWS CLI..." -ForegroundColor Green
$awsVersion = aws --version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "      Installing AWS CLI..." -ForegroundColor Gray
    winget install Amazon.AWSCLI --silent --accept-source-agreements --accept-package-agreements
    
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    
    Write-Host "      ✓ AWS CLI installed" -ForegroundColor Gray
} else {
    Write-Host "      ✓ AWS CLI already installed" -ForegroundColor Gray
}

# Configure AWS CLI
Write-Host "      Configuring AWS CLI for LocalStack..." -ForegroundColor Gray
aws configure set aws_access_key_id localstack
aws configure set aws_secret_access_key localstack
aws configure set default.region us-east-1
Write-Host "      ✓ AWS CLI configured" -ForegroundColor Gray

# Step 8: Create AWS Secrets
Write-Host "`n[8/10] Creating AWS Secrets..." -ForegroundColor Green

aws --endpoint-url=http://localhost:4566 secretsmanager create-secret `
    --name recipes/dev/sa-password `
    --secret-string "StrongP4ssword123" 2>$null | Out-Null

aws --endpoint-url=http://localhost:4566 secretsmanager create-secret `
    --name recipes/dev/app-db-connection `
    --secret-string "Server=localhost,14333;Database=Recipes;User Id=recipes_app;Password=StrongP4ssword123;TrustServerCertificate=true;" 2>$null | Out-Null

aws --endpoint-url=http://localhost:4566 secretsmanager create-secret `
    --name recipes/dev/jwt-config `
    --secret-string '{"Secret":"ThisIsAStrongJwtSecretKey1234567","Issuer":"recipes-api","Audience":"recipes-client"}' 2>$null | Out-Null

Write-Host "      ✓ Secrets created" -ForegroundColor Gray

# Step 9: Install EF Tools
Write-Host "`n[9/10] Installing Entity Framework tools..." -ForegroundColor Green
dotnet tool install --global dotnet-ef 2>$null | Out-Null
Write-Host "      ✓ EF Tools installed" -ForegroundColor Gray

# Step 10: Install packages
Write-Host "`n[10/10] Installing project dependencies..." -ForegroundColor Green

Write-Host "      Installing NuGet packages (2-3 minutes)..." -ForegroundColor Gray
dotnet restore
Write-Host "      ✓ NuGet packages installed" -ForegroundColor Gray

Write-Host "      Installing npm packages (3-5 minutes)..." -ForegroundColor Gray
Push-Location src/recipes-ui
npm install 2>&1 | Out-Null
Pop-Location
Write-Host "      ✓ npm packages installed" -ForegroundColor Gray

# Setup database
Write-Host "`n[BONUS] Setting up database..." -ForegroundColor Green
Push-Location src/Recipes.Api
.\start-db.ps1
Pop-Location

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "   ✓ SETUP COMPLETE!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Workshop repository location:" -ForegroundColor White
Write-Host "  $repoPath`n" -ForegroundColor Gray

Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Open the repository in VS Code:" -ForegroundColor White
Write-Host "     code `"$repoPath`"" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Press F5 to start the API + BFF" -ForegroundColor White
Write-Host ""
Write-Host "  3. In terminal, run:" -ForegroundColor White
Write-Host "     cd src/recipes-ui" -ForegroundColor Gray
Write-Host "     ng serve" -ForegroundColor Gray
Write-Host ""
Write-Host "  4. Open http://localhost:4200 in your browser" -ForegroundColor White
Write-Host ""
