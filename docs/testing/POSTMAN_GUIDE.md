# Manual API Testing with Postman

Follow the [backend README](../../backend/README.md) to install dependencies,
configure the application database, and start Uvicorn. Keep the server terminal
running. Postman sends HTTP requests to the backend; it does not need database
credentials or the JWT signing secret.

## Configure requests

1. Set collection variable `base_url` to `http://127.0.0.1:8000` (adjust the port
   if the backend uses another one).
2. Use paths and JSON fields from the [API reference](../API_REFERENCE.md).
3. For registration/login, choose **No Auth** and **Body → raw → JSON**.
4. Register a unique demonstration email, then log in with the same credentials.
   Save the returned token as `access_token`.
5. For protected endpoints, choose **Bearer Token** and enter `{{access_token}}`
   without adding a second Bearer prefix. Use **Body: none** for archive/restore.

Optional login post-response script:

```javascript
if (pm.response.code === 200) {
  pm.collectionVariables.set("access_token", pm.response.json().access_token);
}
```

Clear an old token before attempting login so failed login cannot leave stale
credentials in use. Check that environment variables do not override collection
variables. Never reuse demonstration passwords for real accounts or export real tokens.
A collection file is not required; requests can be created manually.

## Acceptance workflows

| Work packages | Manual sequence |
| --- | --- |
| B01–B03 | Register → login → current user; verify identity and absence of password hash; check duplicate registration, wrong password, invalid input, and missing/expired token |
| B04 | Create → list → detail → PATCH → archive → restore; check ownership, invalid input, duplicate active name, and unchanged retries |
| B05–B06 | List categories → save an ACTIVE category_id → create private definition → save definition_id → list/filter → detail → rename → archive → restore; check name conflicts and foreign access |

Use the API reference for exact status codes and database effects. B05 requires
categories populated through an approved initialization process; it has no write
endpoint. Stock-dependent archival requires inventory APIs or controlled fixtures.
Do not modify other users' accounts or shared data to manufacture test conditions.

Manual requests use the running application's database and do not receive pytest
cleanup. Repeated registration creates more accounts. Record manual outcomes in
the relevant work-package report in this directory, separately from automated runs.

## Connection troubleshooting

Use a client capable of reaching the backend's localhost. If requests cannot
connect, check that the server is running and the host/port match. For database or
500 errors, inspect server logs and database connectivity. A successful `/health`
request proves service reachability, not database connectivity. Do not recreate
application tables as a troubleshooting shortcut.
