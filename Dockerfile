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


# ------------------------------------------------------------------
# 1.  BUILD STAGE  – compile deps with uv, pin recent FastMCP
# ------------------------------------------------------------------
FROM ghcr.io/astral-sh/uv:0.7-python3.10-bookworm-slim AS builder

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=0

WORKDIR /app

# 1-a  install dependencies (cached layer)
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --frozen --no-install-project --no-dev

# 1-b  copy source and build wheel
COPY . /app
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

# ------------------------------------------------------------------
# 2.  RUNTIME STAGE  – minimal image, non-root user, health-check
# ------------------------------------------------------------------
FROM python:3.10-slim-bookworm

# create unprivileged user
RUN groupadd --gid 1000 app && \
    useradd --uid 1000 --gid app --shell /bin/bash --create-home app

WORKDIR /app

# copy venv + source
COPY --from=builder --chown=app:app /app /app

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1

USER app
EXPOSE 8000

# simple health probe – MCP HTTP transport answers 404 on / -> 200 on /health
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import httpx,sys;sys.exit(0 if httpx.get('http://localhost:8000/health',timeout=2).is_success else 1)"

# run the server (HTTP transport is recognised now)
CMD ["python", "-m", "freesound_mcp_server.freesound"]
