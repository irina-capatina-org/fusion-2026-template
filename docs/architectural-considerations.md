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
        "url": "https://uipath-test.coupahost.com/api/invoices",
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
      "as": "{ ...$context, outputs: { ...$context?.outputs, \"http_request_1\": $output } }"
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
connection, verb and URL — and the payload in `body`:

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
        "url": "https://slack.com/api/chat.postMessage",
        "body": "${{ channel: $workflow.input.slackChannel, text: $context.variables.message }}"
      }
    },
    "export": {
      "as": "{ ...$context, outputs: { ...$context?.outputs, \"http_request_2\": $output } }"
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
| `HTTP_Request_1` and the `http_request_1` export key | yours — unique per activity, export key is the activity key lowercased |
| `connectionId` / `connectionResourceId` / `bodyParameters.connection` | yours — the **same** connection id in all three, from the table below |
| `bodyParameters.targetConnector` | yours — the connector key of the system being called |
| `bodyParameters.method` + `url` | yours — the real verb and URL of the call you are making |

`bodyParameters` accepts: `authentication`, `targetConnector`, `connection`, `method`
and `url` (all required), plus `path`, `headers`, `query` and `body` (optional). They
are flat keys taking **bare literals** — `"url": "https://…"`, never `"${'https://…'}"`,
which clears the field when Studio Web saves. A real reference stays wrapped:
`"body": "${$context.variables.payload}"`.

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

The repository name IS the solution name, and its prefix IS the epic key:

```
repository / solution name   jactiv-572-no-po-invoice-chaser
epic key                     jactiv-572
resource prefix              jactiv_572_
```

| Thing | Rule | Example |
|---|---|---|
| Solution name | = the repository name, verbatim | `jactiv-572-no-po-invoice-chaser` |
| Every asset, credential, queue and bucket | `<epic_key>_<thing>`, lowercase, underscores | `jactiv_572_invoice_status`, `jactiv_572_coupa_api_key` |
| Connections | **never named here — they already exist**, see the table above | `coupa-uipath-test` |

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

Five to eight activities. If the design exceeds **twelve** activities, or introduces a
second loop, the SDD must say in *Decisions Made* which PDD statement forced it. "Good
practice", "robustness" and "production-grade" are not PDD statements.

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
