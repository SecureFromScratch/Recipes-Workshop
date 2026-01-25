using Microsoft.AspNetCore.Antiforgery;

namespace Recipes.Bff.Middleware
{
    public class AntiforgeryMiddleware
    {
        private readonly RequestDelegate _next;
        private readonly IAntiforgery _antiforgery;

        public AntiforgeryMiddleware(RequestDelegate next, IAntiforgery antiforgery)
        {
            _next = next;
            _antiforgery = antiforgery;
        }

        public async Task InvokeAsync(HttpContext context)
        {
            var method = context.Request.Method;
            var path = context.Request.Path.Value ?? "";

            // Validate CSRF on POST/PUT/DELETE/PATCH to /api or /bff
            bool needsValidation = 
                (method == "POST" || method == "PUT" || method == "DELETE" || method == "PATCH") &&
                (path.StartsWith("/api") || path.StartsWith("/bff"));

            if (needsValidation)
            {
                try
                {
                    await _antiforgery.ValidateRequestAsync(context);
                }
                catch (AntiforgeryValidationException)
                {
                    context.Response.StatusCode = 403;
                    await context.Response.WriteAsJsonAsync(new { error = "CSRF validation failed" });
                    return;
                }
            }

            await _next(context);
        }
    }
}