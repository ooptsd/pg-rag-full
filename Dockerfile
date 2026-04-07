# ============================================================
# Stage 1: Build Stage - Compile Apache AGE extension
# ============================================================
# pg-rag-full 项目：基于 ParadeDB 构建，编译 Apache AGE 扩展
# 使用与 ParadeDB 相同的 base image 来编译 AGE，确保 glibc 兼容
FROM paradedb/paradedb:latest-pg18 AS builder

ENV DEBIAN_FRONTEND=noninteractive

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

# Download and build Apache AGE from source
RUN curl -L https://github.com/apache/age/archive/refs/heads/master.zip -o /tmp/age.zip && \
    unzip -q /tmp/age.zip -d /tmp/ && \
    cd /tmp/age-master && \
    make PG_CONFIG=/usr/lib/postgresql/18/bin/pg_config && \
    make PG_CONFIG=/usr/lib/postgresql/18/bin/pg_config install && \
    rm -rf /tmp/age /tmp/age.zip

# ============================================================
# Stage 2: Final Stage - Runtime image
# ============================================================
FROM paradedb/paradedb:latest-pg18

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
