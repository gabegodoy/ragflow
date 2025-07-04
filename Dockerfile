# base stage
FROM ubuntu:22.04 AS base
USER root
SHELL ["/bin/bash", "-c"]

# Set environment variables to prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC

ARG NEED_MIRROR=0
ARG LIGHTEN=0
ARG RAGFLOW_VERSION=latest
ENV LIGHTEN=${LIGHTEN}

WORKDIR /ragflow

# Install system dependencies with automatic timezone configuration
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    tzdata \
    ca-certificates \
    libglib2.0-0 libglx-mesa0 libgl1 \
    pkg-config libicu-dev libgdiplus \
    default-jdk \
    libatk-bridge2.0-0 \
    libpython3-dev libgtk-4-1 libnss3 xdg-utils libgbm-dev \
    libjemalloc-dev \
    python3-pip pipx nginx unzip curl wget git vim less \
    ghostscript && \
    ln -fs /usr/share/zoneinfo/Etc/UTC /etc/localtime && \
    dpkg-reconfigure --frontend noninteractive tzdata && \
    rm -rf /var/lib/apt/lists/*

# Install Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | bash -s -- -y --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"

# Install MSSQL ODBC driver
RUN curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /etc/apt/trusted.gpg.d/microsoft.gpg && \
    curl https://packages.microsoft.com/config/ubuntu/22.04/prod.list > /etc/apt/sources.list.d/mssql-release.list && \
    apt-get update && \
    ACCEPT_EULA=Y apt-get install -y unixodbc-dev msodbcsql17 && \
    rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pipx install uv
ENV VIRTUAL_ENV=/ragflow/.venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# builder stage
FROM base AS builder
WORKDIR /ragflow

# Copy and install Python dependencies
COPY pyproject.toml uv.lock ./
RUN uv pip install -r <(uv pip compile pyproject.toml)

# Build frontend
COPY web web
RUN cd web && npm install && npm run build

# Set version info
RUN echo "RAGFlow version: ${RAGFLOW_VERSION}" > /ragflow/VERSION

# production stage
FROM base AS production
WORKDIR /ragflow

# Copy Python environment
COPY --from=builder $VIRTUAL_ENV $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Copy application files (excluding unnecessary files)
COPY api api
COPY conf conf
COPY deepdoc deepdoc
COPY rag rag
COPY agent agent
COPY graphrag graphrag
COPY agentic_reasoning agentic_reasoning
COPY mcp mcp
COPY plugin plugin
COPY docker/service_conf.yaml.template ./conf/service_conf.yaml.template

# Copy built frontend
COPY --from=builder /ragflow/web/dist /ragflow/web/dist
COPY --from=builder /ragflow/VERSION /ragflow/VERSION

# Entrypoint
COPY docker/entrypoint.sh ./
RUN chmod +x ./entrypoint.sh

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

EXPOSE 8000
ENTRYPOINT ["./entrypoint.sh"]