## Remediation Guide

### 1. Implement Anti-Forgery Tokens (Recommended)

**Add an AntiForgery Extension**

```csharp
public static class AntiforgeryServiceCollectionExtensions
    {
        public static IServiceCollection AddBffAntiforgery(this IServiceCollection services)
        {
            services.AddAntiforgery(options =>
            {
                options.Cookie.Name = "bff-xsrf";
                options.Cookie.HttpOnly = false; // for dev / JS access
                options.Cookie.SameSite = SameSiteMode.Lax;
                options.Cookie.SecurePolicy = CookieSecurePolicy.SameAsRequest; // dev only
                options.HeaderName = "X-CSRF-TOKEN";
            });

            return services;
        }
    }
```

**Add Token to Responses:**

```csharp
app.MapGet("/api/csrf-token", (IAntiforgery antiforgery, HttpContext context) =>
{
    var tokens = antiforgery.GetAndStoreTokens(context);
    return Results.Ok(new { token = tokens.RequestToken });
}).RequireAuthorization();
```

**Validate Tokens on State-Changing Requests:**

```csharp
app.MapPost("/api/recipes", 
    [ValidateAntiForgeryToken] 
    async (Recipe recipe, IRecipeService service) =>
{
    var created = await service.CreateRecipeAsync(recipe);
    return Results.Created($"/api/recipes/{created.Id}", created);
}).RequireAuthorization();
```

### 2. Fix CORS Configuration

**Replace permissive CORS with strict whitelist:**

```csharp
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.WithOrigins("http://localhost:4200") // Only your frontend
              .AllowAnyMethod()
              .AllowAnyHeader()
              .AllowCredentials();
    });
});
```

### 3. Implement SameSite Cookies

**Update Authentication Cookie Configuration:**

```csharp
builder.Services.ConfigureApplicationCookie(options =>
{
    options.Cookie.SameSite = SameSiteMode.Strict;
    options.Cookie.SecurePolicy = CookieSecurePolicy.Always;
    options.Cookie.HttpOnly = true;
});
```

### 4. Add Custom Request Headers Validation

**Require custom header for API requests:**

```csharp
app.Use(async (context, next) =>
{
    if (context.Request.Method != "GET" && 
        context.Request.Method != "HEAD")
    {
        var customHeader = context.Request.Headers["X-Requested-With"];
        if (customHeader != "XMLHttpRequest")
        {
            context.Response.StatusCode = 403;
            await context.Response.WriteAsync("Missing required header");
            return;
        }
    }
    await next();
});
```

### 5. Implement Double Submit Cookie Pattern

**Alternative to Anti-Forgery Tokens:**

```csharp
// Generate CSRF token
var csrfToken = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));

// Set in cookie
context.Response.Cookies.Append("CSRF-TOKEN", csrfToken, new CookieOptions
{
    HttpOnly = false, // Client needs to read it
    Secure = true,
    SameSite = SameSiteMode.Strict
});

// Validate: Cookie value must match header value
var cookieToken = context.Request.Cookies["CSRF-TOKEN"];
var headerToken = context.Request.Headers["X-CSRF-TOKEN"];

if (cookieToken != headerToken)
{
    context.Response.StatusCode = 403;
    return;
}
```

### 6. Frontend Integration (Angular)

**Step 1: Create CSRF Interceptor**

Create `src/app/interceptors/csrf.interceptor.ts`:

```typescript
import { inject } from '@angular/core';
import { AuthService } from '../services/auth.service';
import { HttpInterceptorFn } from '@angular/common/http';

export const csrfInterceptor: HttpInterceptorFn = (req, next) => {
    const authService = inject(AuthService);
    
    // Only apply to state-changing requests to BFF
    if (!['POST', 'PUT', 'DELETE', 'PATCH'].includes(req.method) || 
        !req.url.includes('/bff')) {
        return next(req);
    }
    
    const token = authService.getRequestToken();
    
    if (!token) {
        console.warn('No CSRF request token available');
        return next(req);
    }
    
    // Clone request and add CSRF token header
    const cloned = req.clone({
        setHeaders: {
            'X-XSRF-TOKEN': token  // Anti-forgery token
        },
        withCredentials: true  // Send cookies
    });
    
    return next(cloned);
};
```

**Step 2: Configure App to Use Interceptor**

Update `src/app/app.config.ts`:

```typescript
import {
  ApplicationConfig,
  provideZoneChangeDetection,
  importProvidersFrom,
  provideAppInitializer,
  inject
} from '@angular/core';
import { provideRouter } from '@angular/router';
import { routes } from './app.routes';
import { 
  HttpClient, 
  provideHttpClient, 
  withInterceptors 
} from '@angular/common/http';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AuthService } from './services/auth.service';
import { csrfInterceptor } from './interceptors/csrf.interceptor';

export const appConfig: ApplicationConfig = {
  providers: [
    provideZoneChangeDetection({ eventCoalescing: true }),
    provideRouter(routes),
    
    // Register HTTP client with CSRF interceptor
    provideHttpClient(
      withInterceptors([csrfInterceptor])
    ),
    
    importProvidersFrom(CommonModule, FormsModule, HttpClient),
    
    // Fetch CSRF token on app initialization
    provideAppInitializer(() => {
      const authService = inject(AuthService);
      return authService.initCsrf();
    })
  ]
};
```

**Step 3: Add CSRF Methods to AuthService**

Update `src/app/services/auth.service.ts`:

```typescript
import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { firstValueFrom } from 'rxjs';

@Injectable({
  providedIn: 'root'
})
export class AuthService {
  private csrfToken: string | null = null;
  private readonly bffUrl = 'http://localhost:4200/bff';

  constructor(private http: HttpClient) {}

  /**
   * Fetch CSRF token from BFF on app initialization
   */
  async initCsrf(): Promise<void> {
    try {
      const response = await firstValueFrom(
        this.http.get<{ token: string }>(`${this.bffUrl}/csrf-token`, {
          withCredentials: true
        })
      );
      this.csrfToken = response.token;
      console.log('CSRF token initialized');
    } catch (error) {
      console.error('Failed to initialize CSRF token:', error);
    }
  }

  /**
   * Get the current CSRF token for requests
   */
  getRequestToken(): string | null {
    return this.csrfToken;
  }

  /**
   * Refresh CSRF token (call after login/logout)
   */
  async refreshCsrfToken(): Promise<void> {
    await this.initCsrf();
  }
}
```

**Step 4: Using HttpClient in Components**

Now all HTTP requests automatically include CSRF tokens:

```typescript
export const appConfig: ApplicationConfig = {
  providers: [
    provideZoneChangeDetection({ eventCoalescing: true }),
    provideRouter(routes),
    provideHttpClient(
      withInterceptors([credentialsInterceptor, csrfInterceptor])      
    ),

    ...
  ]
};
```

**How It Works:**

1. **App Initialization**: `initCsrf()` fetches token from `/bff/csrf-token`
2. **Token Storage**: Token stored in `AuthService.csrfToken`
3. **Automatic Injection**: Interceptor adds `X-XSRF-TOKEN` header to all POST/PUT/DELETE/PATCH requests
4. **BFF Validation**: Server validates token on each state-changing request
5. **Attack Blocked**: Attacker's requests fail because they don't have the token

**Important Notes:**

- ✅ Always use `withCredentials: true` to send authentication cookies
- ✅ Refresh token after login/logout: `authService.refreshCsrfToken()`
- ✅ Token is fetched once on app load and reused
- ✅ Interceptor only applies to BFF endpoints (not external APIs)

---


## Testing Your Fixes

After implementing remediations:

1. **Re-run the attack PoC**
   - It should fail with 403 Forbidden or 400 Bad Request

2. **Verify legitimate requests still work**
   - Frontend should include CSRF tokens
   - Authorized users can create recipes normally

---

