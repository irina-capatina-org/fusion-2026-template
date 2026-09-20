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

| Need | Preferred pattern | Fallback |
|---|---|---|
| Third-party SaaS with a catalog connector (Slack, Outlook/O365, Salesforce, Google Workspace, SAP, ServiceNow) | **Integration Service connection** | direct HTTP + connector authentication, when the connector lacks the curated operation, HTTP + Orchestrator connection if all else fails |
| Third-party SaaS with no catalog connector | HTTP Request + **Integration Service connection** | HTTP Request + **Orchestrator credential asset** |
| Any username / password / token / client secret | **Orchestrator credential asset**, never a plain asset, never inline | — |

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
| Every asset, credential, queue, bucket and connection | `<epic_key>_<thing>`, lowercase, underscores | `jactiv_572_coupa_connection`, `jactiv_572_slack_connection`, `jactiv_572_invoice_status` |

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
- **Prefer a connector's own activity over hand-rolled string work** — OData filters,
  message formatting, pagination.
- **One connection per system per environment**, referenced by name, not recreated per
  project.

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

| System | Purpose | Base URL | Auth | IS connector available |
|---|---|---|---|---|
| Coupa | invoice and PO data | https://uipath-test.coupahost.com/api/ | IS connection | YES |
| Slack | notifications to AP | https://slack.com/api/ | IS connection | YES |
| Jira | story tracking | https://uipath.atlassian.net/ | IS connection | YES |

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
