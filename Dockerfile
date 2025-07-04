# base stage
FROM ubuntu:22.04 AS base
USER root
SHELL ["/bin/bash", "-c"]

ARG NEED_MIRROR=0
ARG LIGHTEN=0
ENV LIGHTEN=${LIGHTEN}

WORKDIR /ragflow

# Copy models downloaded via download_deps.py
RUN mkdir -p /ragflow/rag/res/deepdoc /root/.ragflow
COPY --from=infiniflow/ragflow_deps:latest /huggingface.co/InfiniFlow/huqie/huqie.txt.trie /ragflow/rag/res/
COPY --from=infiniflow/ragflow_deps:latest /huggingface.co/InfiniFlow/text_concat_xgb_v1.0 /ragflow/rag/res/deepdoc/text_concat_xgb_v1.0
COPY --from=infiniflow/ragflow_deps:latest /huggingface.co/InfiniFlow/deepdoc /ragflow/rag/res/deepdoc/

RUN if [ "$LIGHTEN" != "1" ]; then \
    mkdir -p /root/.ragflow && \
    COPY --from=infiniflow/ragflow_deps:latest /huggingface.co/BAAI/bge-large-zh-v1.5 /root/.ragflow/bge-large-zh-v1.5 && \
    COPY --from=infiniflow/ragflow_deps:latest /huggingface.co/maidalun1020/bce-embedding-base_v1 /root/.ragflow/bce-embedding-base_v1; \
    fi

# Copy tika and other dependencies
COPY --from=infiniflow/ragflow_deps:latest /nltk_data /root/nltk_data
COPY --from=infiniflow/ragflow_deps:latest /tika-server-standard-3.0.0.jar /ragflow/
COPY --from=infiniflow/ragflow_deps:latest /tika-server-standard-3.0.0.jar.md5 /ragflow/
COPY --from=infiniflow/ragflow_deps:latest /cl100k_base.tiktoken /ragflow/9b5ad71b2ce5302211f9c61530b329a4922fc6a4

ENV TIKA_SERVER_JAR="file:///ragflow/tika-server-standard-3.0.0.jar"
ENV DEBIAN_FRONTEND=noninteractive

# Setup apt packages
RUN if [ "$NEED_MIRROR" == "1" ]; then \
        sed -i 's|http://ports.ubuntu.com|http://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list; \
        sed -i 's|http://archive.ubuntu.com|http://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list; \
    fi; \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache && \
    chmod 1777 /tmp && \
    apt update && \
    apt --no-install-recommends install -y ca-certificates && \
    apt update && \
    apt install -y libglib2.0-0 libglx-mesa0 libgl1 \
                   pkg-config libicu-dev libgdiplus \
                   default-jdk \
                   libatk-bridge2.0-0 \
                   libpython3-dev libgtk-4-1 libnss3 xdg-utils libgbm-dev \
                   libjemalloc-dev \
                   python3-pip pipx nginx unzip curl wget git vim less \
                   ghostscript

RUN if [ "$NEED_MIRROR" == "1" ]; then \
        pip3 config set global.index-url https://mirrors.aliyun.com/pypi/simple && \
        pip3 config set global.trusted-host mirrors.aliyun.com; \
        mkdir -p /etc/uv && \
        echo "[[index]]" > /etc/uv/uv.toml && \
        echo 'url = "https://mirrors.aliyun.com/pypi/simple"' >> /etc/uv/uv.toml && \
        echo "default = true" >> /etc/uv/uv.toml; \
    fi; \
    pipx install uv

ENV PYTHONDONTWRITEBYTECODE=1 DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
ENV PATH=/root/.local/bin:$PATH

# Install Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt purge -y nodejs npm cargo && \
    apt autoremove -y && \
    apt update && \
    apt install -y nodejs

# Install Rust
RUN apt update && apt install -y curl build-essential \
    && if [ "$NEED_MIRROR" == "1" ]; then \
         export RUSTUP_DIST_SERVER="https://mirrors.tuna.tsinghua.edu.cn/rustup"; \
         export RUSTUP_UPDATE_ROOT="https://mirrors.tuna.tsinghua.edu.cn/rustup/rustup"; \
       fi; \
    curl --proto '=https' --tlsv1.2 --http1.1 -sSf https://sh.rustup.rs | bash -s -- -y --profile minimal \
    && echo 'export PATH="/root/.cargo/bin:${PATH}"' >> /root/.bashrc

ENV PATH="/root/.cargo/bin:${PATH}"

# Add MSSQL ODBC driver
RUN curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - && \
    curl https://packages.microsoft.com/config/ubuntu/22.04/prod.list > /etc/apt/sources.list.d/mssql-release.list && \
    apt update && \
    arch="$(uname -m)"; \
    if [ "$arch" = "arm64" ] || [ "$arch" = "aarch64" ]; then \
        ACCEPT_EULA=Y apt install -y unixodbc-dev msodbcsql18; \
    else \
        ACCEPT_EULA=Y apt install -y unixodbc-dev msodbcsql17; \
    fi

# Add Chrome for selenium
COPY --from=infiniflow/ragflow_deps:latest /chrome-linux64-121-0-6167-85 /chrome-linux64.zip
RUN unzip /chrome-linux64.zip && \
    mv chrome-linux64 /opt/chrome && \
    ln -s /opt/chrome/chrome /usr/local/bin/

COPY --from=infiniflow/ragflow_deps:latest /chromedriver-linux64-121-0-6167-85 /chromedriver-linux64.zip
RUN unzip -j /chromedriver-linux64.zip chromedriver-linux64/chromedriver && \
    mv chromedriver /usr/local/bin/ && \
    rm -f /usr/bin/google-chrome

# Install libssl
RUN arch="$(uname -m)"; \
    if [ "$arch" = "x86_64" ]; then \
        COPY --from=infiniflow/ragflow_deps:latest /libssl1.1_1.1.1f-1ubuntu2_amd64.deb /tmp/ && \
        dpkg -i /tmp/libssl1.1_1.1.1f-1ubuntu2_amd64.deb; \
    elif [ "$arch" = "aarch64" ]; then \
        COPY --from=infiniflow/ragflow_deps:latest /libssl1.1_1.1.1f-1ubuntu2_arm64.deb /tmp/ && \
        dpkg -i /tmp/libssl1.1_1.1.1f-1ubuntu2_arm64.deb; \
    fi

# builder stage
FROM base AS builder
USER root

WORKDIR /ragflow

# install dependencies from uv.lock file
COPY pyproject.toml uv.lock ./

RUN if [ "$NEED_MIRROR" == "1" ]; then \
        sed -i 's|pypi.org|mirrors.aliyun.com/pypi|g' uv.lock; \
    else \
        sed -i 's|mirrors.aliyun.com/pypi|pypi.org|g' uv.lock; \
    fi; \
    if [ "$LIGHTEN" == "1" ]; then \
        uv sync --python 3.10 --frozen; \
    else \
        uv sync --python 3.10 --frozen --all-extras; \
    fi

COPY web web
COPY docs docs
RUN cd web && npm install && npm run build

COPY .git /ragflow/.git

RUN version_info=$(git describe --tags --match=v* --first-parent --always); \
    if [ "$LIGHTEN" == "1" ]; then \
        version_info="$version_info slim"; \
    else \
        version_info="$version_info full"; \
    fi; \
    echo "RAGFlow version: $version_info"; \
    echo $version_info > /ragflow/VERSION

# production stage
FROM base AS production
USER root

WORKDIR /ragflow

# Copy Python environment and packages
ENV VIRTUAL_ENV=/ragflow/.venv
COPY --from=builder ${VIRTUAL_ENV} ${VIRTUAL_ENV}
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"

ENV PYTHONPATH=/ragflow/

COPY web web
COPY api api
COPY conf conf
COPY deepdoc deepdoc
COPY rag rag
COPY agent agent
COPY graphrag graphrag
COPY agentic_reasoning agentic_reasoning
COPY pyproject.toml uv.lock ./
COPY mcp mcp
COPY plugin plugin

COPY docker/service_conf.yaml.template ./conf/service_conf.yaml.template
COPY docker/entrypoint.sh ./
RUN chmod +x ./entrypoint*.sh

# Copy compiled web pages
COPY --from=builder /ragflow/web/dist /ragflow/web/dist

COPY --from=builder /ragflow/VERSION /ragflow/VERSION
ENTRYPOINT ["./entrypoint.sh"]