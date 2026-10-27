FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    FRAUDSHIELD_HOME=/app

RUN apt-get update && apt-get install -y --no-install-recommends libgomp1 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY pyproject.toml README.md ./
COPY src ./src
RUN pip install ".[api,vector,agents,llm]"

# Deep-learning layer (GNN + graph autoencoder): build with --build-arg WITH_DL=1.
# CPU-only PyTorch wheels keep the image small.
ARG WITH_DL=0
RUN if [ "$WITH_DL" = "1" ]; then \
      pip install torch --index-url https://download.pytorch.org/whl/cpu && pip install torch-geometric; \
    fi

COPY knowledge_base ./knowledge_base
COPY configs ./configs

RUN useradd --create-home --uid 10001 fraudshield && mkdir -p /app/data /app/artifacts && chown -R fraudshield /app
USER fraudshield

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=600s CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/health')"
CMD ["fraudshield", "serve", "--host", "0.0.0.0", "--port", "8000"]
