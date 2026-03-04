# Metabase — Create Questions & Dashboards

Create Metabase questions (cards) and dashboards programmatically via direct MySQL access to the Metabase internal database.

**Instance:** https://data.12min.com (dashboard `29` = Search Analytics, as reference)

---

## Setup

### 1. Get credentials from Kubernetes

```bash
kubectl get secret metabase-database -o jsonpath='{.data.username}' | base64 -d
kubectl get secret metabase-database -o jsonpath='{.data.password}' | base64 -d
```

### 2. Start Cloud SQL proxy for MySQL (port 3307)

```bash
~/cloud-sql-proxy -p 3307 -c ~/db-access.json min-b302a:us-central1:mysql-database-instance &
sleep 3
```

### 3. Check proxy is up

```bash
nc -z 127.0.0.1 3307 && echo "proxy up" || echo "proxy down"
```

### 4. Connect

```bash
METABASE_USER=$(kubectl get secret metabase-database -o jsonpath='{.data.username}' | base64 -d)
METABASE_PASS=$(kubectl get secret metabase-database -o jsonpath='{.data.password}' | base64 -d)

/opt/homebrew/opt/mysql-client/bin/mysql \
  -h 127.0.0.1 -P 3307 \
  -u "$METABASE_USER" -p"$METABASE_PASS" \
  12min_metabase
```

> If `mysql` not found: `brew install mysql-client` and use `/opt/homebrew/opt/mysql-client/bin/mysql`

---

## Key Reference IDs

### Databases (`metabase_database`)

| id | name | engine |
|----|------|--------|
| 2 | TwelveMin ebdb - Replica Production | postgres |
| 3 | Twelvelytics - BQ Production | bigquery-cloud-sdk |
| 5 | Billing - Postgres Production | postgres |
| 6 | Twelvemin ebdb - BigQuery | bigquery-cloud-sdk |

### Collections (`collection`)

| id | name |
|----|------|
| 9  | General |
| 10 | Control Center |
| 11 | ARR |
| 12 | Revenue |
| 14 | Retention |
| 18 | Editorial |
| 27 | Playground |

### Creator user IDs (`core_user`)

```sql
SELECT id, email FROM core_user WHERE is_active = 1;
```

---

## Creating a Question (Card)

```sql
INSERT INTO report_card (
  created_at, updated_at,
  name, description,
  display,            -- 'line', 'bar', 'table', 'scalar', 'pie'
  dataset_query,      -- JSON (see format below)
  visualization_settings, -- JSON
  creator_id,         -- user id from core_user
  database_id,        -- id from metabase_database
  query_type,         -- 'native' for raw SQL
  archived,
  collection_id,
  entity_id,          -- unique 21-char string: LEFT(UUID(), 21)
  parameters,
  parameter_mappings,
  collection_preview
) VALUES (
  NOW(), NOW(),
  'My Question Name', 'Optional description',
  'line',
  '{"type":"native","native":{"query":"SELECT ...","template-tags":{}},"database":3}',
  '{"graph.dimensions":["day"],"graph.metrics":["value"]}',
  26,   -- creator_id
  3,    -- database_id (BigQuery)
  'native', 0,
  9,    -- collection_id (General)
  LEFT(UUID(), 21), '[]', '[]', 1
);

SELECT LAST_INSERT_ID() AS card_id;
```

### `dataset_query` format (native SQL)

```json
{
  "type": "native",
  "native": {
    "query": "SELECT DATE(timestamp) AS day, COUNT(*) AS total FROM rudderstack.my_table GROUP BY day",
    "template-tags": {}
  },
  "database": 3
}
```

### `visualization_settings` examples

```json
-- Line/bar chart
{"graph.dimensions": ["day"], "graph.metrics": ["value"], "graph.y_axis.title_text": "Count"}

-- Table
{"table.pivot_column": "name", "table.cell_column": "count"}

-- Scalar (single number)
{}
```

---

## Creating a Dashboard

```sql
INSERT INTO report_dashboard (
  created_at, updated_at,
  name, description,
  creator_id,
  parameters,   -- '[]' or JSON array of filter params
  archived,
  collection_id,
  entity_id,
  auto_apply_filters
) VALUES (
  NOW(), NOW(),
  'My Dashboard', 'Dashboard description.',
  26,   -- creator_id
  '[]',
  0,
  9,    -- collection_id
  LEFT(UUID(), 21),
  1
);

SET @dashboard_id = LAST_INSERT_ID();
SELECT @dashboard_id AS dashboard_id;
```

---

## Adding Cards to a Dashboard

```sql
INSERT INTO report_dashboardcard (
  created_at, updated_at,
  size_x, size_y,   -- width (max 24), height (rows)
  row, col,         -- position in grid (0-based)
  card_id,
  dashboard_id,
  parameter_mappings,
  visualization_settings,
  entity_id
) VALUES (
  NOW(), NOW(),
  24, 6,    -- full-width, 6 rows tall
  0, 0,     -- top-left corner
  CARD_ID,
  @dashboard_id,
  '[]', '{}',
  LEFT(UUID(), 21)
);
```

### Layout grid reference

The grid is **24 columns wide**. Common layouts:

| Layout | size_x | col values |
|--------|--------|------------|
| Full width | 24 | 0 |
| Half / half | 12 | 0 and 12 |
| Third / third / third | 8 | 0, 8, 16 |

Increment `row` by `size_y` for each new row.

---

## Full Example: Dashboard with 2 cards

```sql
-- Card 1
INSERT INTO report_card (created_at, updated_at, name, display, dataset_query, visualization_settings, creator_id, database_id, query_type, archived, collection_id, entity_id, parameters, parameter_mappings, collection_preview)
VALUES (NOW(), NOW(), 'Daily Searches', 'line',
  '{"type":"native","native":{"query":"SELECT DATE(timestamp) AS day, COUNT(*) AS searches FROM rudderstack.search_performed GROUP BY day ORDER BY day","template-tags":{}},"database":3}',
  '{"graph.dimensions":["day"],"graph.metrics":["searches"]}',
  26, 3, 'native', 0, 9, LEFT(UUID(), 21), '[]', '[]', 1);
SET @card1 = LAST_INSERT_ID();

-- Card 2
INSERT INTO report_card (created_at, updated_at, name, display, dataset_query, visualization_settings, creator_id, database_id, query_type, archived, collection_id, entity_id, parameters, parameter_mappings, collection_preview)
VALUES (NOW(), NOW(), 'Zero-Result Rate', 'scalar',
  '{"type":"native","native":{"query":"SELECT ROUND(COUNTIF(is_zero_result) / COUNT(*) * 100, 1) AS rate FROM rudderstack.search_performed WHERE DATE(timestamp) = CURRENT_DATE()","template-tags":{}},"database":3}',
  '{}',
  26, 3, 'native', 0, 9, LEFT(UUID(), 21), '[]', '[]', 1);
SET @card2 = LAST_INSERT_ID();

-- Dashboard
INSERT INTO report_dashboard (created_at, updated_at, name, description, creator_id, parameters, archived, collection_id, entity_id, auto_apply_filters)
VALUES (NOW(), NOW(), 'My Dashboard', 'Auto-created dashboard.', 26, '[]', 0, 9, LEFT(UUID(), 21), 1);
SET @dash = LAST_INSERT_ID();

-- Add cards
INSERT INTO report_dashboardcard (created_at, updated_at, size_x, size_y, row, col, card_id, dashboard_id, parameter_mappings, visualization_settings, entity_id)
VALUES (NOW(), NOW(), 12, 6, 0, 0, @card1, @dash, '[]', '{}', LEFT(UUID(), 21));

INSERT INTO report_dashboardcard (created_at, updated_at, size_x, size_y, row, col, card_id, dashboard_id, parameter_mappings, visualization_settings, entity_id)
VALUES (NOW(), NOW(), 12, 6, 0, 12, @card2, @dash, '[]', '{}', LEFT(UUID(), 21));

SELECT CONCAT('https://data.12min.com/dashboard/', @dash) AS url;
```

---

## Useful queries

```sql
-- List existing dashboards
SELECT id, name, collection_id, created_at FROM report_dashboard WHERE archived = 0 ORDER BY id DESC LIMIT 20;

-- List cards in a dashboard
SELECT rc.id, rc.name, rc.display, rdc.row, rdc.col, rdc.size_x, rdc.size_y
FROM report_dashboardcard rdc
JOIN report_card rc ON rc.id = rdc.card_id
WHERE rdc.dashboard_id = DASHBOARD_ID
ORDER BY rdc.row, rdc.col;

-- Delete a dashboard and its cards
DELETE FROM report_dashboardcard WHERE dashboard_id = DASHBOARD_ID;
DELETE FROM report_dashboard WHERE id = DASHBOARD_ID;

-- Archive a card (soft delete)
UPDATE report_card SET archived = 1 WHERE id = CARD_ID;
```
