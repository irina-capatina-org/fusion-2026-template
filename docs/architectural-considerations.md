# Architectural considerations

Org-level platform facts and design preferences for this automation program. The SDD
and DSD agents read this file and treat it as authoritative, so it removes the guessing
that otherwise shows up as `[ARCHITECT REVIEW]` on every generated document.


## How the agents must use this file

Read this before the Constraint Gate, and apply it as follows.

| Marker | Meaning | What the agent does |
|---|---|---|
| a plain value | a **confirmed fact** about the org | state it as fact. Do NOT raise an `[ARCHITECT REVIEW]` for it. Record the source as "org architectural considerations" in *Recommended Scope*. |
| `[UNCONFIRMED]` | nobody has confirmed this yet | treat exactly as if this file did not mention it: apply the normal default and carry the `[ARCHITECT REVIEW]` item. |
| a **preference** (§3–§4, §8) | a house default, not a law | apply it, and record in *Decisions Made* that it came from this file. If the PDD's actual need contradicts it, follow the PDD and note the deviation with its reason. A preference must never force a design the process cannot use. |

Two rules that matter more than the rest:

1. **Never invent a value that is not here.** An absent row is an `[ARCHITECT REVIEW]`, not an
   opportunity to assume.
2. **A preference is not a constraint.** Only §2 licensing can *block* a product. §3–§4
   shape a design; they never veto one.

---

## 1. Delivery model

| Field | Value |
|---|---|
| Deployment type | Automation Cloud |
| Region / data residency | EU |
| Tenant version | latest |
| Orchestrator folder structure | modern folders |
| Cloud variant | standard |

Deploy-time identifiers are not repeated here — they live in the repo/org GitHub
variables `UIPATH_ORGANIZATION`, `UIPATH_TENANT`, `UIPATH_AUTHORITY`,
`UIPATH_FOLDER_PATH` and are read by `uipath-deploy`.

---

## 2. Licensed products

This is the only section that can **block** a product. An unlicensed product is
unavailable: recommend the documented alternative instead and record the block in
*Recommended Scope → Blocked by platform*.

| Product | Licensed | Notes |
|---|---|---|
| RPA (attended / unattended robots) | available, but limited | see §5 for runtime counts |
| API Workflows | fully available | |
| Maestro — Flow | fully available | |
| Maestro — BPMN | not available | |
| Maestro — Case Management | partially available  | |
| Agents / Agent Builder | fully available | |
| IXP / Document Understanding | not available  | |
| Coded Apps | fully available | |
| Integration Service | fully available | gates §4's connector-first preference |
| Action Center (HITL) | partially available  | |
| Data Fabric | partially available  | |
| Test Manager | partially available | |

> `not available` is a hard block. `partially available` / `available, but limited`
> means the product may be used but the design must justify it and say what the limit
> is — prefer an alternative where one exists. `fully available` is unconstrained.

---

## 2.5 The shape every delivery takes

A UiPath **Solution** containing exactly **one API Workflow project**.

This is a decision, not an outcome to be re-derived per request. The use cases in this
programme are deliberately simple, and a design that quietly splits into two or three
projects produces a shape nobody rehearsed and a deployment nobody tested.

| Term | What it means here |
|---|---|
| `sdd_scope: single-product` | ONE project, inside the solution. **Never** "no solution". |
| `sdd_scope: solution` | two or more independently deployed projects. Not used here. |
| the delivery | always a solution: `uip solution pack` -> `publish` -> `deploy run` |

Reading `single-product` as "no solution wrapper" is what made a deploy step look for
`.nupkg` files that a solution build never produces, and then skip the deploy entirely
while the run stayed green. If a process genuinely needs a second project, that is an
`[ARCHITECT REVIEW]` item - not a decision to take mid-run.

## 3. Preferred project types, and when

House defaults for product selection. They narrow the choice; they do not override the
process need.

| Situation | Preferred | Why |
|---|---|---|
| A stable REST/OData API exists for every system involved, no UI, no bot | **API Workflow** | no robot licence consumed, no UI fragility, fastest to run and to test |
| Any step needs a UI, or machine-local work (Excel, files, on-prem DB, desktop email, terminal) | **RPA Process** | nothing else can drive a UI |
| Per-item transactional volume above ~200 items per run with a distinct selection step | **RPA Master Project** (Dispatcher + Performer + queue) | retry and throughput are queue properties |
| A staged lifecycle with SLAs or approvals | **Case Management** | |
| Two or more independently deployed peers that must be coordinated at runtime | **Maestro Flow** | |
| Genuine judgment not expressible as fixed rules | **Agent**, as a component of a deterministic host | cost and auditability |
| A fixed generative step inside a known path | an **LLM activity** in the host, not an Agent | |
| Headless deterministic compute, no UI, no orchestration | **API Workflow**  first, **Coded Function** if **API Workflow** not possible| leaner than an RPA process |

Standing rules:

- **Hybrid is the normal answer.** A deterministic primary with an Agent only for the
  steps that need judgment. A fixed process containing judgment steps is never an
  Agent-primary design.
- **API-first.** Where a system offers both an API and a UI, use the API.
- **Every automation is a Solution**, even if it only has a single project.
- **The artifacts must match the product.** An API Workflow is `Workflow.json` +
  `uipath.json` + `entry-points.json` — it has no `.xaml` and no `project.json`. RPA is
  `project.json` + `.xaml`. A design that names the wrong product's files is wrong even
  if the heading is right.

---

## 4. Connection and credential patterns

### API calls: one pattern, always

**Every call to an external system is an HTTP Request activity authenticated by that
system's Integration Service connection.** You write the method, the URL and the
payload; the connection supplies the credentials. There is no second approved shape.

This is not the HTTP connector calling itself and it is not a curated vendor activity.
It is the **HTTP connector's `http-request` activity with `authentication: "connector"`**,
pointed at the target connector and connection. A working example of both a Coupa call
and a Slack call built this way lives in `automation-docs/Solution/API Workflow/` in the
programme repository; the shape below is copied from it verbatim and validates clean.

| Need | Pattern |
|---|---|
| Any REST call to a system in the connections table below | HTTP Request activity, `authentication: "connector"`, targeting that connection |
| A REST call to a system with **no** connection below | there isn't one. Say so and stop. |
| Any username / password / token / client secret | **Orchestrator credential asset**, never a plain asset, never inline |

#### The activity, verbatim

Everything here is fixed except the five marked lines. Copy it, change those, done.

```json
{
  "HTTP_Request_1": {
    "call": "UiPath.Http",
    "with": {
      "connector": "uipath-uipath-http",
      "connectionId": "5fadfc73-a372-46ae-a27c-2481741eed07",
      "connectionResourceId": "5fadfc73-a372-46ae-a27c-2481741eed07",
      "method": "POST",
      "endpoint": "/http-request",
      "bodyParameters": {
        "authentication": "connector",
        "targetConnector": "uipath-coupa-coupa",
        "connection": "5fadfc73-a372-46ae-a27c-2481741eed07",
        "method": "GET",
        "path": "invoices",
        "url": "invoices",
        "query": {
          "status[in]": "draft,new",
          "invoice-date[gt_or_eq]": "${$context.variables.windowStart}",
          "invoice-date[lt_or_eq]": "${$context.variables.windowEnd}",
          "order_by": "invoice-date",
          "dir": "desc",
          "limit": "50"
        }
      }
    },
    "export": {
      "as": "{ ...$context, outputs: { ...$context?.outputs, \"HTTP_Request_1\": $output } }"
    },
    "metadata": {
      "activityType": "Connector",
      "displayName": "HTTP Request: Coupa",
      "uiPathActivityTypeId": "5c4cc855-b42a-37e6-b910-de8588998fce",
      "configuration": "{\"essentialConfiguration\":{\"connectorVersion\":\"1.4.44\",\"scriptRef\":null,\"customFieldsRequestDetails\":null,\"instanceParameters\":{\"connectorKey\":\"uipath-uipath-http\",\"objectName\":\"http-request\",\"httpMethod\":\"POST\",\"activityType\":\"Curated\",\"version\":\"1.0.0\",\"supportsStreaming\":false,\"subType\":\"method\"},\"objectName\":\"http-request\",\"operation\":\"create\",\"packageVersion\":\"1.0.0\",\"httpMethod\":\"POST\",\"path\":\"/http-request\",\"unifiedTypesCompatible\":true,\"savedJitInputFieldId\":\"in_http-request\"}}"
    }
  }
}
```

The Slack call is the same activity with four lines different — target connector,
connection, verb and path — and the payload in `body`.

> **`body` below is deliberately shortened so the activity shape stays readable. It is
> NOT the payload you ship.** The real value of `bodyParameters.body` is the full Block
> Kit payload in *"The Slack message is Block Kit, and it goes in `body`"* further down
> this section — read that before you write this activity. A build that copies the
> one-line `text:` form below and stops produces the unformatted wall-of-prose message
> the Block Kit subsection exists to prevent. That has now happened on a real run.

```json
{
  "HTTP_Request_2": {
    "call": "UiPath.Http",
    "with": {
      "connector": "uipath-uipath-http",
      "connectionId": "43d506f7-7de2-4798-aac1-9522e2e45dbb",
      "connectionResourceId": "43d506f7-7de2-4798-aac1-9522e2e45dbb",
      "method": "POST",
      "endpoint": "/http-request",
      "bodyParameters": {
        "authentication": "connector",
        "targetConnector": "uipath-salesforce-slack",
        "connection": "43d506f7-7de2-4798-aac1-9522e2e45dbb",
        "method": "POST",
        "path": "chat.postMessage",
        "url": "chat.postMessage",
        "body": "${{ channel: 'WLX9BD8FN', text: `...`, blocks: [ ... ] }}"
      }
    },
    "export": {
      "as": "{ ...$context, outputs: { ...$context?.outputs, \"HTTP_Request_2\": $output } }"
    },
    "metadata": {
      "activityType": "Connector",
      "displayName": "HTTP Request: Slack",
      "uiPathActivityTypeId": "5c4cc855-b42a-37e6-b910-de8588998fce",
      "configuration": "{\"essentialConfiguration\":{\"connectorVersion\":\"1.4.44\",\"scriptRef\":null,\"customFieldsRequestDetails\":null,\"instanceParameters\":{\"connectorKey\":\"uipath-uipath-http\",\"objectName\":\"http-request\",\"httpMethod\":\"POST\",\"activityType\":\"Curated\",\"version\":\"1.0.0\",\"supportsStreaming\":false,\"subType\":\"method\"},\"objectName\":\"http-request\",\"operation\":\"create\",\"packageVersion\":\"1.0.0\",\"httpMethod\":\"POST\",\"path\":\"/http-request\",\"unifiedTypesCompatible\":true,\"savedJitInputFieldId\":\"in_http-request\"}}"
    }
  }
}
```

Note the two `method` fields are independent: `with.method` is always `POST` because that
is how you invoke the HTTP connector, while `bodyParameters.method` is the verb of the
call you are actually making — `GET` for Coupa, `POST` for Slack.

| Line | Fixed or yours |
|---|---|
| `call`, `connector`, `method: "POST"`, `endpoint: "/http-request"` | **fixed** — this is the HTTP connector's own operation, never the target's |
| `uiPathActivityTypeId`, `metadata.configuration` | **fixed** — byte for byte, for every HTTP Request activity |
| `HTTP_Request_1` and its export key | yours — unique per activity. The export key is the activity key **character for character, same case**. Never lowercase it. |
| `connectionId` / `connectionResourceId` / `bodyParameters.connection` | yours — the **same** connection id in all three, from the table below |
| `bodyParameters.targetConnector` | yours — the connector key of the system being called |
| `bodyParameters.method` + `path` + `url` | yours — the real verb, and the resource path **relative to the connector's base URL**. Not an absolute URL. |

`bodyParameters` accepts: `authentication`, `targetConnector`, `connection`, `method`,
`path` and `url` (all required), plus `headers`, `query` and `body` (optional). They
are flat keys taking **bare literals** — `"url": "invoices"`, never `"${'invoices'}"`,
which clears the field when Studio Web saves. A real reference stays wrapped:
`"body": "${$context.variables.payload}"`.

#### The URL is RELATIVE, and `path` and `url` must both carry it

This is the single most expensive mistake in this file's history. `targetConnector`
already identifies the system, and the Integration Service connection already knows its
base URL — so the activity supplies only the resource path after it, in **both** `path`
and `url`, with the same value and no leading slash:

| Call | `path` and `url` | NOT |
|---|---|---|
| Coupa list invoices | `invoices` | `https://uipath-test.coupahost.com/api/invoices` |
| Slack post message | `chat.postMessage` | `https://slack.com/api/chat.postMessage` |

Write an absolute URL and the request URL arrives **empty** in Studio Web - the field
looks unfilled, the workflow validates and packs clean, and it fails at run time. A
built solution had to be opened and fixed by hand for exactly this.

#### Slack `chat.postMessage` needs a member ID, not an email

The `channel` field takes a Slack **member ID** or **channel ID**. An email address is
rejected by the Slack API even though it looks right in the document and in the PDD.

| Recipient | `channel` value |
|---|---|
| Irina Capatina (irina.capatina@uipath.com) | `WLX9BD8FN` |

If a design names a Slack recipient by email and no member ID is recorded here, that is
an `[ARCHITECT REVIEW]` item - do not pass the email through as `channel`, and do not
invent an ID.

#### The Slack message is Block Kit, and it goes in `body`

`chat.postMessage` renders `blocks` and uses the top-level `text` only as the
notification preview and screen-reader fallback. Send plain `text` alone and you get
a wall of prose with a raw URL in it; send `blocks` and you get a title, icon-led
lines and a real button.

`bodyParameters.body` is a UiPath expression, NOT a JSON document. Its delimiters are
`${` and `}`, and the thing you write between them is a JavaScript object literal, so
the value always reads `${{ ... }}`: the OUTER brace of that pair belongs to `${ }` and
the INNER one opens the object. **You write the object's key/value pairs directly. You
do NOT add another `{ }` around them.**

```
correct    "body": "${{ channel: 'WLX9BD8FN', text: `...`, blocks: [ ... ] }}"
WRONG      "body": "${{ { channel: 'WLX9BD8FN', text: `...`, blocks: [ ... ] } }}"
```

That second form is a real failure from a real run, not a hypothetical. Pasting a JSON
payload in whole adds its outer braces on top of the ones `${{` already supplies, the
Studio Web expression editor reports `SyntaxError: Unexpected token '{'`, and the
activity fails at run time after a clean build and a clean deployment.

It is an expression, so it is JavaScript and not JSON: keys are unquoted, strings use
single quotes or backticks (never `"`, which would have to be escaped inside the JSON
file), and a value is interpolated with `${$context.variables.<name>}` inside a
backtick string or written bare outside one.

This is the whole `body` value, copy it and change only the variable names:

```
${{ channel: 'WLX9BD8FN', text: `:receipt: ${$context.variables.qualifyingCount} invoices from the last seven days have no purchase order linked`, blocks: [ { type: 'header', text: { type: 'plain_text', text: `:receipt: ${$context.variables.qualifyingCount} invoices need a purchase order`, emoji: true } }, { type: 'section', text: { type: 'mrkdwn', text: `:warning:  *${$context.variables.qualifyingCount} invoices* from the last seven days have no purchase order linked.\n:no_entry:  An invoice without a linked PO cannot be matched or paid under our *no-PO-no-pay policy*, and payment to the supplier stalls until it is fixed.\n:point_right:  Please make sure a purchase order exists for these invoices and is correctly linked to each one.` } }, { type: 'actions', elements: [ { type: 'button', text: { type: 'plain_text', text: 'Open the list in Coupa', emoji: true }, url: $context.variables.coupaUrl, style: 'primary' } ] }, { type: 'divider' }, { type: 'context', elements: [ { type: 'mrkdwn', text: `:calendar: Invoices dated *${$context.variables.windowStart}* to *${$context.variables.windowEnd}*  ·  :robot_face: No-PO Invoice Chaser  ·  checked *${$context.variables.runDate}*` } ] } ] }}
```

The braces INSIDE the payload - around each block, around each nested `text` - are
ordinary object literals and are all required. Only the outermost pair is the one that
must not be doubled.

Five things about this that are not obvious and cost a rebuild each if you get them
wrong:

| Rule | Why |
|---|---|
| `${{ ... }}` already opens the object - never add another `{ }` | The outer brace is the `${ }` expression delimiter, the inner one is the object literal. A pasted JSON payload brings its own pair and you get `${{ { ... } }}`, which is `SyntaxError: Unexpected token '{'` at run time, after the build and the deploy have both gone green. |
| The three body lines are ONE `section` separated by `\n` | One section per line looked right in the JSON and rendered with a large gap between every line. Slack puts a margin between blocks, not between lines. |
| Top-level `text` is required | With `blocks` present it is the push-notification text. Omit it and the notification reads "This content can't be displayed". |
| `url` on a button must be a real absolute URL | Block Kit validates it. A templated value that has not been substituted is rejected outright, so the failure is at send time, not at build time. |
| `header` is `plain_text` only | No `mrkdwn`, no bold. Emoji work through `:name:` with `"emoji": true`. |
| `channel` is the member ID | See the member-ID note above. An email is rejected by Slack. |

**Write the payload inline in `body`. Do NOT compose it in a script step.** An earlier
version of this section said the opposite - "compose the whole JSON string into a
variable and reference it once" - and a build followed it: it added a
`Javascript_ComposeSlackPayload` script and an `Assign_SlackPayload`, then put a bare
variable reference in `body`. The payload was correct, but `validate-build.sh` reads
`body` and found no `blocks` there, failed the build, and a repair agent spent 197
seconds putting the payload back where this section wanted it. Inline is the only
approved shape, for three reasons:

- `validate-build.sh` checks `bodyParameters.body`. A payload assembled somewhere else
  is invisible to it, so the one gate that protects this message cannot see it.
- Two extra activities exist only to move a string, and each is a place for the
  case-sensitivity bug below to bite.
- What you read in the activity is what Slack receives. Nothing to trace through.

Interpolate the workflow's values with `${$context.variables.<name>}` directly inside
the payload, exactly as the example above does. The count appears twice on purpose -
the title is what shows in the Slack sidebar unopened.

#### Activity names are CASE SENSITIVE, everywhere they appear

An API Workflow resolves `$context.outputs.<Name>` as an exact string. Three places
must agree character for character, including case:

1. the activity's key in the `do` tree — `HTTP_Request_Slack`
2. the string inside its `export.as` — `"HTTP_Request_Slack": $output`
3. every later reference — `$context.outputs.HTTP_Request_Slack`

`http_request_slack` is a different, non-existent output. It does not error at build or
validate time: the script step simply reads `undefined` and the workflow fails at run
time on a confusing message. A built solution needed this fixed by hand.

Pick one spelling per activity and reuse it by copy-paste. Never re-type an activity
name, and never "normalise" the case of one.

**Reading the response.** The activity outputs
`{ statusCode, statusText, headers, ok, request, content, vendorProcessingTimeMs }`.
The payload is in **`.content`** — not `.body` — and the status is **`.statusCode`**,
not `.code`. For a Coupa list, `.content` is a plain array:

```
$context.outputs.http_request_1.content          // the array of invoices
$context.outputs.http_request_1.content.length   // how many came back
$context.outputs.http_request_1.statusCode       // 200
```

**Coupa query syntax, verified against the live tenant on 2026-09-21.** `status[in]`
takes a comma-separated list; `status[in][]` with the second pair of brackets returns
**HTTP 400**. Date bounds are `invoice-date[gt_or_eq]` / `[lt_or_eq]` as `YYYY-MM-DD`.
`order_by` + `dir` sort, and `limit` caps the page.

#### Two files have to agree with it

An activity alone is not enough — the connection has to be declared to the solution as
well, or Studio Web shows the activity with a broken connection and deploy cannot bind
it. Both files are in the reference solution.

1. `<project>/bindings_v2.json` — one entry per activity:

```json
{ "resource": "Connection", "key": "<connection id>",
  "activityId": "HTTP_Request_1", "activityDisplayName": "HTTP Request: Coupa",
  "value": { "ConnectionId": { "defaultValue": "<connection id>", "isExpression": false } },
  "metadata": { "UseConnectionService": "true", "Connector": "uipath-coupa-coupa",
                "ActivityName": "HTTP Request: Coupa", "BindingsVersion": "2.2",
                "SolutionsSupport": "true" } }
```

2. `Solution/resources/solution_folder/connection/<connector-key>/<connection-name>.json`
   — one file per connection, `kind: "connection"`, `type: <connector key>`,
   `key: <connection id>`, `spec.authenticationType: "AuthenticateAfterDeployment"`,
   `folders: [{ "fullyQualifiedName": "solution_folder" }]`. Copy the reference file and
   change the name, type, key and `spec.connectorName` / `connectorVersion`.

#### What not to do

**Do not use a curated vendor activity** (`ListInvoices`, `SendMessage`, `GetAsset`, and
the rest). The build runner has no UiPath credentials, so it cannot run
`uip api-workflow registry resolve` / `stub`, and any `uiPathActivityTypeId` or
`metadata.configuration` not produced by `stub` is a guess. JACTIV-665 shipped
`CoupaListInvoices_1` against connector key `uipath-coupa` with a `<TODO: run 'uip
api-workflow registry resolve …'>` left in the activity id: no such activity, and the
real connector key is `uipath-coupa-coupa`. The shape above needs no registry call,
because every part of it that is not the request itself is a constant.

**Do not use `connectionId: "ImplicitConnection"`.** That is the anonymous HTTP Request,
with no credentials — it only suits a public endpoint, and every system this programme
talks to needs authentication.

**Never ship a `<TODO: …>` or `<REPLACE_WITH_…>` placeholder** in a connection id or an
activity id. Studio Web renders it as a broken connection. If a value is not in this
file, stop and say so — do not leave a marker for someone to find later.

### Existing connections to enterprise systems — reusable across automations

These connections **already exist** in the `Fusion2026` folder. They are program
infrastructure shared by every automation, not per-automation resources: reference them
by name and id, and never create, rename, duplicate or re-provision one.

These two are the connections the demo use case runs on, and the ones wired into the
reference solution — use these ids, not new ones. The base URLs are in §6; the two calls
the demo makes are `GET https://uipath-test.coupahost.com/api/invoices` and
`POST https://slack.com/api/chat.postMessage`.

| Connection name | System | Connector key | Connection id | State 2026-09-20 |
|---|---|---|---|---|
| `coupa-uipath-test` | Coupa — invoice and PO data | `uipath-coupa-coupa` | `5fadfc73-a372-46ae-a27c-2481741eed07` | **Failed — 403 Forbidden** |
| `slack-product-test-app` | Slack — notification to AP | `uipath-salesforce-slack` | `43d506f7-7de2-4798-aac1-9522e2e45dbb` | Enabled |
| `jira-irina-capatina` | Jira | `uipath-atlassian-jira` | `b023ef92-1ae8-4cc3-bf56-fb67eff2bd8f` | Enabled |
| `gh_irina-capatina-org` | GitHub | `uipath-microsoft-github` | `e4ae6c82-9243-4691-972d-77fc0c950104` | Enabled |
| `uipath-orchestrator` | UiPath Orchestrator | `uipath-uipath-orchestrator` | `d35479dd-4a08-4e0d-bd35-4f733c3ca24a` | Enabled |

> **Coupa, 2026-09-21 — `coupa-uipath-test` works. Ignore its ping.**
> `uip is connections ping` reports it Failed with a 403, but a real call through it
> returns **HTTP 200** with full invoice data. Verified by running the activity above
> against the live tenant: newest invoices are dated 2026-09-20 with status `draft`,
> supplier names resolve, and `invoice-lines[]` carries `po-number` / `order-header-num`
> / `description`. Ping state is not runtime state — do not re-provision this connection
> on the strength of a failed ping.
>
> **Scope: `invoices` read is sufficient.** Everything the business rules need comes back
> in that one call — `status`, `invoice-date`, `invoice-number`, `gross-total`, nested
> `currency.code`, nested `supplier.name`, `is-credit-note`, `created-by.fullname`, and
> the PO fields on the lines. No supplier, user or purchase-order scope is needed, and no
> write scope at any point.

A row here is a **confirmed fact**. The SDD records the connection as an existing
prerequisite — not as something a human must go and create — and raises no
`[ARCHITECT REVIEW]` for it. A system that is *not* in this table has no connection:
say so plainly and stop, rather than inventing a name for one.

### Naming — derived from the repository, never from the process name

Everything is derived from the repository name, whose prefix IS the epic key:

```
repository name              jactiv-572-no-po-invoice-chaser
epic key                     jactiv-572
epic number                  572
process base                 no-po-invoice-chaser     (repo name minus the epic prefix)
solution / deployment name   no-po-invoice-chaser-572 (process base + epic number)
API Workflow project name    no-po-invoice-chaser-api
resource prefix              jactiv_572_
```

| Thing | Rule | Example |
|---|---|---|
| Solution name | `<process-base>-<epic-number>` | `no-po-invoice-chaser-572` |
| Deployment name, and so the Orchestrator sub-folder | the same string as the solution | `no-po-invoice-chaser-572` |
| The API Workflow project inside it | `<process-base>-api` | `no-po-invoice-chaser-api` |
| …and that one string appears in three places | the project directory, `project.uiproj`'s `"Name"`, and `resources/solution_folder/process/api/<name>.json` | all three read `no-po-invoice-chaser-api` |
| Every asset, credential, queue and bucket | `<epic_key>_<thing>`, lowercase, underscores | `jactiv_572_invoice_status`, `jactiv_572_coupa_api_key` |
| Connections | **never named here — they already exist**, see the table above | `coupa-uipath-test` |

**What Orchestrator actually displays.** The solution and its folder take the deployment
name; the process takes `project.uiproj`'s `"Name"`, NOT the directory it sits in and
NOT the solution name. Get that field wrong and the repository and the tenant read
different names for the same thing — one build shipped `jactiv-707-no-po-invoice-chaser`
in git showing as `NoPoInvoiceChaser` in Orchestrator, with the solution and the process
swapped relative to each other. `uipath-develop` now fails the build unless the
directory, the `"Name"` field and the process resource all carry the same string.

Two deployments do not collide on the project name: each deployment gets its own
Orchestrator folder, and processes are scoped to the folder. Only the SOLUTION name has
to be globally unique, which is what the epic number is for.

**Why the epic number is on the end of the solution name.** `uip solution deploy run`
names the Orchestrator sub-folder after the deployment, and refuses to create one that
already exists. Two epics of the same process — a change request, a re-run, a rehearsal
— would collide on a bare `no-po-invoice-chaser`, and the pipeline would be forced down
the upgrade path instead of producing a clean, separately inspectable deployment. The
epic number makes each lifecycle its own folder. Do not drop it, and do not substitute
the story key: a lifecycle has one epic but a different story per stage.

**Use the EPIC key, never a stage story key.** A lifecycle has one epic and one story
per stage — analysis, architecture, docs, development each carry a different key. If a
resource were named off the story key, a change-request replay would write a new SDD on
a new story and **rename every asset and connection**, which silently breaks a
deployment that is already live. The epic key is the only identifier stable across the
whole lifecycle, and the repository name is where it is recorded.

Never derive a resource name from the process name (`NoPoInvoiceFinder_...`) — it is not
unique across the estate and it changes when the process is renamed.

The SDD's names are binding: deployment and the as-built DSD both expect them unchanged.

Rules:

- **Never put a credential value in a document, a repo or a workflow file.** The SDD and
  DSD name the asset and its owner, never its value.
- **Filtering, formatting and paging belong in the request you write** — query
  parameters on the `httpRequest`, and at most one JavaScript step to shape the result.
  They are not a reason to add activities.
- **Connections are shared program infrastructure.** One per system, listed above,
  referenced by name and id — never recreated per project.

### Before you say the build is finished — read your own `Workflow.json` against this

Every line below is a defect that actually shipped on a real run of this programme and
had to be fixed by hand or by a repair pass. `uip api-workflow validate` passes all of
them: it checks structure, not any of this. Walk the list against the file you just
wrote, activity by activity, before you write the build notes. It takes under a minute
and it is the difference between a demo that runs and one that does not.

**Every HTTP Request activity**

- [ ] `bodyParameters.url` is filled in, and is the resource path RELATIVE to the
      connector's base URL — `invoices`, not `https://…/api/invoices`, and no leading
      slash. A shipped build left it empty and the call had nowhere to go.
- [ ] `bodyParameters.path` is present and identical to `url`.
- [ ] `bodyParameters.authentication` is `"connector"`, `targetConnector` names the
      vendor connector, and `connectionId` is a real id from §4's table — never
      `ImplicitConnection`, which fails at run time on `baseUrl is required`.

**The Slack call**

- [ ] `channel` is a member ID (`WLX9BD8FN`), never an email address.
- [ ] `body` contains the Block Kit payload INLINE — `channel`, `text` and `blocks`
      together. Not composed in a script step, not referenced through a variable.
- [ ] `body` has a top-level `text` as well as `blocks`.
- [ ] `body` reads `${{ channel: … }}`, NOT `${{ { channel: … } }}`. The doubled brace
      is a run-time SyntaxError that build, validate and deploy all pass.

**Names**

- [ ] Every `$context.outputs.<Name>` matches its activity key character for
      character, INCLUDING case. `http_request` against an activity named
      `HTTP_Request` reads as undefined, silently, at run time.
- [ ] The solution is named `solution_name` from the architecture contract, the project
      is `projects[0].name`, and `project.uiproj`'s `"Name"` matches the directory.

**Then actually run the gate.** `bash .github/scripts/validate-build.sh <code dir>
docs/architectural-considerations.md` is the same script the Test stage runs. Running it
yourself, here, while the file is still open and you still have the context, costs
seconds. Letting it fail in the Test stage costs a fresh agent three minutes, most of it
spent working out where the files are — and a repair written without this context is how
the doubled brace got introduced in the first place.


---

## 4.5 Reference implementation — the build starts from THIS, not from a blank file

Below is the complete `Workflow.json` of a build of this exact process that passed
`uip api-workflow validate`, passed `validate-build.sh`, packed, published, deployed
to Orchestrator, ran, and posted the Block Kit message to Slack. It is the approved
implementation of the No-PO Invoice Chaser, and **the build stage is required to
start from it** rather than compose a workflow from the SDD and the product docs.

Why this exists. Two builds of the same SDD came out at 21 KB and 35 KB, one right
and one bloated, and every build re-learned the same lessons about relative URLs,
member IDs, Block Kit bodies and brace counts by failing a gate first. A demo cannot
carry that variance. Composing from scratch is the right way to build something new;
this process is not new, and a reference that is already proven is both faster and
far more predictable than a fresh derivation. Only the parts the SDD genuinely
changes get touched.

**How the build stage uses it** — extract it with one command, never by re-typing:

```
awk '/^```json reference-workflow$/{f=1;next} /^```$/{if(f)exit} f' \
    docs/architectural-considerations.md > <project-dir>/Workflow.json
```

Then read the SDD and check three things against the extracted file: every `BR-xx`
has a step that implements it, the Coupa filter matches the SDD's window and status
values, and the variable names used in the Slack `body` (`qualifyingCount`,
`coupaUrl`, `windowStart`, `windowEnd`, `runDate`) are the ones the scripts set.
Change only a line the SDD contradicts. If nothing is contradicted, change nothing.

What is deliberately in here and must stay: the two HTTP Request activities in §4's
exact shape; the inline Block Kit body with `channel`, `text` and `blocks` and the
correct outer braces; the `Assign` aliases after each script (see §8 for why they
are not padding); the single edge `Try/Catch`. What is NOT in here: any credential,
any absolute URL, any email address.

```json reference-workflow
{
  "document": {
    "dsl": "1.0.0",
    "name": "no-po-invoice-chaser-api",
    "tags": {
      "projectId": "ea846bf4-5333-4ad0-a3b8-8cebf41317d4"
    },
    "version": "0.0.1",
    "namespace": "default",
    "metadata": {
      "variables": {
        "schema": {
          "format": "json",
          "document": {
            "type": "object",
            "properties": {
              "windowStart": {
                "type": "string",
                "default": ""
              },
              "windowEnd": {
                "type": "string",
                "default": ""
              },
              "runDate": {
                "type": "string",
                "default": ""
              },
              "qualifyingCount": {
                "type": "number",
                "default": 0
              },
              "exclusionLog": {
                "type": "string",
                "default": ""
              },
              "slackPayload": {
                "type": "string",
                "default": ""
              },
              "coupaUrl": {
                "type": "string",
                "default": ""
              },
              "slackSent": {
                "type": "boolean",
                "default": false
              }
            },
            "title": "Variables"
          }
        }
      }
    }
  },
  "input": {
    "schema": {
      "format": "json",
      "document": {
        "type": "object",
        "properties": {},
        "title": "Inputs"
      }
    }
  },
  "output": {
    "schema": {
      "format": "json",
      "document": {
        "type": "object",
        "properties": {
          "status": {
            "type": "string"
          },
          "qualifying_count": {
            "type": "number"
          },
          "slack_sent": {
            "type": "boolean"
          }
        },
        "title": "Outputs"
      }
    }
  },
  "do": [
    {
      "Sequence_1": {
        "do": [
          {
            "WorkflowStart": {
              "set": "${ { ...Object.entries($workflow.definition?.document?.metadata?.variables?.schema?.document?.properties || {}).reduce((acc, [name, def]) => ({ ...acc, [name]: def?.default }), {}), ...($workflow.input || {}) } }",
              "output": {
                "as": "${$input}"
              },
              "export": {
                "as": "{ ...$context, variables: { ...$context.variables, ...$output } }"
              },
              "metadata": {
                "activityType": "Assign",
                "displayName": "Workflow start",
                "fullName": "Assign",
                "isTransparent": true
              }
            }
          },
          {
            "Javascript_ComputeDateWindow": {
              "run": {
                "script": {
                  "code": "const now = new Date(); const pad = (n) => String(n).padStart(2,'0'); const fmt = (d) => `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}`; const windowEndDate = new Date(now.getFullYear(), now.getMonth(), now.getDate()); const windowStartDate = new Date(windowEndDate); windowStartDate.setDate(windowStartDate.getDate() - 7); return { windowStart: fmt(windowStartDate), windowEnd: fmt(windowEndDate), runDate: fmt(windowEndDate) };",
                  "language": "javascript",
                  "arguments": "${{ \"$context\": $context, \"$workflow\": $workflow, \"$input\": $input }}"
                }
              },
              "export": {
                "as": "{ ...$context, outputs: { ...$context?.outputs, \"Javascript_ComputeDateWindow\": $output } }"
              },
              "metadata": {
                "activityType": "JsInvoke",
                "displayName": "Compute date window",
                "fullName": "JsInvoke"
              }
            }
          },
          {
            "Assign_WindowStart": {
              "set": {
                "windowStart": "${$context.outputs.Javascript_ComputeDateWindow.windowStart}"
              },
              "export": {
                "as": "{ ...$context, variables: { ...$context.variables, ...$output } }"
              },
              "metadata": {
                "activityType": "Assign",
                "displayName": "Set windowStart",
                "fullName": "Assign",
                "isTransparent": false
              }
            }
          },
          {
            "Assign_WindowEnd": {
              "set": {
                "windowEnd": "${$context.outputs.Javascript_ComputeDateWindow.windowEnd}"
              },
              "export": {
                "as": "{ ...$context, variables: { ...$context.variables, ...$output } }"
              },
              "metadata": {
                "activityType": "Assign",
                "displayName": "Set windowEnd",
                "fullName": "Assign",
                "isTransparent": false
              }
            }
          },
          {
            "Assign_RunDate": {
              "set": {
                "runDate": "${$context.outputs.Javascript_ComputeDateWindow.runDate}"
              },
              "export": {
                "as": "{ ...$context, variables: { ...$context.variables, ...$output } }"
              },
              "metadata": {
                "activityType": "Assign",
                "displayName": "Set runDate",
                "fullName": "Assign",
                "isTransparent": false
              }
            }
          },
          {
            "HTTP_Request_Coupa": {
              "call": "UiPath.Http",
              "with": {
                "connector": "uipath-uipath-http",
                "connectionId": "5fadfc73-a372-46ae-a27c-2481741eed07",
                "connectionResourceId": "5fadfc73-a372-46ae-a27c-2481741eed07",
                "method": "POST",
                "endpoint": "/http-request",
                "bodyParameters": {
                  "authentication": "connector",
                  "targetConnector": "uipath-coupa-coupa",
                  "connection": "5fadfc73-a372-46ae-a27c-2481741eed07",
                  "method": "GET",
                  "path": "invoices",
                  "url": "invoices",
                  "query": {
                    "status[in]": "draft,new",
                    "invoice-date[gt_or_eq]": "${$context.variables.windowStart}",
                    "invoice-date[lt_or_eq]": "${$context.variables.windowEnd}",
                    "order_by": "invoice-date",
                    "dir": "desc",
                    "limit": "50"
                  }
                }
              },
              "export": {
                "as": "{ ...$context, outputs: { ...$context?.outputs, \"HTTP_Request_Coupa\": $output } }"
              },
              "metadata": {
                "activityType": "Connector",
                "displayName": "HTTP Request: Coupa",
                "uiPathActivityTypeId": "5c4cc855-b42a-37e6-b910-de8588998fce",
                "configuration": "{\"essentialConfiguration\":{\"connectorVersion\":\"1.4.44\",\"scriptRef\":null,\"customFieldsRequestDetails\":null,\"instanceParameters\":{\"connectorKey\":\"uipath-uipath-http\",\"objectName\":\"http-request\",\"httpMethod\":\"POST\",\"activityType\":\"Curated\",\"version\":\"1.0.0\",\"supportsStreaming\":false,\"subType\":\"method\"},\"objectName\":\"http-request\",\"operation\":\"create\",\"packageVersion\":\"1.0.0\",\"httpMethod\":\"POST\",\"path\":\"/http-request\",\"unifiedTypesCompatible\":true,\"savedJitInputFieldId\":\"in_http-request\"}}"
              }
            }
          },
          {
            "Javascript_FilterAndCount": {
              "run": {
                "script": {
                  "code": "const invoices = $context.outputs.HTTP_Request_Coupa.content || []; const excluded = []; const qualifying = []; for (const inv of invoices) { if (inv['invoice-type'] === 'Credit Note') { excluded.push(`${inv['invoice-number'] || inv['id']} excluded: credit note`); continue; } const lines = inv['invoice-lines'] || []; const hasLinkedPo = lines.some(l => (l['po-number'] && l['po-number'].trim() !== '') || (l['order-header-num'] && l['order-header-num'].trim() !== '')); if (hasLinkedPo) { excluded.push(`${inv['invoice-number'] || inv['id']} excluded: linked PO`); continue; } qualifying.push(inv); } return { qualifyingCount: qualifying.length, exclusionLog: excluded.join('; ') };",
                  "language": "javascript",
                  "arguments": "${{ \"$context\": $context, \"$workflow\": $workflow, \"$input\": $input }}"
                }
              },
              "export": {
                "as": "{ ...$context, outputs: { ...$context?.outputs, \"Javascript_FilterAndCount\": $output } }"
              },
              "metadata": {
                "activityType": "JsInvoke",
                "displayName": "Filter and count",
                "fullName": "JsInvoke"
              }
            }
          },
          {
            "Assign_QualifyingCount": {
              "set": {
                "qualifyingCount": "${$context.outputs.Javascript_FilterAndCount.qualifyingCount}"
              },
              "export": {
                "as": "{ ...$context, variables: { ...$context.variables, ...$output } }"
              },
              "metadata": {
                "activityType": "Assign",
                "displayName": "Set qualifyingCount",
                "fullName": "Assign",
                "isTransparent": false
              }
            }
          },
          {
            "Assign_ExclusionLog": {
              "set": {
                "exclusionLog": "${$context.outputs.Javascript_FilterAndCount.exclusionLog}"
              },
              "export": {
                "as": "{ ...$context, variables: { ...$context.variables, ...$output } }"
              },
              "metadata": {
                "activityType": "Assign",
                "displayName": "Set exclusionLog",
                "fullName": "Assign",
                "isTransparent": false
              }
            }
          },
          {
            "If_1#Wrapper": {
              "do": [
                {
                  "If_1": {
                    "switch": [
                      {
                        "case": {
                          "when": "${$context.variables.qualifyingCount > 0}",
                          "then": "If_1#Then"
                        }
                      },
                      {
                        "default": {
                          "then": "If_1#Else"
                        }
                      }
                    ],
                    "metadata": {
                      "displayName": "Branch on qualifying count"
                    }
                  }
                },
                {
                  "If_1#Then": {
                    "do": [
                      {
                        "Javascript_ComposeSlackPayload": {
                          "run": {
                            "script": {
                              "code": "const count = $context.variables.qualifyingCount; const start = $context.variables.windowStart; const end = $context.variables.windowEnd; const run = $context.variables.runDate; const url = `https://uipath-test.coupahost.com/invoices?q%5Binvoice_date_gteq%5D=${start}&q%5Binvoice_date_lteq%5D=${end}&q%5Bstatus_eq%5D=draft`; const payload = { channel: 'WLX9BD8FN', text: `:receipt: ${count} invoices from the last seven days have no purchase order linked`, blocks: [ { type: 'header', text: { type: 'plain_text', text: `:receipt: ${count} invoices need a purchase order`, emoji: true } }, { type: 'section', text: { type: 'mrkdwn', text: `:warning:  *${count} invoices* from the last seven days have no purchase order linked.\\n:no_entry:  An invoice without a linked PO cannot be matched or paid under our *no-PO-no-pay policy*, and payment to the supplier stalls until it is fixed.\\n:point_right:  Please make sure a purchase order exists for these invoices and is correctly linked to each one.` } }, { type: 'actions', elements: [ { type: 'button', text: { type: 'plain_text', text: 'Open the list in Coupa', emoji: true }, url: url, style: 'primary' } ] }, { type: 'divider' }, { type: 'context', elements: [ { type: 'mrkdwn', text: `:calendar: Invoices dated *${start}* to *${end}*  ·  :robot_face: No-PO Invoice Chaser  ·  checked *${run}*` } ] } ] }; return { slackPayload: JSON.stringify(payload), coupaUrl: url };",
                              "language": "javascript",
                              "arguments": "${{ \"$context\": $context, \"$workflow\": $workflow, \"$input\": $input }}"
                            }
                          },
                          "export": {
                            "as": "{ ...$context, outputs: { ...$context?.outputs, \"Javascript_ComposeSlackPayload\": $output } }"
                          },
                          "metadata": {
                            "activityType": "JsInvoke",
                            "displayName": "Compose Slack payload",
                            "fullName": "JsInvoke"
                          }
                        }
                      },
                      {
                        "Assign_SlackPayload": {
                          "set": {
                            "slackPayload": "${$context.outputs.Javascript_ComposeSlackPayload.slackPayload}"
                          },
                          "export": {
                            "as": "{ ...$context, variables: { ...$context.variables, ...$output } }"
                          },
                          "metadata": {
                            "activityType": "Assign",
                            "displayName": "Set slackPayload",
                            "fullName": "Assign",
                            "isTransparent": false
                          }
                        }
                      },
                      {
                        "Assign_CoupaUrl": {
                          "set": {
                            "coupaUrl": "${$context.outputs.Javascript_ComposeSlackPayload.coupaUrl}"
                          },
                          "export": {
                            "as": "{ ...$context, variables: { ...$context.variables, ...$output } }"
                          },
                          "metadata": {
                            "activityType": "Assign",
                            "displayName": "Set coupaUrl",
                            "fullName": "Assign",
                            "isTransparent": false
                          }
                        }
                      },
                      {
                        "HTTP_Request_Slack": {
                          "call": "UiPath.Http",
                          "with": {
                            "connector": "uipath-uipath-http",
                            "connectionId": "43d506f7-7de2-4798-aac1-9522e2e45dbb",
                            "connectionResourceId": "43d506f7-7de2-4798-aac1-9522e2e45dbb",
                            "method": "POST",
                            "endpoint": "/http-request",
                            "bodyParameters": {
                              "authentication": "connector",
                              "targetConnector": "uipath-salesforce-slack",
                              "connection": "43d506f7-7de2-4798-aac1-9522e2e45dbb",
                              "method": "POST",
                              "path": "chat.postMessage",
                              "url": "chat.postMessage",
                              "body": "${{ channel: 'WLX9BD8FN', text: `:receipt: ${$context.variables.qualifyingCount} invoices from the last seven days have no purchase order linked`, blocks: [ { type: 'header', text: { type: 'plain_text', text: `:receipt: ${$context.variables.qualifyingCount} invoices need a purchase order`, emoji: true } }, { type: 'section', text: { type: 'mrkdwn', text: `:warning:  *${$context.variables.qualifyingCount} invoices* from the last seven days have no purchase order linked.\\n:no_entry:  An invoice without a linked PO cannot be matched or paid under our *no-PO-no-pay policy*, and payment to the supplier stalls until it is fixed.\\n:point_right:  Please make sure a purchase order exists for these invoices and is correctly linked to each one.` } }, { type: 'actions', elements: [ { type: 'button', text: { type: 'plain_text', text: 'Open the list in Coupa', emoji: true }, url: $context.variables.coupaUrl, style: 'primary' } ] }, { type: 'divider' }, { type: 'context', elements: [ { type: 'mrkdwn', text: `:calendar: Invoices dated *${$context.variables.windowStart}* to *${$context.variables.windowEnd}*  ·  :robot_face: No-PO Invoice Chaser  ·  checked *${$context.variables.runDate}*` } ] } ] }}"
                            }
                          },
                          "export": {
                            "as": "{ ...$context, outputs: { ...$context?.outputs, \"HTTP_Request_Slack\": $output } }"
                          },
                          "metadata": {
                            "activityType": "Connector",
                            "displayName": "HTTP Request: Slack",
                            "uiPathActivityTypeId": "5c4cc855-b42a-37e6-b910-de8588998fce",
                            "configuration": "{\"essentialConfiguration\":{\"connectorVersion\":\"1.4.44\",\"scriptRef\":null,\"customFieldsRequestDetails\":null,\"instanceParameters\":{\"connectorKey\":\"uipath-uipath-http\",\"objectName\":\"http-request\",\"httpMethod\":\"POST\",\"activityType\":\"Curated\",\"version\":\"1.0.0\",\"supportsStreaming\":false,\"subType\":\"method\"},\"objectName\":\"http-request\",\"operation\":\"create\",\"packageVersion\":\"1.0.0\",\"httpMethod\":\"POST\",\"path\":\"/http-request\",\"unifiedTypesCompatible\":true,\"savedJitInputFieldId\":\"in_http-request\"}}"
                          }
                        }
                      },
                      {
                        "Javascript_ValidateSlack": {
                          "run": {
                            "script": {
                              "code": "const resp = $context.outputs.HTTP_Request_Slack.content; if (!resp || resp.ok !== true) { throw new Error(`Slack chat.postMessage failed: ${JSON.stringify(resp)}`); } return { ok: true };",
                              "language": "javascript",
                              "arguments": "${{ \"$context\": $context, \"$workflow\": $workflow, \"$input\": $input }}"
                            }
                          },
                          "export": {
                            "as": "{ ...$context, outputs: { ...$context?.outputs, \"Javascript_ValidateSlack\": $output } }"
                          },
                          "metadata": {
                            "activityType": "JsInvoke",
                            "displayName": "Validate Slack response",
                            "fullName": "JsInvoke"
                          }
                        }
                      },
                      {
                        "Assign_SlackSent": {
                          "set": {
                            "slackSent": true
                          },
                          "export": {
                            "as": "{ ...$context, variables: { ...$context.variables, ...$output } }"
                          },
                          "metadata": {
                            "activityType": "Assign",
                            "displayName": "Set slackSent true",
                            "fullName": "Assign",
                            "isTransparent": false
                          }
                        }
                      }
                    ],
                    "then": "exit"
                  }
                },
                {
                  "If_1#Else": {
                    "do": [],
                    "then": "exit"
                  }
                }
              ],
              "export": {
                "as": "{ ...$context, outputs: { ...$context?.outputs, \"If_1\": $output } }"
              },
              "metadata": {
                "activityType": "If",
                "displayName": "Branch: qualifying count > 0",
                "fullName": "If"
              }
            }
          },
          {
            "Javascript_LogResult": {
              "run": {
                "script": {
                  "code": "const count = $context.variables.qualifyingCount; const sent = $context.variables.slackSent; console.log(`qualifying_count=${count}`); console.log(`slack_sent=${sent}`); return { qualifying_count: count, slack_sent: sent };",
                  "language": "javascript",
                  "arguments": "${{ \"$context\": $context, \"$workflow\": $workflow, \"$input\": $input }}"
                }
              },
              "export": {
                "as": "{ ...$context, outputs: { ...$context?.outputs, \"Javascript_LogResult\": $output } }"
              },
              "metadata": {
                "activityType": "JsInvoke",
                "displayName": "Log result",
                "fullName": "JsInvoke"
              }
            }
          },
          {
            "Response_1": {
              "response": "${{ status: 'Successful', qualifying_count: $context.variables.qualifyingCount, slack_sent: $context.variables.slackSent }}",
              "markJobAsFailed": false,
              "then": "end",
              "export": {
                "as": "{ ...$context, outputs: { ...$context?.outputs, \"Response_1\": $output } }"
              },
              "metadata": {
                "activityType": "Response",
                "displayName": "Response",
                "fullName": "Response"
              }
            }
          }
        ],
        "metadata": {
          "activityType": "Sequence",
          "displayName": "Sequence",
          "fullName": "Sequence"
        }
      }
    }
  ],
  "evaluate": {
    "mode": "strict",
    "language": "javascript"
  }
}
```

---

## 5. Runtime and environment

| Field | Value |
|---|---|
| Unattended runtimes available | limited |
| Attended runtimes available | not available |
| Serverless / API Workflow runtime | available, no limit |
| Default robot attendance for new automations | unattended unless the process needs a human-only sign-in |

---

## 6. Company systems

One row per system the program automates against. An `[UNCONFIRMED]` endpoint stays an
`[ARCHITECT REVIEW]` item in the SDD — this table is only useful once it is filled.

An Integration Service connection being *available* is not the same as it *existing*:
the SDD still records the named connection as a deployment prerequisite that a human
must create and authorise in Integration Service.

| System | Purpose | Base URL | Connection (see §4) | IS connector available |
|---|---|---|---|---|
| Coupa | invoice and PO data | https://uipath-test.coupahost.com/api/ | `coupa-uipath-test` | YES |
| Slack | notifications to AP | https://slack.com/api/ | `slack-product-test-app` | YES |
| Jira | story tracking | https://uipath.atlassian.net/ | `jira-irina-capatina` | YES |
| GitHub | automation repositories | https://api.github.com/ | `gh_irina-capatina-org` | YES |
| UiPath Orchestrator | assets, queues, jobs | tenant API | `uipath-orchestrator` | YES |

---

## 7. Logging, data handling and support

| Field | Value |
|---|---|
| Logging target | Orchestrator job logs |
| Must never be logged | credential values; plus any field the PDD marks commercially sensitive |
| Transaction identifier in logs | the business key (invoice id, employee id), never a full record |

---

## 8. Design simplicity — the default is the smallest thing that works

The design must be the **smallest artifact that satisfies the requirement**. Complexity
is opt-in: every construct beyond the happy path has to trace back to something the PDD
actually states. This is a preference, not a law — but the burden of proof sits on the
complexity, not on the simplicity.

### The happy path is the design. Everything else is justified or absent.

Write the straight-line sequence first: read the data, decide, act, report. That
sequence *is* the process. Then add a deviation only when the PDD names the failure,
names who cares about it, and names what should happen instead. A failure mode nobody
has described is not a requirement — it is an invention.

### Do not add these unless the PDD asks for them

| Construct | Add it only when |
|---|---|
| Retry loop (`Do_While` + `Wait`, backoff, attempt counters) | the PDD states the system is unreliable **and** the platform's own retry cannot cover it (see below) |
| `Try/Catch` around an individual call | that one call has a **documented** business fallback that differs from failing the run |
| Correlation keys, run ids, trace tokens | the PDD or §7 asks for them |
| More than one terminal outcome | the PDD names each outcome and what a human does differently for each |
| A status/state variable | something downstream actually branches on it |
| Pagination, batching, chunking | the PDD gives a volume that needs it |
| A config asset for a value | the value genuinely changes per environment |

**Platform-native beats hand-built.** Where the runtime already provides a behaviour,
use it instead of building it out of activities. An API Workflow has `httpRetryConfig`
at the workflow level — that is the retry mechanism, not a `Do_While` wrapping a
`Try/Catch` wrapping a `Wait`. A connector's own filter/format operation beats a
JavaScript step that does the same string work (§4). Hand-rolling a platform feature
triples the artifact size and is the single largest driver of build time.

**One failure boundary, not one per call.** The default error design is a single
catch at the edge of the process that reports the failure and stops. Per-activity
error handling is the exception and needs a reason in the SDD.

### Business rules are filters, not architecture

A `BR-xx` that reads "exclude credit notes" is a predicate — one clause inside one
filtering step, alongside the other predicates. It is not its own activity, its own
branch, or its own outcome. Ten exclusion rules are **one** filter step with ten
conditions. Only a rule that changes *what the process does next* earns a branch.

### Sizing expectation

For a single-product automation with one source system and one destination, the
expected shape is roughly:

```
read from source  →  filter/decide  →  format  →  act on destination  →  respond
```

Five to eight *steps*. But an API Workflow spends more than one activity per step, so
count activities against **twenty**, not twelve.

The twelve was a guess made before a workflow of this shape had been built, and a real
build came in at nineteen with nothing wrong with it. Where the extra ones go:

| | |
|---|---|
| `Sequence`, `WorkflowStart`, `Response` | three structural activities every workflow has |
| one `Assign` per value a script returns | a `JsInvoke` returning three fields is followed by three `Assign` steps that alias `$context.outputs.<Script>.<field>` to `$context.variables.<field>` |

The aliasing `Assign` steps are **deliberate, and they stay**. They look like padding
and they are not: they concentrate every case-sensitive `$context.outputs.<ActivityName>`
reference into one place per script, so the rest of the workflow uses a short, stable
`$context.variables.<name>`. Removing them would mean spelling the activity name
correctly at every use instead of once - and a mis-cased reference reads as `undefined`
at run time with no build error and no validation error. That trade is not worth two
fewer rows in a count.

So: twenty is the number, and it is a *reporting* threshold, not a build failure. Above
it, check that a retry loop, a per-call try/catch or a third outcome has not crept in,
and that the SDD names the PDD statement that forced whatever did. "Good practice",
"robustness" and "production-grade" are not PDD statements.

### What this does not mean

This is not licence to drop scope. Every business rule the PDD lists still gets
implemented, every named resource still gets created, and nothing gets weakened to make
a check pass. Simplicity is about the *shape* of the solution, not its coverage — the
same behaviour, expressed with fewer moving parts.

---

## 9. Maintaining this file

- One row, one fact. If a value is contested, leave it `[UNCONFIRMED]` rather than
  guessing — an unmarked wrong value becomes an unmarked wrong statement in every SDD.
- Record the date and who confirmed a value when you fill it in.
- Changing §2 changes which products the Constraint Gate will recommend, so review the
  open SDDs after editing it.

| Date | Who | What changed |
|---|---|---|
| 2026-09-19 | drafted | initial skeleton; only the delivery type is confirmed |
| 2026-09-20 | irina.capatina | added §8 Design simplicity after JACTIV-665 produced a 1,837-line artifact (2 retry loops, 2 try/catch, 4 outcomes) for a 5-step process |
| 2026-09-20 | irina.capatina | §4 rewritten after JACTIV-665's Workflow.json shipped 31 activities with a fabricated Coupa activity and `<TODO>` connection ids: `httpRequest` on an existing connection is now the only approved shape for an API call, and the five existing connections are listed as facts |
| 2026-09-21 | irina.capatina | §4 corrected against the working reference solution in `automation-docs/Solution`: the approved shape is the HTTP Request activity with `authentication: "connector"` (NOT the connector's own `httpRequest`, and NOT `ImplicitConnection`). Canonical activity, `bindings_v2.json` entry and solution connection-resource file all recorded verbatim |
| 2026-09-21 | irina.capatina | §4 verified end-to-end against the live Coupa tenant: response payload is `.content` / `.statusCode` (not `.body` / `.code`), `status[in][]` returns 400 and `status[in]` works, and `coupa-uipath-test` is confirmed working despite a failing ping |
