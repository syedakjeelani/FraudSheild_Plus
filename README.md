# FraudShield+

AI-based anti-money-laundering intelligence platform. It learns known laundering patterns, matches
new cases to past crimes, surfaces patterns it was never trained on, and hands investigators a case
file in which every statement is checked against the evidence. It covers the five areas of the
project plan: data structures and algorithms, machine learning, deep learning, generative AI and
agentic AI.

**Status:** backend complete, tested and runnable end to end; the investigator UI will be built on
the API once the design arrives (see [docs/api-contract.md](docs/api-contract.md)).

## Quick start

```bash
pip install -e ".[api,vector,agents,dev]"     # Python 3.10+
make install-dl                                # optional: GNN + graph autoencoder (CPU PyTorch)

fraudshield --fast demo        # ~10 s: small synthetic world, train, investigate the top alert
fraudshield train              # ~5 min: default world (380k transactions), writes artifacts/evaluation.md
fraudshield serve              # API on http://127.0.0.1:8000, interactive docs at /docs
pytest                         # 94 tests
```

Other commands: `fraudshield investigate --case <id>`, `fraudshield query "<question>"`,
`fraudshield screen "<name>"`, `fraudshield kb search|ingest`, `fraudshield export-neo4j`,
`fraudshield openapi`, `fraudshield generate`. Docker: `docker compose up api`
(profiles `graph` for Neo4j, `llm` for Ollama).

## Results on the default synthetic world

381,108 transactions, 6,439 accounts, 0.9% laundering, 30 days; trained on the first 18 days, tuned on
the next 6, evaluated on the last 6. PEEL-CHAIN was held out: unlabelled until the test period.

| What the plan asks for | Result |
|---|---|
| Flag known typologies | Stacked LightGBM + GNN: PR-AUC 0.922, recall 89.9%, precision@100 99%; all 48 test attempts reach an analyst |
| Surface patterns never trained on | PEEL-CHAIN: all 4 attempts detected (90.6% of its transactions); all its cases flagged as a candidate new pattern (cluster purity 20%) |
| Match a new case to past cases | Correct typology from the nearest confirmed case 93.2% of the time (top-5 vote 95.5%) |
| Grounded case files | 251 of 251 claims verified against evidence; 100% of injected false claims caught |
| Investigation time | Instrumented (case open to decision, with and without the AI case file); user-study protocol in the docs |

Full report with per-typology tables and a fairness audit (which found a disparity worth acting on):
[docs/evaluation.md](docs/evaluation.md). Synthetic results overstate real performance; the IBM AMLworld
run is the benchmark to report.

## How the plan maps to the code

| Area | What is built | Where |
|---|---|---|
| DSA | Temporal multigraph as compressed adjacency lists; time-respecting BFS/DFS money trails; Tarjan SCC; Johnson's cycles on case graphs and time-ordered, flow-conserving cycle search on the full graph; two-pointer sliding windows for structuring and for causal features; Union-Find entity resolution and case grouping; Levenshtein + BK-tree + Bloom filter screening; VF2 typology templates; binary-heap alert queue; PageRank and personalised PageRank | `graph/`, `features/`, `screening/` |
| ML | LightGBM transaction classifier with class weighting and exact TreeSHAP reasons; Isolation Forest and LOF; HDBSCAN discovery of new patterns; F2-optimal thresholds; PR-AUC-based evaluation | `models/` |
| DL | GINE graph neural network with reverse message passing and edge updates (Multi-GNN style); graph autoencoder; case embeddings in a FAISS index of past crimes | `dl/` |
| GenAI | Case narratives (offline templates, local Ollama model or Claude API); BM25 retrieval over typology documents with citations; text-to-Cypher with a read-only guard and in-memory execution; pseudonymisation and an egress guard for external models | `genai/`, `knowledge_base/` |
| Agentic AI | LangGraph orchestrator with six agents: triage, graph investigator, screening, typology matcher, report writer, critic. The critic verifies each claim against tool evidence and sends drafts back for revision | `agents/` |
| Human in the loop | Decisions, triage timing, audit log, active-learning retrain, naming of new patterns | `feedback/`, `api/` |

Design decisions and their reasons: [docs/architecture.md](docs/architecture.md).

## Data

Runs out of the box on a synthetic world written in the **IBM AMLworld file format**
(`*_Trans.csv`, `*_Patterns.txt`, `*_accounts.csv`), so the real Kaggle files drop in unchanged:

```bash
fraudshield --config configs/ibm-hi-small.yaml train
```

Loaders also exist for SAML-D, PaySim, Elliptic, OpenSanctions/OFAC and ICIJ Offshore Leaks. Details,
download commands and format notes: [docs/datasets.md](docs/datasets.md).

## Language models and privacy

| `llm.provider` | Data leaves the machine? | Use |
|---|---|---|
| `offline` (default) | No | deterministic template writer; reproducible; no model needed |
| `ollama` | No | local open model (default `qwen2.5:7b`) |
| `anthropic` | Only if `llm.allow_external: true` | Claude via the Messages API (default `claude-sonnet-5-5`); ids and names pseudonymised before the call |

Whatever writes the text, the recommendation comes from transparent rules and an analyst decides.

## Documentation

- [docs/architecture.md](docs/architecture.md): layers, data flow, design decisions, scaling notes
- [docs/api-contract.md](docs/api-contract.md): endpoints and JSON shapes for the UI, screen by screen
- [docs/evaluation.md](docs/evaluation.md): latest evaluation report; [protocol](docs/evaluation-protocol.md)
- [docs/datasets.md](docs/datasets.md): datasets, formats, downloads
- [docs/ethics-and-limitations.md](docs/ethics-and-limitations.md): what the system must not do, fairness, privacy, model card
- [docs/openapi.json](docs/openapi.json): machine-readable API contract; [docs/examples/](docs/examples/): real API responses and an example case file

## Project layout

```
src/fraudshield/
  data/        schema, loaders, synthetic IBM-format generator, temporal split
  graph/       temporal graph, traversal, SCC, cycles, structuring, Union-Find, PageRank, VF2, alert queue
  features/    sliding-window and graph features per scoring batch
  models/      LightGBM, anomaly models, discovery, metrics, SHAP descriptions
  dl/          GNN, graph autoencoder, FAISS case index
  cases/       case grouping and structural signatures
  screening/   Levenshtein, BK-tree, Bloom filter, watchlist and offshore screening
  genai/       LLM providers, retrieval, text-to-Cypher, Neo4j export
  agents/      orchestrator, specialists, report writer, critic
  feedback/    decision store, active learning
  api/         FastAPI app and schemas
  pipeline.py  training and monitoring run      evaluation.py  metrics and report
  service.py   platform shared by API, agents and CLI      cli.py  command line
knowledge_base/  typology notes (add FATF / FinCEN / FIU-IND documents with `fraudshield kb ingest`)
configs/         default.yaml, ibm-hi-small.yaml
tests/           94 tests: algorithms vs reference implementations, features vs brute force, agents, API
```

Framing note from the plan: domestic AML work is done by financial intelligence units such as FIU-IND
or FinCEN. The end user, regulator and report type (STR or SAR) are configuration values
(`end_user`, `jurisdiction`).
