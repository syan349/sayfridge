# Product Scope and User Needs

SayFridge helps individuals manage food and household supplies across their
fridge, freezer, pantry and other storage spaces. It makes purchases, remaining
quantities and expiry dates visible so users can avoid forgotten stock and
repeated purchases. Each account owns its inventory; spaces are flat and private.

## Clients and roles

| Client | User need | Implemented experience |
| --- | --- | --- |
| Flutter Android | Record stock while shopping or cooking | Camera/gallery input, editable speech transcription, text assistant, inventory maintenance, local reminders and daily check-in |
| Flutter Web | Access the Mobile interface in a browser | Shared Flutter UI and API workflows; browser permissions and notification lifecycle apply |
| React Web | Review and maintain larger inventories | Search, filters, batch stock entry/movement/archival, quantities, history and expiry views |
| React administrator pages | Manage accounts | Restricted account listing, detail and permitted status changes |

Mobile and Web share accounts and inventory, while their interfaces serve these
different contexts. Flutter Web provides an additional browser entry point;
the Android APK is the native delivery artifact.

## Core user stories and evidence

| User story | Delivered behavior | Verification entry |
| --- | --- | --- |
| As a user, I want to register and return to my account | Registration/login, automatic access renewal and session logout | [Authentication and browser E2E](../testing/README.md#core-e2e) |
| I want to organize stock by storage location | Create/rename/archive/restore spaces and choose a default | [Space report](../testing/reports/B04_STORAGE_SPACES_TEST_RESULTS.md), E2E |
| I want to record purchases and see them later | Private definitions, stock batches, quantities, dates, categories and notes | [Inventory report](../testing/reports/B07-B09_INVENTORY_TEST_RESULTS.md), E2E |
| I want to correct details or location | Metadata editing and movement with version checks | E2E persistence after reload and inventory tests |
| I want to record use and actual remaining stock | ADD, CONSUME and RECONCILE; exact/estimated balances and quantity history | [Quantity reports](../testing/README.md#reports), E2E |
| I want to find expired or upcoming stock | On-demand expiry summary using a supplied local date | [Expiry report](../testing/reports/B22_EXPIRY_SUMMARY_TEST_RESULTS.md), E2E |
| I want to enter stock by photo, speech or text | Speech becomes editable client-side text; the model interprets text/images; photo stock requires review | [Agent reports](../testing/README.md#reports); native device checks accompany Android acceptance |
| I want to remove stock from active views | Discard or archive while retaining the stored record | [State report](../testing/reports/B13_INVENTORY_STATE_TEST_RESULTS.md), E2E archival |
| I want my data separated from other accounts | Ownership enforcement on resources and Agent conversations | E2E cross-user checks and [security evidence](../security/README.md) |
| As an administrator, I want to manage account status | Role-restricted account queries and state updates | [Administrator report](../testing/reports/B25_ADMIN_USERS_TEST_RESULTS.md) |

Reports identify the run and scope they verified. The testing guide owns current
execution instructions; the final deployed acceptance record identifies the
release tested by the team.

## Current product behavior

The assistant supports queries, new stock, additions, consumption, reconciliation,
clarification and explicit user memory. Complete text actions can execute directly;
image stock, category-review cases and user-requested approval wait for confirmation.
Ambiguous targets or missing required facts require clarification. Approximate
quantities remain visibly estimated until a physical reconciliation.

Missing stock expiry dates use the configured estimation service before the write;
explicit dates and shelf-life inputs take priority. Estimation failure returns a
warning alongside the successful stock entry.

Mobile reminder settings and profile preferences are stored per user on the device.
Native reminders are local notifications. Web notifications depend on browser
permission and the open application; there is no server push service. Daily Check-in
passes the user's edited text/images to the assistant with a request to confirm deductions.

React conversation history displays labeled sample data. The recovery API restores
pending business progress; it does not list all previous chats or return full image history.
Email/password changes, account deletion and a server voice-quota API are not supplied.

## Scope boundaries

Inventory sharing, nested spaces, supermarket ordering/payment, IoT hardware,
server notification queues, automatic historical estimate recalculation and
administrator task/audit dashboards are outside the delivered scope. Stock removal
uses archive/discard rather than hard deletion. Firebase, Firestore and Firebase
Cloud Messaging are not project dependencies.

Detailed behavior is owned by the [API reference](../reference/API_REFERENCE.md),
[architecture](../architecture/README.md), [security guide](../security/README.md)
and [delivery guide](../delivery/README.md). The repository [README](../../README.md)
is the project entry point.
