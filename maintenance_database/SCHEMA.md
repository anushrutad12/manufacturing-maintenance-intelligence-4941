# Predictive Maintenance MySQL Schema (maintenance_database)

This database supports an end-to-end predictive maintenance workflow:

**Equipment registry → thresholds → readings/logs → alerts → work orders → parts availability → audit trail**

## How to initialize

1) Start MySQL (if not already running):
- `./startup.sh`

2) Create schema + seed realistic preview data:
- `bash ./init_predictive_maintenance.sql.sh`

> The init script is idempotent: it uses `CREATE TABLE IF NOT EXISTS` and `INSERT IGNORE`.

## Tables

### Master data
- `plants`: sites/plants
- `areas`: sub-areas/lines within a plant

### Equipment registry
- `equipment`: equipment/assets
- `equipment_components`: components/subsystems for equipment (motor, bearing, compressor, etc.)

### Parameters & thresholds
- `parameter_catalog`: standard parameters (e.g., temperature, vibration)
- `equipment_parameters`: per-equipment/component thresholds (warn/alarm/expected ranges)

### Logs / readings
- `equipment_readings`: time-series readings (sensor or operator-entered)

### Alerting
- `alerts`: threshold breach events and their lifecycle (open → acknowledged → in progress → resolved)

### Work orders
- `work_orders`: maintenance work execution (may be linked to an alert)

### Parts inventory
- `parts`: stock/reorder data
- `work_order_parts`: required/reserved/backordered parts per work order

### Audit trail
- `audit_events`: JSON-based event log (who did what, when) for traceability

### Migrations
- `schema_migrations`: simple version tracking for applied schema versions
