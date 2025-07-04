# base stage
FROM ubuntu:22.04 AS base
USER root
SHELL ["/bin/bash", "-c"]

# Set environment variables to prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC \
    PATH="/root/.local/bin:$PATH"

WORKDIR /ragflow

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3.10-venv \
    python3-pip \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install uv (pip replacement)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.cargo/bin:/root/.local/bin:$PATH"

# Create virtual environment
RUN python3 -m venv /ragflow/.venv
ENV VIRTUAL_ENV=/ragflow/.venv \
    PATH="/ragflow/.venv/bin:$PATH"

# builder stage
FROM base AS builder
WORKDIR /ragflow

# First copy just the dependency files
COPY pyproject.toml uv.lock ./

# Install Python dependencies using uv
RUN uv pip install --no-cache-dir -r requirements.txt || \
    (uv pip install -e . && \
     uv pip compile pyproject.toml -o requirements.txt && \
     uv pip install --no-cache-dir -r requirements.txt)

# Copy and build frontend (if needed)
COPY web web
RUN if [ -f "web/package.json" ]; then \
      curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
      apt-get install -y nodejs && \
      cd web && npm install && npm run build; \
    fi

# production stage
FROM base AS production
WORKDIR /ragflow

# Copy Python environment
COPY --from=builder $VIRTUAL_ENV $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Copy application code
COPY . .

# Entrypoint
COPY docker/entrypoint.sh ./
RUN chmod +x ./entrypoint.sh

EXPOSE 8000
ENTRYPOINT ["./entrypoint.sh"]