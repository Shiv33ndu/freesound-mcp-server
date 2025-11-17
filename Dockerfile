# # Taken reference from the following Dockerfile examples:
# #  * UV Docker Example      - https://github.com/astral-sh/uv-docker-example/blob/main/multistage.Dockerfile
# #  * MCP Local RAG Example  - https://github.com/nkapila6/mcp-local-rag/blob/main/Dockerfile


# ### BUILD STAGE: installs dependencies and builds everything we need
# FROM ghcr.io/astral-sh/uv:0.7-python3.10-bookworm-slim AS builder

# # optimizations
# ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy

# # use system Python interpreter for consistency across images
# ENV UV_PYTHON_DOWNLOADS=0

# WORKDIR /app

# # install dependencies w/ cache mounts (faster rebuilds)
# RUN --mount=type=cache,target=/root/.cache/uv \
#     --mount=type=bind,source=uv.lock,target=uv.lock \
#     --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
#     # --mount=type=bind,source=.python-version,target=.python-version \
#     uv sync --frozen --no-install-project --no-dev
#     # uv sync --frozen --no-install-project --no-dev --no-editable


# COPY . /app

# RUN --mount=type=cache,target=/root/.cache/uv \
#     uv sync --frozen --no-dev



# ### RUNTIME STAGE: lightweight image for running the app
# FROM python:3.10-slim-bookworm

# # # create non-root user for security
# # RUN groupadd --gid 1000 app && \
# #     useradd --uid 1000 --gid app --shell /bin/bash --create-home app

# WORKDIR /app

# # copy application from the builder
# COPY --from=builder --chown=app:app /app /app

# ENV PATH="/app/.venv/bin:$PATH"

# # expose port for HTTP server (only used when running in HTTP mode)
# EXPOSE 8000

# # default stdio transport
# # can be overridden at runtime for different transports
# #CMD ["python", "-m", "freesound_mcp_server.freesound", "--transport", "stdio"]

# # CMD ["uv", "run", "freesound-mcp", "--transport", "stdio"]

# # Streamable HTTP transport
# CMD ["python", "-m", "freesound_mcp_server.freesound", "--transport", "http", "--host", "0.0.0.0"]


# ---------------------------------------------------------------------
# Multi-stage Dockerfile for Freesound MCP server (Streamable HTTP)
# ---------------------------------------------------------------------
# Build stage: use uv image to resolve Python deps declared by uv.lock / pyproject.toml
FROM ghcr.io/astral-sh/uv:0.7-python3.10-bookworm-slim AS builder

# optimizations for uv
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
ENV UV_PYTHON_DOWNLOADS=0

WORKDIR /app

# run uv to populate builder environment (cache mounts help dev iter)
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --frozen --no-install-project --no-dev

# copy project source into builder
COPY . /app

# run uv sync again (ensures project deps listed in pyproject are resolved in builder)
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev


# ---------------------------------------------------------------------
# Runtime stage: lightweight final image
# ---------------------------------------------------------------------
FROM python:3.10-slim-bookworm

ENV PYTHONUNBUFFERED=1

# create non-root user "app" for security
RUN groupadd --gid 1000 app || true && \
    useradd --uid 1000 --gid app --shell /usr/sbin/nologin --create-home app || true

WORKDIR /app

# copy project from builder
COPY --from=builder /app /app

# Install small system build deps (only what is needed), then remove apt caches
RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

# Ensure system Python has pip available
RUN python3 -m ensurepip || true

# Upgrade pip & build tools
RUN python3 -m pip install --upgrade pip setuptools wheel

# Install your package (so 'python -m freesound_mcp_server.freesound' is importable)
# This will work with both src/ layout and plain package layout.
RUN python3 -m pip install --no-cache-dir /app

# Install FastMCP and HTTP extras (ensures "http" transport is registered)
RUN python3 -m pip install --no-cache-dir -U fastmcp>=2.3.0 fastmcp-http httpx uvicorn anyio

# Fix ownership (so non-root user can read and run)
RUN chown -R app:app /app

# Switch to non-root user
USER app

# Expose the port (Render overrides PORT at runtime)
EXPOSE 8000

# Final command: run module (module name, not file path). Your app should read PORT env var.
CMD ["python3", "-m", "freesound_mcp_server.freesound", "--transport", "http", "--host", "0.0.0.0"]
