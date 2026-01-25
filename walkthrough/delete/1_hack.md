## Delete Exploitation

### Vulnerability Analysis

The application does not enforce ownership checks when deleting recipes.
As a result, any authenticated user can delete recipes created by other users.

Root causes:

- Missing authorization check (owner or role-based)
- Trust in client-supplied identifiers
- Prior mass assignment allows crafting an approved recipe

### Execute the Attack

1. **Create an approved recipe**
   - Log in as User A.
   - Exploit the mass assignment vulnerability to set `isApproved=true` during recipe creation.
   - Note the recipe ID.

2. **Delete as another user**
   - Log out and log in as User B.
   - Send a delete request for the recipe ID created by User A.
   - The deletion succeeds despite lack of ownership.
