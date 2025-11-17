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

# ---------------------------------------------------------------------
# Runtime stage: lightweight final image
# ---------------------------------------------------------------------
FROM python:3.10-slim-bookworm

# ensure output isn't buffered (helps logs)
ENV PYTHONUNBUFFERED=1

# create non-root user "app" for security and to make chown valid
RUN groupadd --gid 1000 app || true && \
    useradd --uid 1000 --gid app --shell /usr/sbin/nologin --create-home app || true

WORKDIR /app

# copy files from builder; make app user the owner
COPY --from=builder --chown=app:app /app /app

# add virtualenv bin path if uv created one at /app/.venv
ENV PATH="/app/.venv/bin:$PATH"

# make sure pip & build tools are available, then install/upgrade fastmcp + http extras
# This guarantees the "http" (Streamable HTTP) transport is registered in the final image.
RUN python -m pip install --upgrade pip setuptools wheel && \
    python -m pip install --no-cache-dir -U fastmcp>=2.3.0 fastmcp-http httpx uvicorn anyio

# switch to non-root user
USER app

# expose the typical port we'll listen on (Render injects PORT at runtime)
EXPOSE 8000

# Default command: start the freesound MCP server using Streamable HTTP
# Note: your Python code should read PORT from environment (os.getenv("PORT"))
CMD ["python", "-m", "freesound_mcp_server.freesound", "--transport", "http", "--host", "0.0.0.0"]
