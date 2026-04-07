-- 创建必要的扩展
CREATE EXTENSION IF NOT EXISTS vector;
-- pg_jieba 已移除，使用 ParadeDB 内置的 pg_search 进行中文全文搜索
CREATE EXTENSION IF NOT EXISTS age;

-- pg_search 依赖的扩展 (ParadeDB 已包含 pg_search)
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;

-- 加载AGE扩展并设置搜索路径
LOAD 'age';
SET search_path = ag_catalog, "$user", public;

-- ============================================================
-- 使用 ParadeDB pg_search 进行中文全文搜索
-- ParadeDB 内置的 BM25 算法，无需额外配置
-- ============================================================

-- 创建示例图数据库
SELECT create_graph('sample_graph');

-- ============================================================
-- 验证扩展已正确加载
-- ============================================================
SELECT 'Extensions loaded successfully' AS status;
