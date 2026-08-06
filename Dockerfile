# ============================================================
# Stage 1: Build Stage - Compile Apache AGE extension
# ============================================================
# pg-rag-full 项目：基于 ParadeDB 构建，编译 Apache AGE 扩展
# 使用与 ParadeDB 相同的 base image 来编译 AGE，确保 glibc 兼容
#
# 多架构支持：通过 --platform 参数 + TARGETARCH 自适应
#   docker buildx build --platform linux/arm64 ...  → ARM 镜像（麒麟 Kunpeng-920）
#   docker buildx build --platform linux/amd64 ...  → x86 镜像
#
# ARM64 编译标志（仅 arm64 构建时自动启用）：
#   -march=armv8-a+crc     只用 ARMv8 基础 + CRC，必兼容所有 ARMv8 CPU
#   -mtune=generic         不为特定微架构调优
#   防止 macOS Apple Silicon 交叉构建时引入 Apple 私有扩展指令导致 SIGILL
# ============================================================
ARG TARGETARCH
FROM --platform=linux/$TARGETARCH paradedb/paradedb:latest-pg18 AS builder

ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive

# 编译器标志在下方 make 步骤中根据 TARGETARCH 动态设置
# ARM64 → -march=armv8-a+crc 防 SIGILL；AMD64 → 默认优化

# Install build dependencies for Apache AGE
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    libreadline-dev \
    zlib1g-dev \
    flex \
    bison \
    curl \
    ca-certificates \
    unzip \
    postgresql-server-dev-18 && \
    rm -rf /var/lib/apt/lists/*

# AGE 源码：使用 Apache AGE 官方 PG18 端口
# 本地 zip（age-pg18.zip）可选，缺则下载官方 PG18 tag
# 重要：必须用 PG18/v1.7.0-rc0 或更新的 PG18 兼容版本，
#       旧版 1.5.0 master 不兼容 PostgreSQL 18（缺少 ExecInitExtraTupleSlot 等新 API）
COPY age-pg18.zip* /tmp/age.zip
RUN set -eux; \
    if [ -s /tmp/age.zip ]; then \
        echo "Using local age-pg18.zip"; \
        unzip -q /tmp/age.zip -d /tmp/; \
        AGE_DIR=$(ls -d /tmp/age* 2>/dev/null | head -1); \
        cd "$AGE_DIR"; \
    else \
        echo "Downloading AGE PG18/v1.7.0-rc0 from GitHub (Apache 官方 PG18 端口)"; \
        curl -L https://github.com/apache/age/archive/refs/tags/PG18/v1.7.0-rc0.zip -o /tmp/age.zip; \
        unzip -q /tmp/age.zip -d /tmp/; \
        cd /tmp/age-PG18-v1.7.0-rc0; \
    fi && \
    echo "Building AGE for TARGETARCH=$TARGETARCH" && \
    if [ "$TARGETARCH" = "arm64" ]; then \
        export CFLAGS="-march=armv8-a+crc -mtune=generic -O2 -fno-stack-protector"; \
        export CXXFLAGS="-march=armv8-a+crc -mtune=generic -O2 -fno-stack-protector"; \
        export RUSTFLAGS="-C target-feature=+crc -C target-cpu=generic"; \
        export PG_CFLAGS="-march=armv8-a+crc -mtune=generic -O2"; \
    fi && \
    make PG_CONFIG=/usr/lib/postgresql/18/bin/pg_config && \
    make PG_CONFIG=/usr/lib/postgresql/18/bin/pg_config install && \
    rm -rf /tmp/age /tmp/age.zip /tmp/age-*

# ============================================================
# Stage 2: Final Stage - Runtime image
# ============================================================
ARG TARGETARCH
FROM --platform=linux/$TARGETARCH paradedb/paradedb:latest-pg18

ENV DEBIAN_FRONTEND=noninteractive

# Copy compiled AGE extension from build stage
COPY --from=builder /usr/lib/postgresql/18/lib/age.so /usr/lib/postgresql/18/lib/
COPY --from=builder /usr/share/postgresql/18/extension/age.control /usr/share/postgresql/18/extension/
COPY --from=builder /usr/share/postgresql/18/extension/age--*.sql /usr/share/postgresql/18/extension/

# Note: ParadeDB already includes:
# - pg_search (full-text search using BM25, 内置 jieba 分词器)
# - pgvector (vector similarity search)
# - pg_cron (job scheduler)
# - pg_ivm (incremental view maintenance)
# - PostGIS

# Configure PostgreSQL to load AGE extension
# ParadeDB already has shared_preload_libraries set for pg_search, pg_cron, pg_stat_statements
# We need to add age.so to the list
RUN sed -i "s/shared_preload_libraries = 'pg_search,pg_cron,pg_stat_statements'/shared_preload_libraries = 'pg_search,pg_cron,pg_stat_statements,age'/" /usr/share/postgresql/postgresql.conf.sample

# The base image paradedb/paradedb already has CMD/ENTRYPOINT for PostgreSQL

# Copy core initialization SQL and set appropriate permissions
COPY --chmod=644 init.sql /docker-entrypoint-initdb.d/00-core-init.sql
