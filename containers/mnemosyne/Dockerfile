# Mnemosyne MCP server — local-first AI agent memory.
# Single SQLite file, sub-millisecond, zero external dependencies.
#
# Usage:
#   podman build -t mnemosyne-memory -f containers/mnemosyne/Dockerfile .
#   podman run -v /var/lib/mnemosyne:/data -p 8000:8000 mnemosyne-memory
#
# MCP endpoint: http://localhost:8000/mcp (Streamable HTTP)
# Health:       http://localhost:8000/health

FROM python:3.12-slim

# Install only what's needed for the runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd --create-home --shell /bin/bash mnemosyne

# Install mnemosyne with local embeddings (fastembed + bge-small-en-v1.5, ~800MB RAM)
RUN pip install --no-cache-dir mnemosyne-memory[embeddings]

# Data directory for SQLite database
RUN mkdir -p /data && chown mnemosyne:mnemosyne /data

USER mnemosyne
WORKDIR /data
ENV MNEMOSYNE_DATA_DIR=/data

# MCP over Streamable HTTP (for remote access via Tailscale)
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -sf http://localhost:8000/health || exit 1

ENTRYPOINT ["mnemosyne", "mcp", "--transport", "sse", "--host", "0.0.0.0", "--port", "8000"]
