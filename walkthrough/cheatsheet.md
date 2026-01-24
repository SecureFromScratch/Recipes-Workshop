## Usefull & easy to run

### Sql terminal
```bash
docker exec -it recipes-sqlserver /opt/mssql-tools18/bin/sqlcmd   -S localhost   -U sa   -P StrongP4ssword123 -C
    
```
## SQL commands
```SQL
USE Recipes;
GO
SELECT * FROM Users;
GO
```
### Add openapi api secret
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
  --name recipes/dev/openai \
  --secret-string "sk-proj-..."

### Get the secret value
aws --endpoint-url=http://localhost:4566 secretsmanager get-secret-value \
  --secret-id recipes/dev/openai


 ### Install sqlcmd on your linux host machine
curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
curl https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list
sudo apt-get update
sudo apt-get install -y mssql-tools18 unixodbc-dev

### Creating QR Code
import qrcode

payload = "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"  
img = qrcode.make(payload)
img.save("test/qr/class-qr.png")
