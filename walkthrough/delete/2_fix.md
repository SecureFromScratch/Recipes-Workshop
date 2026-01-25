# Implementing Owner-or-Admin Authorization in ASP.NET Core

## The Problem

You have a DELETE API endpoint and you want to ensure that:

- **Admins** can delete ANY recipe
- **Users** can delete ONLY their own recipes (recipes they created)

### Why Simple Role-Based Authorization Doesn't Work

You might try this:

```csharp
[HttpDelete("{id}")]
[Authorize(Policy = "UserOrAdmin")] // ❌ WRONG!
public async Task<IActionResult> Delete(long id)
{
    await _service.DeleteAsync(id);
    return NoContent();
}
```

**The problem:** This allows ANY authenticated user to delete ANY recipe! The `[Authorize]` attribute runs **before** your method executes, so it can't check if the user owns that specific recipe.

## The Solution: Resource-Based Authorization

ASP.NET Core provides **resource-based authorization** that lets you check authorization **after** you've loaded the resource. This is perfect for ownership checks.

---

## Step-by-Step Implementation

### Step 1: Create the Authorization Requirement and Handler

Create a new file `Authorization/RecipeOwnerOrAdminHandler.cs`:

```csharp
using Microsoft.AspNetCore.Authorization;
using Recipes.Api.Models;

namespace Recipes.Api.Authorization;

// 1. Define the requirement (this is just a marker class)
public class OwnerOrAdminRequirement : IAuthorizationRequirement { }

// 2. Create the handler that contains the authorization logic
public class RecipeOwnerOrAdminHandler : AuthorizationHandler<OwnerOrAdminRequirement, Recipe>
{
    protected override Task HandleRequirementAsync(
        AuthorizationHandlerContext context,
        OwnerOrAdminRequirement requirement,
        Recipe resource)
    {
        // Check if user is an Admin - admins can do anything
        if (context.User.IsInRole("Admin"))
        {
            context.Succeed(requirement);
            return Task.CompletedTask;
        }

        // Check if user owns the resource
        var username = context.User.Identity?.Name;
        if (!string.IsNullOrEmpty(username) && resource.CreatedBy == username)
        {
            context.Succeed(requirement);
        }

        // If neither condition is met, we don't call Succeed()
        // This means the authorization fails
        return Task.CompletedTask;
    }
}
```

**Key Points:**

- `OwnerOrAdminRequirement` is just a marker class that identifies this requirement
- `RecipeOwnerOrAdminHandler` contains the actual logic
- The handler checks TWO conditions: Admin role OR ownership
- Calling `context.Succeed(requirement)` marks the authorization as successful
- If you don't call `Succeed()`, the authorization fails

### Step 2: Register the Handler and Policy

Update your `Extensions/AuthorizationExtensions.cs`:

```csharp
using Microsoft.AspNetCore.Authorization;
using Recipes.Api.Authorization;

namespace Recipes.Api.Extensions;

public static class AuthorizationExtensions
{
    public static IServiceCollection AddAuthorizationPolicies(this IServiceCollection services)
    {
        // ⭐ CRITICAL: Register the handler with dependency injection
        services.AddScoped<IAuthorizationHandler, RecipeOwnerOrAdminHandler>();

        services.AddAuthorization(options =>
        {
            // Define the "OwnerOrAdmin" policy
            options.AddPolicy("OwnerOrAdmin", policy =>
            {
                policy.RequireAuthenticatedUser();
                policy.Requirements.Add(new OwnerOrAdminRequirement());
            });

            // ... your other policies ...
        });

        return services;
    }
}
```

**Critical:** If you forget `services.AddScoped<IAuthorizationHandler, RecipeOwnerOrAdminHandler>();`, the handler will NEVER be called and authorization will always fail!

### Step 3: Use the Policy in Your Controller

Update your `Controllers/RecipesController.cs`:

```csharp
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Recipes.Api.Services;

[ApiController]
[Route("api/recipes")]
[Authorize] // All endpoints require authentication
public class RecipesController : ControllerBase
{
    private readonly IRecipeService m_service;
    private readonly IAuthorizationService m_authorizationService; // Inject this

    public RecipesController(
        IRecipeService service,
        IAuthorizationService authorizationService)
    {
        m_service = service;
        m_authorizationService = authorizationService;
    }

    [HttpDelete("{id:long}")]
    public async Task<IActionResult> Delete(long id)
    {
        // 1. Load the resource first
        var recipe = await m_service.GetByIdAsync(id);
        if (recipe == null)
            return NotFound();

        // 2. Check authorization against the specific resource
        var authResult = await m_authorizationService.AuthorizeAsync(
            User, recipe, "OwnerOrAdmin");

        if (!authResult.Succeeded)
        {
            return Forbid(); // Returns 403 Forbidden
        }

        // 3. Perform the delete operation
        await m_service.DeleteAsync(id);
        return NoContent();
    }
}
```

**Important Flow:**

1. Load the recipe from the database
2. Check if the current user can delete THIS specific recipe
3. Only if authorized, proceed with deletion

---

## How It Works

### Authorization Flow Diagram

```
User sends DELETE /api/recipes/123
    ↓
Controller loads Recipe #123
    ↓
Calls AuthorizeAsync(User, recipe, "OwnerOrAdmin")
    ↓
ASP.NET Core finds the "OwnerOrAdmin" policy
    ↓
Policy has OwnerOrAdminRequirement
    ↓
ASP.NET Core finds RecipeOwnerOrAdminHandler
    ↓
Handler checks:
    - Is User an Admin? → YES → Succeed
    - Is User.Identity.Name == recipe.CreatedBy? → YES → Succeed
    - Neither? → Fail (don't call Succeed)
    ↓
Returns AuthorizationResult (Succeeded = true/false)
    ↓
Controller checks result
    - If failed → return Forbid() (403)
    - If succeeded → delete recipe
```

### What Happens for Different Users

**Scenario 1: Admin deletes any recipe**

```
User: admin (Role: Admin)
Recipe: Created by "john"
Result: ✅ Authorized (Admin role check passes)
```

**Scenario 2: User deletes their own recipe**

```
User: john (Role: User)
Recipe: Created by "john"
Result: ✅ Authorized (CreatedBy matches username)
```

**Scenario 3: User tries to delete someone else's recipe**

```
User: john (Role: User)
Recipe: Created by "mary"
Result: ❌ Forbidden (Neither Admin nor Owner)
```

---

## Complete Code Checklist

### ✅ File 1: `Authorization/RecipeOwnerOrAdminHandler.cs`

```csharp
using Microsoft.AspNetCore.Authorization;
using Recipes.Api.Models;

namespace Recipes.Api.Authorization;

public class OwnerOrAdminRequirement : IAuthorizationRequirement { }

public class RecipeOwnerOrAdminHandler : AuthorizationHandler<OwnerOrAdminRequirement, Recipe>
{
    protected override Task HandleRequirementAsync(
        AuthorizationHandlerContext context,
        OwnerOrAdminRequirement requirement,
        Recipe resource)
    {
        if (context.User.IsInRole("Admin"))
        {
            context.Succeed(requirement);
            return Task.CompletedTask;
        }

        var username = context.User.Identity?.Name;
        if (!string.IsNullOrEmpty(username) && resource.CreatedBy == username)
        {
            context.Succeed(requirement);
        }

        return Task.CompletedTask;
    }
}
```

### ✅ File 2: `Extensions/AuthorizationExtensions.cs`

```csharp
using Microsoft.AspNetCore.Authorization;
using Recipes.Api.Authorization;

namespace Recipes.Api.Extensions;

public static class AuthorizationExtensions
{
    public static IServiceCollection AddAuthorizationPolicies(this IServiceCollection services)
    {
        services.AddScoped<IAuthorizationHandler, RecipeOwnerOrAdminHandler>();

        services.AddAuthorization(options =>
        {
            options.AddPolicy("OwnerOrAdmin", policy =>
            {
                policy.RequireAuthenticatedUser();
                policy.Requirements.Add(new OwnerOrAdminRequirement());
            });
        });

        return services;
    }
}
```

### ✅ File 3: `Controllers/RecipesController.cs` (DELETE endpoint)

```csharp
private readonly IAuthorizationService m_authorizationService;

public RecipesController(
    IRecipeService service,
    IAuthorizationService authorizationService)
{
    m_service = service;
    m_authorizationService = authorizationService;
}

[HttpDelete("{id:long}")]
public async Task<IActionResult> Delete(long id)
{
    var recipe = await m_service.GetByIdAsync(id);
    if (recipe == null)
        return NotFound();

    var authResult = await m_authorizationService.AuthorizeAsync(
        User, recipe, "OwnerOrAdmin");

    if (!authResult.Succeeded)
        return Forbid();

    await m_service.DeleteAsync(id);
    return NoContent();
}
```

### ✅ File 4: `Program.cs` (Make sure this is called)

```csharp
builder.Services.AddAuthorizationPolicies(); // Your extension method
```

---

## Common Mistakes and Troubleshooting

### ❌ Mistake 1: Forgetting to Register the Handler

```csharp
// WRONG - Handler not registered
services.AddAuthorization(options =>
{
    options.AddPolicy("OwnerOrAdmin", policy =>
    {
        policy.Requirements.Add(new OwnerOrAdminRequirement());
    });
});
```

**Symptom:** Authorization always fails, handler is never called

**Fix:** Add `services.AddScoped<IAuthorizationHandler, RecipeOwnerOrAdminHandler>();`

### ❌ Mistake 2: Using [Authorize] Attribute with Resource

```csharp
// WRONG - Can't check ownership before loading resource
[Authorize(Policy = "OwnerOrAdmin")]
public async Task<IActionResult> Delete(long id)
{
    await m_service.DeleteAsync(id);
    return NoContent();
}
```

**Fix:** Use manual `AuthorizeAsync` call after loading the resource

### ❌ Mistake 3: Wrong Username Comparison

```csharp
// WRONG - Using UserId instead of Username
var userId = context.User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
if (userId != null && resource.CreatedBy == userId)
```

**Fix:** Make sure you're comparing the same field. If `CreatedBy` stores username, use `User.Identity.Name`. If it stores user ID, use the user ID claim.

### ❌ Mistake 4: Not Calling context.Succeed()

```csharp
// WRONG - Checking but not marking as succeeded
if (context.User.IsInRole("Admin"))
{
    return Task.CompletedTask; // Missing Succeed call!
}
```

**Fix:** Always call `context.Succeed(requirement)` when authorization should pass

---

## Testing

### Test Cases

1. **Admin deletes any recipe** → Should succeed (200/204)
2. **User deletes their own recipe** → Should succeed (200/204)
3. **User deletes another user's recipe** → Should fail (403 Forbidden)
4. **Unauthenticated user** → Should fail (401 Unauthorized)
5. **Recipe doesn't exist** → Should return 404 before auth check

### Example Test with HTTP Client

```bash
# User "john" deletes their own recipe
DELETE /api/recipes/123
Authorization: Bearer <john's-token>
Response: 204 No Content ✅

# User "mary" tries to delete john's recipe
DELETE /api/recipes/123
Authorization: Bearer <mary's-token>
Response: 403 Forbidden ❌

# Admin deletes any recipe
DELETE /api/recipes/123
Authorization: Bearer <admin-token>
Response: 204 No Content ✅
```

---

## Extending This Pattern

You can use this same pattern for UPDATE operations:

```csharp
[HttpPut("{id:long}")]
public async Task<IActionResult> Update(long id, [FromBody] Recipe recipe)
{
    var existing = await m_service.GetByIdAsync(id);
    if (existing == null)
        return NotFound();

    // Same authorization check
    var authResult = await m_authorizationService.AuthorizeAsync(
        User, existing, "OwnerOrAdmin");

    if (!authResult.Succeeded)
        return Forbid();

    // Proceed with update
    var updated = await m_service.UpdateAsync(id, recipe);
    return Ok(updated);
}
```

---

## Summary

**Resource-based authorization** is the correct way to handle ownership checks in ASP.NET Core because:

1. ✅ You need the actual resource to check ownership
2. ✅ `[Authorize]` attributes run before loading resources
3. ✅ Manual `AuthorizeAsync()` lets you check after loading
4. ✅ Keeps authorization logic separate and reusable
5. ✅ Follows ASP.NET Core best practices

**Key Takeaways:**

- Create a requirement class (marker)
- Create a handler with the authorization logic
- **Register the handler** in DI (don't forget this!)
- Register the policy
- Inject `IAuthorizationService` in your controller
- Call `AuthorizeAsync()` after loading the resource

---

## Additional Resources

- [Microsoft Docs: Resource-based authorization](https://learn.microsoft.com/en-us/aspnet/core/security/authorization/resourcebased)
- [Microsoft Docs: Custom authorization handlers](https://learn.microsoft.com/en-us/aspnet/core/security/authorization/policies)
