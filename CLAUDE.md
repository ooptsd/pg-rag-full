# CLAUDE.md

本文件为 Claude (或任何 AI 编程助手) 在此仓库中工作时提供全局指引。

## 语言规则
- **绝对要求**：与用户交流时**只使用中文**。
- 包括代码注释、commit message、PR 描述等在内的所有输出均使用中文。
- 绝不要输出英文或中英双语内容。

## 项目概述
`pg-rag-full` 是一个一站式 AI 多模态数据库环境，基于 ParadeDB (PostgreSQL 18) 构建。它将向量搜索 (pgvector)、BM25 全文检索 (内置 pdb.jieba 分词) 和图数据库能力 (Apache AGE) 整合到单个容器中。主要面向 RAG 管线、混合检索、知识图谱等 AI 应用场景。

## 重要技术规范与上下文 (防呆指南)
1. **纯中文分词原则**:
   - 项目**已经完全弃用并移除了**独立的 `pg_jieba` C扩展。
   - 现在**必须**使用 ParadeDB 内置的 `pdb.jieba` 分词器。
   - 示例用法：索引创建或查询时使用强制类型转换 `content::pdb.jieba`，例如 `USING bm25 (id, (content::pdb.jieba))`。
2. **多模态环境构成**:
   - ParadeDB 提供 `pg_search` (BM25全文检索，通过 `|||`, `&&&` 操作符)。
   - `pgvector` 提供向量检索 (通过 `<->`, `<=>` 距离操作符)。
   - `Apache AGE` 提供图数据库支持 (通过 `ag_catalog.cypher()` 函数)。
3. **架构与构建说明**:
   - `Dockerfile` 是多阶段构建，从源码构建了 AGE (并复制了 `.so` 和 `.sql` 到底包中)。
   - `shared_preload_libraries` 已在 Dockerfile 和 `docker-compose.yml` 中配置包含 `age,pg_search,pg_cron,pg_stat_statements` (以 compose 中的 command 为准)。
   - 容器初始化脚本 `init.sql` 仅在首次启动 (无挂载数据时) 执行，负责创建所需扩展并配置示例图。若需重新执行该脚本，用户必须用 `docker compose down -v` 清除旧卷。
   - `docker-compose.yml` 中容器名称设置为 `pg-rag-full-postgres`。
