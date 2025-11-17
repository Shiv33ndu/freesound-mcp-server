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

# use cache mounts for faster rebuilds; this will run uv to populate .venv in builder
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --frozen --no-install-project --no-dev

# copy the project source into builder
COPY . /app

# run uv sync again to install project into the builder venv (if pyproject defines it)
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

### RUNTIME STAGE: lightweight image for running the app
FROM python:3.10-slim-bookworm

# ensure output isn't buffered (helps logs)
ENV PYTHONUNBUFFERED=1

# create non-root user "app" for security
RUN groupadd --gid 1000 app || true && \
    useradd --uid 1000 --gid app --shell /usr/sbin/nologin --create-home app || true

WORKDIR /app

# copy application from the builder (don't rely on builder venv; copy project files)
COPY --from=builder /app /app

# install minimal system packages required to build wheels (if any), then clean apt caches
RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

# Make sure the system Python has pip. If ensurepip fails it's okay, we still call python3 -m pip
RUN python3 -m ensurepip || true

# Use system python3 to upgrade pip and install runtime python packages.
# This ensures pip is available and uses the runtime's Python environment (not a copied venv).
RUN python3 -m pip install --upgrade pip setuptools wheel && \
    python3 -m pip install --no-cache-dir -U fastmcp>=2.3.0 fastmcp-http httpx uvicorn anyio

# If your builder created /app/.venv and you want to prefer it, you can add it to PATH AFTER installing pip above.
# But generally it's more robust to rely on system site-packages in runtime.
# If you still want to use /app/.venv first, uncomment next line:
# ENV PATH="/app/.venv/bin:$PATH"

# switch to non-root user
USER app

# expose the typical port we'll listen on (Render injects PORT at runtime)
EXPOSE 8000

# Default command: start the freesound MCP server using Streamable HTTP
CMD ["python3", "-m", "/app/src/freesound_mcp_server/freesound.py", "--transport", "http", "--host", "0.0.0.0"]
