#!/bin/bash
set -euo pipefail

# Predictive Maintenance DB bootstrap (schema + seed)
# - Idempotent (CREATE TABLE IF NOT EXISTS, INSERT IGNORE)
# - Designed for preview-ready realistic data and full end-to-end flow
#
# Usage:
#   ./startup.sh
#   ./init_predictive_maintenance.sql.sh
#
# Notes:
# - This script intentionally uses single-line SQL statements executed via `mysql -e`
#   to match container operational constraints.

DB_NAME="myapp"
DB_USER="appuser"
DB_PASSWORD="dbuser123"
DB_PORT="5000"
DB_HOST="localhost"

MYSQL_CMD=(mysql -u "${DB_USER}" -p"${DB_PASSWORD}" -h "${DB_HOST}" -P "${DB_PORT}" "${DB_NAME}" -e)

echo "== Predictive Maintenance DB Init =="
echo "Connecting to MySQL ${DB_HOST}:${DB_PORT}/${DB_NAME} as ${DB_USER} ..."

"${MYSQL_CMD[@]}" "SELECT 1" >/dev/null

echo "Creating tables..."

# Master data: plant / areas
"${MYSQL_CMD[@]}" "CREATE TABLE IF NOT EXISTS plants (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, name VARCHAR(120) NOT NULL, code VARCHAR(40) NOT NULL UNIQUE, timezone VARCHAR(64) NOT NULL DEFAULT 'UTC', created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"
"${MYSQL_CMD[@]}" "CREATE TABLE IF NOT EXISTS areas (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, plant_id BIGINT UNSIGNED NOT NULL, name VARCHAR(120) NOT NULL, code VARCHAR(40) NOT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, UNIQUE KEY uq_area (plant_id, code), CONSTRAINT fk_areas_plant FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"

# Equipment registry
"${MYSQL_CMD[@]}" "CREATE TABLE IF NOT EXISTS equipment (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, plant_id BIGINT UNSIGNED NOT NULL, area_id BIGINT UNSIGNED NULL, asset_tag VARCHAR(64) NOT NULL UNIQUE, name VARCHAR(160) NOT NULL, equipment_type VARCHAR(80) NOT NULL, manufacturer VARCHAR(120) NULL, model VARCHAR(120) NULL, serial_number VARCHAR(120) NULL, criticality ENUM('LOW','MEDIUM','HIGH','CRITICAL') NOT NULL DEFAULT 'MEDIUM', status ENUM('ACTIVE','INACTIVE','DECOMMISSIONED') NOT NULL DEFAULT 'ACTIVE', install_date DATE NULL, last_service_date DATE NULL, notes TEXT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, CONSTRAINT fk_equipment_plant FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE RESTRICT, CONSTRAINT fk_equipment_area FOREIGN KEY (area_id) REFERENCES areas(id) ON DELETE SET NULL, INDEX idx_equipment_plant (plant_id), INDEX idx_equipment_area (area_id), INDEX idx_equipment_type (equipment_type), INDEX idx_equipment_status (status)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"
"${MYSQL_CMD[@]}" "CREATE TABLE IF NOT EXISTS equipment_components (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, equipment_id BIGINT UNSIGNED NOT NULL, name VARCHAR(160) NOT NULL, component_type VARCHAR(80) NOT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, UNIQUE KEY uq_component (equipment_id, name), CONSTRAINT fk_components_equipment FOREIGN KEY (equipment_id) REFERENCES equipment(id) ON DELETE CASCADE, INDEX idx_components_equipment (equipment_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"

# Parameters / thresholds
"${MYSQL_CMD[@]}" "CREATE TABLE IF NOT EXISTS parameter_catalog (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, name VARCHAR(120) NOT NULL UNIQUE, unit VARCHAR(32) NULL, description VARCHAR(255) NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"
"${MYSQL_CMD[@]}" "CREATE TABLE IF NOT EXISTS equipment_parameters (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, equipment_id BIGINT UNSIGNED NOT NULL, component_id BIGINT UNSIGNED NULL, parameter_id BIGINT UNSIGNED NOT NULL, source ENUM('SENSOR','OPERATOR') NOT NULL DEFAULT 'SENSOR', is_enabled TINYINT(1) NOT NULL DEFAULT 1, warn_low DECIMAL(14,4) NULL, warn_high DECIMAL(14,4) NULL, alarm_low DECIMAL(14,4) NULL, alarm_high DECIMAL(14,4) NULL, expected_low DECIMAL(14,4) NULL, expected_high DECIMAL(14,4) NULL, sample_interval_seconds INT UNSIGNED NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, UNIQUE KEY uq_equipment_param (equipment_id, component_id, parameter_id), CONSTRAINT fk_eqparam_equipment FOREIGN KEY (equipment_id) REFERENCES equipment(id) ON DELETE CASCADE, CONSTRAINT fk_eqparam_component FOREIGN KEY (component_id) REFERENCES equipment_components(id) ON DELETE SET NULL, CONSTRAINT fk_eqparam_parameter FOREIGN KEY (parameter_id) REFERENCES parameter_catalog(id) ON DELETE RESTRICT, INDEX idx_eqparam_equipment (equipment_id), INDEX idx_eqparam_parameter (parameter_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"

# Readings/logs
"${MYSQL_CMD[@]}" "CREATE TABLE IF NOT EXISTS equipment_readings (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, equipment_id BIGINT UNSIGNED NOT NULL, component_id BIGINT UNSIGNED NULL, parameter_id BIGINT UNSIGNED NOT NULL, recorded_at DATETIME(3) NOT NULL, value DECIMAL(14,4) NOT NULL, source ENUM('SENSOR','OPERATOR') NOT NULL DEFAULT 'SENSOR', recorded_by VARCHAR(120) NULL, note VARCHAR(255) NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, CONSTRAINT fk_readings_equipment FOREIGN KEY (equipment_id) REFERENCES equipment(id) ON DELETE CASCADE, CONSTRAINT fk_readings_component FOREIGN KEY (component_id) REFERENCES equipment_components(id) ON DELETE SET NULL, CONSTRAINT fk_readings_parameter FOREIGN KEY (parameter_id) REFERENCES parameter_catalog(id) ON DELETE RESTRICT, INDEX idx_readings_equipment_time (equipment_id, recorded_at), INDEX idx_readings_param_time (parameter_id, recorded_at), INDEX idx_readings_component (component_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"

# Alerts
"${MYSQL_CMD[@]}" "CREATE TABLE IF NOT EXISTS alerts (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, equipment_id BIGINT UNSIGNED NOT NULL, component_id BIGINT UNSIGNED NULL, parameter_id BIGINT UNSIGNED NOT NULL, reading_id BIGINT UNSIGNED NULL, alert_type ENUM('WARN','ALARM') NOT NULL, severity ENUM('LOW','MEDIUM','HIGH','CRITICAL') NOT NULL, status ENUM('OPEN','ACKNOWLEDGED','IN_PROGRESS','RESOLVED','DISMISSED') NOT NULL DEFAULT 'OPEN', title VARCHAR(200) NOT NULL, description TEXT NULL, detected_at DATETIME(3) NOT NULL, acknowledged_at DATETIME(3) NULL, acknowledged_by VARCHAR(120) NULL, resolved_at DATETIME(3) NULL, resolved_by VARCHAR(120) NULL, resolution_note TEXT NULL, priority_score INT UNSIGNED NOT NULL DEFAULT 0, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, CONSTRAINT fk_alerts_equipment FOREIGN KEY (equipment_id) REFERENCES equipment(id) ON DELETE CASCADE, CONSTRAINT fk_alerts_component FOREIGN KEY (component_id) REFERENCES equipment_components(id) ON DELETE SET NULL, CONSTRAINT fk_alerts_parameter FOREIGN KEY (parameter_id) REFERENCES parameter_catalog(id) ON DELETE RESTRICT, CONSTRAINT fk_alerts_reading FOREIGN KEY (reading_id) REFERENCES equipment_readings(id) ON DELETE SET NULL, INDEX idx_alerts_status (status), INDEX idx_alerts_equipment_time (equipment_id, detected_at), INDEX idx_alerts_severity (severity)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"

# Work orders
"${MYSQL_CMD[@]}" "CREATE TABLE IF NOT EXISTS work_orders (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, alert_id BIGINT UNSIGNED NULL, equipment_id BIGINT UNSIGNED NOT NULL, wo_number VARCHAR(40) NOT NULL UNIQUE, title VARCHAR(200) NOT NULL, description TEXT NULL, priority ENUM('LOW','MEDIUM','HIGH','CRITICAL') NOT NULL DEFAULT 'MEDIUM', status ENUM('DRAFT','OPEN','ASSIGNED','IN_PROGRESS','WAITING_PARTS','COMPLETED','CANCELLED') NOT NULL DEFAULT 'OPEN', requested_by VARCHAR(120) NULL, assigned_to VARCHAR(120) NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, due_date DATE NULL, started_at DATETIME(3) NULL, completed_at DATETIME(3) NULL, completion_note TEXT NULL, CONSTRAINT fk_wo_alert FOREIGN KEY (alert_id) REFERENCES alerts(id) ON DELETE SET NULL, CONSTRAINT fk_wo_equipment FOREIGN KEY (equipment_id) REFERENCES equipment(id) ON DELETE CASCADE, INDEX idx_wo_status (status), INDEX idx_wo_priority (priority), INDEX idx_wo_equipment (equipment_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"

# Parts inventory
"${MYSQL_CMD[@]}" "CREATE TABLE IF NOT EXISTS parts (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, part_number VARCHAR(64) NOT NULL UNIQUE, name VARCHAR(160) NOT NULL, description VARCHAR(255) NULL, unit_cost DECIMAL(12,2) NULL, stock_qty INT NOT NULL DEFAULT 0, reorder_point INT NOT NULL DEFAULT 0, supplier VARCHAR(160) NULL, lead_time_days INT UNSIGNED NULL, location VARCHAR(80) NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, INDEX idx_parts_stock (stock_qty), INDEX idx_parts_reorder (reorder_point)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"
"${MYSQL_CMD[@]}" "CREATE TABLE IF NOT EXISTS work_order_parts (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, work_order_id BIGINT UNSIGNED NOT NULL, part_id BIGINT UNSIGNED NOT NULL, qty_required INT NOT NULL DEFAULT 1, qty_reserved INT NOT NULL DEFAULT 0, status ENUM('REQUIRED','RESERVED','ISSUED','BACKORDERED') NOT NULL DEFAULT 'REQUIRED', note VARCHAR(255) NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, UNIQUE KEY uq_wo_part (work_order_id, part_id), CONSTRAINT fk_wop_wo FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE CASCADE, CONSTRAINT fk_wop_part FOREIGN KEY (part_id) REFERENCES parts(id) ON DELETE RESTRICT, INDEX idx_wop_wo (work_order_id), INDEX idx_wop_part (part_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"

# Audit trail
"${MYSQL_CMD[@]}" "CREATE TABLE IF NOT EXISTS audit_events (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, entity_type VARCHAR(60) NOT NULL, entity_id BIGINT UNSIGNED NULL, action VARCHAR(60) NOT NULL, actor VARCHAR(120) NULL, details JSON NULL, occurred_at DATETIME(3) NOT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, INDEX idx_audit_entity (entity_type, entity_id), INDEX idx_audit_time (occurred_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"

# Migration tracking
"${MYSQL_CMD[@]}" "CREATE TABLE IF NOT EXISTS schema_migrations (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, version VARCHAR(64) NOT NULL UNIQUE, applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, note VARCHAR(255) NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"
"${MYSQL_CMD[@]}" "INSERT IGNORE INTO schema_migrations (version, note) VALUES ('2026-03-26_init_predictive_maintenance_v1','Initial schema for equipment, parameters, readings, alerts, work orders, parts, audit')"

echo "Seeding data..."

# Plants / areas
"${MYSQL_CMD[@]}" "INSERT IGNORE INTO plants (id,name,code,timezone) VALUES (1,'Bluewater Manufacturing','BWM','America/Chicago')"
"${MYSQL_CMD[@]}" "INSERT IGNORE INTO areas (id,plant_id,name,code) VALUES (1,1,'Packaging Line','PKG'),(2,1,'Utilities','UTIL'),(3,1,'Mixing Line','MIX')"

# Equipment
"${MYSQL_CMD[@]}" "INSERT IGNORE INTO equipment (id,plant_id,area_id,asset_tag,name,equipment_type,manufacturer,model,serial_number,criticality,status,install_date,last_service_date,notes) VALUES (1,1,1,'PKG-CNV-01','Case Conveyor 01','Conveyor','Interroll','RM 8320','CNV-19022','HIGH','ACTIVE','2022-04-14','2026-02-10','Primary case conveyor feeding palletizer'),(2,1,1,'PKG-PLT-01','Palletizer 01','Palletizer','ABB','IRB 660','PLT-77120','CRITICAL','ACTIVE','2021-11-01','2026-01-25','Robotic palletizer - high downtime impact'),(3,1,2,'UTIL-CHLR-01','Chiller 01','Chiller','Trane','CGAM','CHLR-45810','HIGH','ACTIVE','2020-06-30','2026-03-05','Plant process water chiller'),(4,1,3,'MIX-PMP-02','Transfer Pump 02','Pump','Grundfos','CR 32','PMP-20339','MEDIUM','ACTIVE','2023-02-18','2026-02-28','Transfers slurry to holding tank')"
"${MYSQL_CMD[@]}" "INSERT IGNORE INTO equipment_components (id,equipment_id,name,component_type) VALUES (1,1,'Drive Motor','Motor'),(2,1,'Gearbox','Gearbox'),(3,2,'Robot Arm','Robot'),(4,2,'Hydraulic Unit','Hydraulics'),(5,3,'Compressor','Compressor'),(6,3,'Evaporator','HeatExchanger'),(7,4,'Bearing A','Bearing'),(8,4,'Seal','Seal')"

# Parameter catalog + thresholds
"${MYSQL_CMD[@]}" "INSERT IGNORE INTO parameter_catalog (id,name,unit,description) VALUES (1,'Vibration RMS','mm/s','Overall vibration velocity RMS'),(2,'Temperature','°C','Surface/ambient temperature'),(3,'Motor Current','A','Motor current draw'),(4,'Oil Pressure','bar','Hydraulic/lube oil pressure'),(5,'Flow Rate','L/min','Process flow rate'),(6,'Noise Level','dB','Acoustic noise level')"
"${MYSQL_CMD[@]}" "INSERT IGNORE INTO equipment_parameters (id,equipment_id,component_id,parameter_id,source,is_enabled,warn_high,alarm_high,expected_low,expected_high,sample_interval_seconds) VALUES (1,1,1,1,'SENSOR',1,6.5000,9.5000,0.5000,5.5000,300),(2,1,1,2,'SENSOR',1,65.0000,80.0000,20.0000,60.0000,300),(3,1,1,3,'SENSOR',1,18.0000,24.0000,5.0000,16.0000,300),(4,2,3,2,'SENSOR',1,60.0000,75.0000,18.0000,55.0000,300),(5,2,4,4,'SENSOR',1,NULL,NULL,8.0000,14.0000,600),(6,3,5,2,'SENSOR',1,70.0000,85.0000,15.0000,65.0000,300),(7,3,5,1,'SENSOR',1,5.5000,8.0000,0.5000,4.5000,300),(8,4,7,1,'SENSOR',1,7.0000,10.5000,0.5000,6.0000,300),(9,4,8,5,'SENSOR',1,NULL,NULL,40.0000,65.0000,600)"

# Parts
"${MYSQL_CMD[@]}" "INSERT IGNORE INTO parts (id,part_number,name,description,unit_cost,stock_qty,reorder_point,supplier,lead_time_days,location) VALUES (1,'BRG-6205-2RS','Bearing 6205-2RS','Sealed ball bearing for pump/conveyor',18.50,4,2,'Motion Industries',3,'Crib A-12'),(2,'V-BELT-A42','V-Belt A42','Conveyor drive belt',9.25,0,2,'Grainger',2,'Crib B-03'),(3,'OIL-ISO46-20L','Hydraulic Oil ISO VG46 20L','Hydraulic/lube oil',72.00,6,2,'Shell',5,'Chem 01'),(4,'SEAL-KIT-PMP','Pump Seal Kit','Mechanical seal kit for transfer pump',140.00,1,1,'Grundfos',7,'Crib A-02'),(5,'TEMP-SENSOR-PT100','PT100 Temperature Sensor','RTD sensor replacement',34.00,8,3,'Omega',4,'Electronics 02')"

# Readings (include warn/alarm breaches)
"${MYSQL_CMD[@]}" "INSERT IGNORE INTO equipment_readings (id,equipment_id,component_id,parameter_id,recorded_at,value,source,recorded_by,note) VALUES (1,1,1,1,DATE_SUB(NOW(3), INTERVAL 55 MINUTE),4.2000,'SENSOR',NULL,'Normal vibration'),(2,1,1,1,DATE_SUB(NOW(3), INTERVAL 30 MINUTE),7.2000,'SENSOR',NULL,'Warn breach vibration'),(3,1,1,2,DATE_SUB(NOW(3), INTERVAL 30 MINUTE),67.5000,'SENSOR',NULL,'Motor running hot'),(4,2,3,2,DATE_SUB(NOW(3), INTERVAL 20 MINUTE),78.2000,'SENSOR',NULL,'Alarm breach temp'),(5,3,5,1,DATE_SUB(NOW(3), INTERVAL 25 MINUTE),8.4000,'SENSOR',NULL,'Alarm breach vibration'),(6,4,7,1,DATE_SUB(NOW(3), INTERVAL 15 MINUTE),7.6000,'SENSOR',NULL,'Warn breach bearing vibration'),(7,4,8,5,DATE_SUB(NOW(3), INTERVAL 10 MINUTE),38.5000,'SENSOR',NULL,'Flow slightly low'),(8,1,1,3,DATE_SUB(NOW(3), INTERVAL 12 MINUTE),26.5000,'SENSOR',NULL,'Alarm breach current')"

# Alerts (various lifecycle states)
"${MYSQL_CMD[@]}" "INSERT IGNORE INTO alerts (id,equipment_id,component_id,parameter_id,reading_id,alert_type,severity,status,title,description,detected_at,priority_score,acknowledged_at,acknowledged_by) VALUES (1,1,1,1,2,'WARN','MEDIUM','OPEN','Conveyor vibration elevated','Vibration RMS exceeded warning threshold. Inspect motor mounts and gearbox alignment.',DATE_SUB(NOW(3), INTERVAL 30 MINUTE),55,NULL,NULL),(2,2,3,2,4,'ALARM','CRITICAL','ACKNOWLEDGED','Palletizer temperature critical','Robot arm temperature exceeded alarm threshold. Risk of unplanned stop.',DATE_SUB(NOW(3), INTERVAL 20 MINUTE),92,DATE_SUB(NOW(3), INTERVAL 15 MINUTE),'j.smith'),(3,3,5,1,5,'ALARM','HIGH','IN_PROGRESS','Chiller compressor vibration high','Compressor vibration exceeded alarm threshold. Check bearings and balance.',DATE_SUB(NOW(3), INTERVAL 25 MINUTE),80,DATE_SUB(NOW(3), INTERVAL 22 MINUTE),'a.patel'),(4,1,1,3,8,'ALARM','HIGH','OPEN','Conveyor motor current spike','Motor current draw exceeded alarm threshold. Possible mechanical binding.',DATE_SUB(NOW(3), INTERVAL 12 MINUTE),78,NULL,NULL)"

# Work orders
"${MYSQL_CMD[@]}" "INSERT IGNORE INTO work_orders (id,alert_id,equipment_id,wo_number,title,description,priority,status,requested_by,assigned_to,due_date,started_at) VALUES (1,2,2,'WO-2026-0001','Inspect palletizer overheating','Investigate robot arm temperature alarm; verify cooling, lubrication, and duty cycle.', 'CRITICAL','ASSIGNED','system','j.smith',DATE_ADD(CURDATE(), INTERVAL 1 DAY),DATE_SUB(NOW(3), INTERVAL 10 MINUTE)),(2,3,3,'WO-2026-0002','Chiller compressor vibration remediation','Inspect compressor bearings; check alignment and perform vibration analysis.', 'HIGH','IN_PROGRESS','a.patel','a.patel',DATE_ADD(CURDATE(), INTERVAL 2 DAY),DATE_SUB(NOW(3), INTERVAL 18 MINUTE)),(3,NULL,1,'WO-2026-0003','Conveyor preventive check','Routine inspection of conveyor motor and belt; replace worn components as needed.', 'MEDIUM','OPEN','planner',NULL,DATE_ADD(CURDATE(), INTERVAL 7 DAY),NULL)"

# Work order parts: reserved + backordered examples
"${MYSQL_CMD[@]}" "INSERT IGNORE INTO work_order_parts (id,work_order_id,part_id,qty_required,qty_reserved,status,note) VALUES (1,1,5,1,1,'RESERVED','Sensor swap if needed'),(2,1,3,1,0,'REQUIRED','Top-up oil after inspection'),(3,2,1,2,0,'BACKORDERED','Bearing stock low - expedite'),(4,2,4,1,0,'REQUIRED','Seal kit may be needed'),(5,3,2,1,0,'BACKORDERED','Belt currently out of stock')"

# Audit events
"${MYSQL_CMD[@]}" "INSERT IGNORE INTO audit_events (id,entity_type,entity_id,action,actor,details,occurred_at) VALUES (1,'ALERT',2,'ACKNOWLEDGE','j.smith',JSON_OBJECT('note','Acknowledged on shift start'),DATE_SUB(NOW(3), INTERVAL 15 MINUTE)),(2,'WORK_ORDER',1,'ASSIGN','system',JSON_OBJECT('assigned_to','j.smith'),DATE_SUB(NOW(3), INTERVAL 14 MINUTE)),(3,'WORK_ORDER',2,'START','a.patel',JSON_OBJECT('started_at',DATE_FORMAT(DATE_SUB(NOW(3), INTERVAL 18 MINUTE),'%Y-%m-%dT%H:%i:%s.%fZ')),DATE_SUB(NOW(3), INTERVAL 18 MINUTE)),(4,'EQUIPMENT_PARAMETER',1,'UPDATE_THRESHOLDS','planner',JSON_OBJECT('warn_high',6.5,'alarm_high',9.5),DATE_SUB(NOW(3), INTERVAL 10 DAY))"

echo "Done. Current tables:"
"${MYSQL_CMD[@]}" "SELECT table_name FROM information_schema.tables WHERE table_schema='${DB_NAME}' ORDER BY table_name"
