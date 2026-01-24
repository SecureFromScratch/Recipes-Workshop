## If migration failure try again

cd /workspaces/Recipes-Workshop/src/Recipes.Api

### Get SA password
SA_PASS=$(aws --endpoint-url=http://localhost:4566 secretsmanager get-secret-value \
  --secret-id recipes/dev/sa-password \
  --query SecretString \
  --output text)

echo "SA Password: $SA_PASS"

### Reset database
docker compose down sqlserver -v
export MSSQL_SA_PASSWORD="$SA_PASS"
docker compose up -d sqlserver
sleep 20

### Initialize database
docker exec -i recipes-sqlserver /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "$SA_PASS" -C \
  -i /init/init-db.sql

### Create and apply migrations
cd /workspaces/Recipes-Workshop/src/Recipes.Api
rm -rf Migrations
dotnet ef migrations add InitialCreate
dotnet ef database update --connection "Server=localhost,14333;Database=Recipes;User Id=sa;Password=$SA_PASS;TrustServerCertificate=true;"

### Verify
docker exec recipes-sqlserver /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "$SA_PASS" -d Recipes -C \
  -Q "SELECT name FROM sys.tables ORDER BY name"

echo "✅ Database ready!"
```

---

## 🎯 **THEN TEST THE APP:**

### **1. Reload VS Code Window:**
```
Ctrl+Shift+P → "Reload Window"
```

### **2. Start Backend:**
```
Press F5
Select: "API + BFF"
