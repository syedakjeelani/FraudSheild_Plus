PY ?= python3

.PHONY: install install-dl data train fast test serve demo openapi neo4j-export docker

install:            ## core, API, vector index, agents, tests
	$(PY) -m pip install -e ".[api,vector,agents,llm,dev]"

install-dl:         ## GNN + graph autoencoder (CPU wheels)
	$(PY) -m pip install torch --index-url https://download.pytorch.org/whl/cpu
	$(PY) -m pip install torch-geometric

data:               ## synthetic data in the IBM AMLworld file format
	$(PY) -m fraudshield generate

train:              ## full pipeline + evaluation report (artifacts/evaluation.md)
	$(PY) -m fraudshield train

fast:               ## small world, ~10 seconds
	$(PY) -m fraudshield --fast train --reports 5

test:
	$(PY) -m pytest

serve:              ## API on http://127.0.0.1:8000 (docs at /docs)
	$(PY) -m fraudshield serve

demo:               ## train if needed, then investigate the top alert
	$(PY) -m fraudshield demo

openapi:            ## contract for the UI team
	$(PY) -m fraudshield openapi --out docs/openapi.json

neo4j-export:
	$(PY) -m fraudshield export-neo4j --out artifacts/neo4j

docker:
	docker compose up --build api
