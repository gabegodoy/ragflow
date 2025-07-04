# base stage
FROM ubuntu:22.04 AS base
USER root
SHELL ["/bin/bash", "-c"]

ARG NEED_MIRROR=0
ARG LIGHTEN=0
ENV LIGHTEN=${LIGHTEN}

WORKDIR /ragflow

# Install system dependencies
RUN apt-get update && \
    apt-get install -y \
    ca-certificates \
    libglib2.0-0 libglx-mesa0 libgl1 \
    pkg-config libicu-dev libgdiplus \
    default-jdk \
    libatk-bridge2.0-0 \
    libpython3-dev libgtk-4-1 libnss3 xdg-utils libgbm-dev \
    libjemalloc-dev \
    python3-pip pipx nginx unzip curl wget git vim less \
    ghostscript

# Install Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | bash -s -- -y --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"

# Install MSSQL ODBC driver
RUN curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - && \
    curl https://packages.microsoft.com/config/ubuntu/22.04/prod.list > /etc/apt/sources.list.d/mssql-release.list && \
    apt-get update && \
    ACCEPT_EULA=Y apt-get install -y unixodbc-dev msodbcsql17

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

# Get version info (without .git copy)
ARG RAGFLOW_VERSION=unknown
RUN echo "RAGFlow version: $RAGFLOW_VERSION" > /ragflow/VERSION

# production stage
FROM base AS production
WORKDIR /ragflow

# Copy Python environment
COPY --from=builder $VIRTUAL_ENV $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Copy application files
COPY . .

# Copy built frontend
COPY --from=builder /ragflow/web/dist /ragflow/web/dist
COPY --from=builder /ragflow/VERSION /ragflow/VERSION

# Entrypoint
COPY docker/entrypoint.sh ./
RUN chmod +x ./entrypoint.sh
ENTRYPOINT ["./entrypoint.sh"]