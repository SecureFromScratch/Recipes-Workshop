using Recipes.Api.Models;
using Microsoft.AspNetCore.Authorization;

namespace Recipes.Api.Extensions;


public class OwnerOrAdminRequirement : IAuthorizationRequirement { }

// 2. Create a handler for Recipe
public class RecipeOwnerOrAdminHandler : AuthorizationHandler<OwnerOrAdminRequirement, Recipe>
{
    protected override Task HandleRequirementAsync(
        AuthorizationHandlerContext context,
        OwnerOrAdminRequirement requirement,
        Recipe resource)
    {
        // Admin can do anything
        if (context.User.IsInRole("Admin"))
        {
            context.Succeed(requirement);
            return Task.CompletedTask;
        }

        // Owner can manage their own recipe
        var username = context.User.Identity?.Name;
        if (!string.IsNullOrEmpty(username) && resource.CreatedBy == username)
        {
            context.Succeed(requirement);
        }

        return Task.CompletedTask;
    }
}
