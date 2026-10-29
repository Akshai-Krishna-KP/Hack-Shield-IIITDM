-- Hack & Shield Service 1: Northstar Enterprise Portal
-- Synthetic enterprise data for an isolated CTF VM. Do not expose this setup publicly.
-- Apply: sudo mysql < /opt/hackshield/protected/service1_seed.sql
-- Portal compatibility: staff(username, plaintext_password, password_hash, full_name, department, role)

CREATE DATABASE IF NOT EXISTS employees CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE employees;

CREATE TABLE IF NOT EXISTS departments (
  department_id INT PRIMARY KEY AUTO_INCREMENT,
  department_code VARCHAR(12) NOT NULL UNIQUE,
  department_name VARCHAR(80) NOT NULL,
  cost_center VARCHAR(20) NOT NULL UNIQUE,
  location VARCHAR(80) NOT NULL,
  manager_username VARCHAR(64),
  budget_annual DECIMAL(14,2) NOT NULL DEFAULT 0,
  status ENUM('active','restructuring','inactive') NOT NULL DEFAULT 'active',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS staff (
  id INT PRIMARY KEY AUTO_INCREMENT,
  username VARCHAR(64) NOT NULL UNIQUE,
  plaintext_password VARCHAR(128) NOT NULL COMMENT 'Intentionally retained legacy training field',
  password_hash CHAR(64) NOT NULL COMMENT 'SHA-256 demo hash; not suitable for production authentication',
  full_name VARCHAR(128) NOT NULL,
  department VARCHAR(64),
  role VARCHAR(32) NOT NULL DEFAULT 'staff',
  email VARCHAR(160) UNIQUE,
  phone_extension VARCHAR(12),
  manager_id INT NULL,
  employment_type ENUM('full_time','part_time','contractor','intern') NOT NULL DEFAULT 'full_time',
  hire_date DATE,
  salary_band VARCHAR(16),
  office_location VARCHAR(80),
  account_status ENUM('active','leave','suspended','terminated') NOT NULL DEFAULT 'active',
  last_login_at DATETIME NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_staff_department(department), INDEX idx_staff_role(role), INDEX idx_staff_status(account_status),
  CONSTRAINT fk_staff_manager FOREIGN KEY(manager_id) REFERENCES staff(id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS roles (
  role_id INT PRIMARY KEY AUTO_INCREMENT,
  role_code VARCHAR(32) NOT NULL UNIQUE,
  role_name VARCHAR(80) NOT NULL,
  description VARCHAR(255) NOT NULL,
  privilege_tier TINYINT NOT NULL DEFAULT 1,
  is_privileged BOOLEAN NOT NULL DEFAULT FALSE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS staff_role_assignments (
  staff_id INT NOT NULL, role_id INT NOT NULL, assigned_by VARCHAR(64) NOT NULL,
  assigned_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, expires_at DATETIME NULL,
  PRIMARY KEY(staff_id,role_id),
  FOREIGN KEY(staff_id) REFERENCES staff(id) ON DELETE CASCADE,
  FOREIGN KEY(role_id) REFERENCES roles(role_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS projects (
  project_id INT PRIMARY KEY AUTO_INCREMENT, project_code VARCHAR(20) NOT NULL UNIQUE,
  project_name VARCHAR(140) NOT NULL, department_id INT NOT NULL,
  project_manager_username VARCHAR(64) NOT NULL,
  status ENUM('proposed','active','on_hold','completed','cancelled') NOT NULL DEFAULT 'proposed',
  priority ENUM('low','normal','high','critical') NOT NULL DEFAULT 'normal',
  budget DECIMAL(14,2) NOT NULL DEFAULT 0, start_date DATE, target_date DATE, description TEXT,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(department_id) REFERENCES departments(department_id), INDEX idx_projects_status(status)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS assets (
  asset_id INT PRIMARY KEY AUTO_INCREMENT, asset_tag VARCHAR(24) NOT NULL UNIQUE,
  asset_type ENUM('laptop','desktop','server','mobile','network','other') NOT NULL,
  manufacturer VARCHAR(60) NOT NULL, model VARCHAR(100) NOT NULL, serial_number VARCHAR(80) UNIQUE,
  assigned_username VARCHAR(64), department_id INT, location VARCHAR(100) NOT NULL,
  purchase_date DATE, warranty_end DATE,
  asset_status ENUM('in_stock','assigned','repair','retired','lost') NOT NULL DEFAULT 'in_stock',
  purchase_cost DECIMAL(12,2) NOT NULL DEFAULT 0, hostname VARCHAR(80) UNIQUE, notes VARCHAR(255),
  FOREIGN KEY(department_id) REFERENCES departments(department_id),
  INDEX idx_assets_owner(assigned_username), INDEX idx_assets_status(asset_status)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS support_tickets (
  ticket_id BIGINT PRIMARY KEY AUTO_INCREMENT, ticket_ref VARCHAR(20) NOT NULL UNIQUE,
  opened_by VARCHAR(64) NOT NULL, assigned_to VARCHAR(64), department_id INT,
  category ENUM('access','hardware','software','network','security','facilities','other') NOT NULL,
  subject VARCHAR(180) NOT NULL, description TEXT NOT NULL,
  priority ENUM('low','normal','high','urgent') NOT NULL DEFAULT 'normal',
  status ENUM('open','in_progress','waiting','resolved','closed') NOT NULL DEFAULT 'open',
  opened_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, due_at DATETIME, resolved_at DATETIME, internal_notes TEXT,
  FOREIGN KEY(department_id) REFERENCES departments(department_id),
  INDEX idx_tickets_status_priority(status,priority), INDEX idx_tickets_opened_by(opened_by)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS vendors (
  vendor_id INT PRIMARY KEY AUTO_INCREMENT, vendor_code VARCHAR(20) NOT NULL UNIQUE,
  vendor_name VARCHAR(140) NOT NULL, category VARCHAR(80) NOT NULL, contact_name VARCHAR(100),
  contact_email VARCHAR(160), phone VARCHAR(40), payment_terms VARCHAR(80),
  vendor_status ENUM('approved','review','suspended','inactive') NOT NULL DEFAULT 'approved',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS purchase_orders (
  po_id INT PRIMARY KEY AUTO_INCREMENT, po_number VARCHAR(24) NOT NULL UNIQUE,
  vendor_id INT NOT NULL, requested_by VARCHAR(64) NOT NULL, department_id INT NOT NULL,
  approved_by VARCHAR(64), order_date DATE NOT NULL, expected_delivery DATE,
  total_amount DECIMAL(14,2) NOT NULL, currency CHAR(3) NOT NULL DEFAULT 'INR',
  status ENUM('draft','pending','approved','ordered','received','cancelled') NOT NULL DEFAULT 'draft',
  justification VARCHAR(255), FOREIGN KEY(vendor_id) REFERENCES vendors(vendor_id),
  FOREIGN KEY(department_id) REFERENCES departments(department_id), INDEX idx_po_status(status)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS invoices (
  invoice_id INT PRIMARY KEY AUTO_INCREMENT, invoice_number VARCHAR(30) NOT NULL UNIQUE,
  vendor_id INT NOT NULL, po_id INT, invoice_date DATE NOT NULL, due_date DATE NOT NULL,
  amount DECIMAL(14,2) NOT NULL, tax_amount DECIMAL(14,2) NOT NULL DEFAULT 0,
  status ENUM('received','under_review','approved','paid','overdue','disputed') NOT NULL DEFAULT 'received',
  payment_reference VARCHAR(60), FOREIGN KEY(vendor_id) REFERENCES vendors(vendor_id),
  FOREIGN KEY(po_id) REFERENCES purchase_orders(po_id), INDEX idx_invoice_status_due(status,due_date)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS audit_logs (
  audit_id BIGINT PRIMARY KEY AUTO_INCREMENT, event_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  actor_username VARCHAR(64) NOT NULL, event_type VARCHAR(60) NOT NULL, resource_type VARCHAR(60) NOT NULL,
  resource_id VARCHAR(80), source_ip VARCHAR(45), outcome ENUM('success','failure','blocked','review') NOT NULL,
  severity ENUM('info','low','medium','high','critical') NOT NULL DEFAULT 'info', details JSON,
  INDEX idx_audit_time(event_time), INDEX idx_audit_actor_time(actor_username,event_time),
  INDEX idx_audit_severity(severity,outcome)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS access_reviews (
  review_id INT PRIMARY KEY AUTO_INCREMENT, review_ref VARCHAR(24) NOT NULL UNIQUE,
  username VARCHAR(64) NOT NULL, system_name VARCHAR(100) NOT NULL, access_level VARCHAR(80) NOT NULL,
  reviewer_username VARCHAR(64) NOT NULL,
  review_status ENUM('pending','approved','revoke','completed') NOT NULL DEFAULT 'pending',
  reviewed_at DATETIME, notes VARCHAR(255), INDEX idx_access_review_status(review_status)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS app_settings (
  setting_key VARCHAR(100) PRIMARY KEY, setting_value VARCHAR(500) NOT NULL,
  environment ENUM('development','staging','production') NOT NULL DEFAULT 'production',
  description VARCHAR(255) NOT NULL, updated_by VARCHAR(64) NOT NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS change_requests (
  change_id INT PRIMARY KEY AUTO_INCREMENT, change_ref VARCHAR(24) NOT NULL UNIQUE,
  requested_by VARCHAR(64) NOT NULL, approved_by VARCHAR(64), service_name VARCHAR(100) NOT NULL,
  change_summary VARCHAR(200) NOT NULL,
  risk_level ENUM('low','medium','high','emergency') NOT NULL DEFAULT 'low',
  status ENUM('submitted','approved','scheduled','implemented','rolled_back','rejected') NOT NULL DEFAULT 'submitted',
  requested_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, scheduled_for DATETIME, completed_at DATETIME,
  rollback_plan TEXT
) ENGINE=InnoDB;

-- Departments
INSERT INTO departments(department_id,department_code,department_name,cost_center,location,manager_username,budget_annual,status) VALUES
(1,'ENG','Engineering','CC-ENG-010','Chennai','arao',18500000,'active'),
(2,'SAL','Sales','CC-SAL-020','Bengaluru','arao',9200000,'active'),
(3,'SUP','Customer Support','CC-SUP-030','Chennai','kmenon',6400000,'active'),
(4,'OPS','Operations','CC-OPS-040','Coimbatore','riyer',11800000,'active'),
(5,'SEC','Information Security','CC-SEC-050','Chennai','sdas',7600000,'active'),
(6,'ADM','Administration','CC-ADM-060','Chennai','Raihan',5100000,'active')
ON DUPLICATE KEY UPDATE department_name=VALUES(department_name),location=VALUES(location),budget_annual=VALUES(budget_annual),status=VALUES(status);

-- Synthetic staff; legacy plaintext field intentionally exists for the challenge.
INSERT INTO staff(id,username,plaintext_password,password_hash,full_name,department,role,email,phone_extension,employment_type,hire_date,salary_band,office_location,account_status,last_login_at) VALUES
(1,'dnair','Warehouse!92',SHA2('Warehouse!92',256),'Devika Nair','Engineering','staff','devika.nair@northstar.example','4217','full_time','2021-04-12','B3','Chennai','active','2026-10-27 09:12:11'),
(2,'arao','SalesQ3_2026',SHA2('SalesQ3_2026',256),'Aditya Rao','Sales','manager','aditya.rao@northstar.example','3184','full_time','2019-08-05','M2','Bengaluru','active','2026-10-27 08:46:32'),
(3,'kmenon','SupportDesk#7',SHA2('SupportDesk#7',256),'Kavya Menon','Support','staff','kavya.menon@northstar.example','2261','full_time','2022-02-21','B2','Chennai','active','2026-10-26 17:58:04'),
(4,'riyer','OpsLead!!41',SHA2('OpsLead!!41',256),'Rahul Iyer','Operations','manager','rahul.iyer@northstar.example','5108','full_time','2018-11-19','M2','Coimbatore','active','2026-10-27 07:55:41'),
(5,'sdas','SecAnalyst_09',SHA2('SecAnalyst_09',256),'Sneha Das','Security','security','sneha.das@northstar.example','6150','full_time','2020-06-08','B4','Chennai','active','2026-10-27 09:01:20'),
(6,'Raihan','SuperSecretPassword123',SHA2('SuperSecretPassword123',256),'Raihan','Administration','admin','raihan@northstar.example','1001','full_time','2017-01-09','D1','Chennai','active','2026-10-27 09:23:55'),
(7,'mfernandes','LaptopRefresh_26',SHA2('LaptopRefresh_26',256),'Maya Fernandes','Engineering','staff','maya.fernandes@northstar.example','4221','full_time','2023-07-17','B2','Chennai','active','2026-10-27 08:22:09'),
(8,'pkapoor','Q4Forecast!88',SHA2('Q4Forecast!88',256),'Pranav Kapoor','Sales','staff','pranav.kapoor@northstar.example','3190','full_time','2022-09-26','B3','Bengaluru','active','2026-10-26 16:34:12'),
(9,'jthomas','Helpdesk#2026',SHA2('Helpdesk#2026',256),'Joel Thomas','Support','staff','joel.thomas@northstar.example','2274','contractor','2025-03-03','C1','Chennai','active','2026-10-27 08:03:45'),
(10,'nsharma','RoutePlan_17',SHA2('RoutePlan_17',256),'Neha Sharma','Operations','staff','neha.sharma@northstar.example','5113','full_time','2021-12-01','B3','Coimbatore','active','2026-10-25 18:10:02'),
(11,'akumar','SecReview!31',SHA2('SecReview!31',256),'Arjun Kumar','Security','staff','arjun.kumar@northstar.example','6154','full_time','2024-01-15','B2','Chennai','active','2026-10-27 08:39:27'),
(12,'lchen','TempAccess_6',SHA2('TempAccess_6',256),'Li Chen','Engineering','contractor','li.chen@northstar.example','4230','contractor','2025-10-06','C2','Chennai','active','2026-10-24 11:45:00')
ON DUPLICATE KEY UPDATE plaintext_password=VALUES(plaintext_password),password_hash=VALUES(password_hash),full_name=VALUES(full_name),department=VALUES(department),role=VALUES(role),email=VALUES(email),phone_extension=VALUES(phone_extension),employment_type=VALUES(employment_type),hire_date=VALUES(hire_date),salary_band=VALUES(salary_band),office_location=VALUES(office_location),account_status=VALUES(account_status),last_login_at=VALUES(last_login_at);

INSERT INTO roles(role_id,role_code,role_name,description,privilege_tier,is_privileged) VALUES
(1,'EMPLOYEE','Standard Employee','Access to ordinary employee resources',1,FALSE),
(2,'MANAGER','Department Manager','Approvals and department reporting',2,FALSE),
(3,'HELPDESK','IT Support','Support ticket and endpoint operations',2,FALSE),
(4,'SECURITY_ANALYST','Security Analyst','Security investigations and access reviews',3,TRUE),
(5,'PORTAL_ADMIN','Portal Administrator','Portal administration and account management',4,TRUE),
(6,'DB_READER','Database Reader','Read-only reporting access',2,TRUE)
ON DUPLICATE KEY UPDATE role_name=VALUES(role_name),description=VALUES(description),privilege_tier=VALUES(privilege_tier),is_privileged=VALUES(is_privileged);

INSERT INTO staff_role_assignments(staff_id,role_id,assigned_by) VALUES
(1,1,'Raihan'),(2,2,'Raihan'),(3,1,'Raihan'),(3,3,'Raihan'),(4,2,'Raihan'),(5,4,'Raihan'),(6,5,'system'),(7,1,'Raihan'),(8,1,'Raihan'),(9,3,'Raihan'),(10,1,'Raihan'),(11,4,'Raihan'),(12,1,'Raihan')
ON DUPLICATE KEY UPDATE assigned_by=VALUES(assigned_by);

INSERT INTO projects(project_id,project_code,project_name,department_id,project_manager_username,status,priority,budget,start_date,target_date,description) VALUES
(1,'NS-ERP-26','ERP Modernization',1,'dnair','active','high',4200000,'2026-02-01','2027-01-31','Modernize finance, procurement, and workforce workflows.'),
(2,'NS-ZTA-14','Zero Trust Access Rollout',5,'sdas','active','critical',1850000,'2026-04-15','2026-12-15','Introduce device posture checks and least-privilege access.'),
(3,'NS-CS-09','Customer Support Knowledge Base',3,'kmenon','active','normal',640000,'2026-05-01','2026-11-30','Consolidate troubleshooting and knowledge articles.'),
(4,'NS-OPS-31','Regional Inventory Visibility',4,'riyer','on_hold','high',1280000,'2026-01-10','2026-10-31','Unify inventory reporting across regional facilities.'),
(5,'NS-PORTAL-08','Employee Portal Refresh',1,'dnair','active','normal',920000,'2026-07-01','2026-12-20','Refresh the internal employee portal and service directory.')
ON DUPLICATE KEY UPDATE project_name=VALUES(project_name),status=VALUES(status),priority=VALUES(priority),budget=VALUES(budget),description=VALUES(description);

INSERT INTO assets(asset_id,asset_tag,asset_type,manufacturer,model,serial_number,assigned_username,department_id,location,purchase_date,warranty_end,asset_status,purchase_cost,hostname,notes) VALUES
(1,'NS-LT-1042','laptop','Lenovo','ThinkPad T14 Gen 4','PF4A1042','dnair',1,'Chennai - Floor 4','2025-02-14','2028-02-13','assigned',112500,'NS-CHN-LT1042','Engineering workstation'),
(2,'NS-LT-1188','laptop','Dell','Latitude 7440','DL7440-1188','sdas',5,'Chennai - Secure Wing','2025-05-22','2028-05-21','assigned',138000,'NS-SEC-LT1188','Security analyst endpoint'),
(3,'NS-SRV-020','server','Dell','PowerEdge R650','SRV-R650-020',NULL,1,'Chennai - Server Room','2024-08-11','2029-08-10','in_stock',640000,'NS-CHN-SRV020','Staging workload host'),
(4,'NS-MOB-330','mobile','Samsung','Galaxy S24','SM-S24-330','arao',2,'Bengaluru - Floor 3','2025-01-10','2027-01-09','assigned',78999,'NS-SAL-MOB330','Managed mobile device'),
(5,'NS-NET-071','network','Cisco','Catalyst 9300','FCW2307N071',NULL,4,'Coimbatore - Network Closet','2024-03-18','2027-03-17','repair',285000,'NS-CBE-SW071','Intermittent uplink; vendor case open'),
(6,'NS-LT-1290','laptop','HP','EliteBook 840 G10','HP840-1290','mfernandes',1,'Chennai - Floor 4','2025-09-04','2028-09-03','assigned',119000,'NS-CHN-LT1290','Portal development')
ON DUPLICATE KEY UPDATE asset_status=VALUES(asset_status),location=VALUES(location),assigned_username=VALUES(assigned_username),notes=VALUES(notes);

INSERT INTO support_tickets(ticket_id,ticket_ref,opened_by,assigned_to,department_id,category,subject,description,priority,status,opened_at,due_at,internal_notes) VALUES
(1,'INC-2026-0142','dnair','jthomas',1,'access','VPN certificate renewal','Client certificate expires before the next release window.','high','in_progress','2026-10-26 10:14:00','2026-10-29 17:00:00','Verify device compliance before renewal.'),
(2,'INC-2026-0143','mfernandes','jthomas',1,'hardware','Laptop docking station disconnects','External monitors disconnect after sleep.','normal','open','2026-10-26 14:40:00','2026-10-31 17:00:00','Firmware version needs checking.'),
(3,'SEC-2026-0038','sdas','akumar',5,'security','Unexpected privileged login','Review a privileged login outside the maintenance window.','urgent','in_progress','2026-10-27 07:45:00','2026-10-27 12:00:00','Correlate source IP with identity-provider logs.'),
(4,'REQ-2026-0911','pkapoor','jthomas',2,'access','Temporary finance dashboard access','Request for read-only dashboard access during quarter close.','normal','waiting','2026-10-25 11:20:00','2026-10-30 17:00:00','Awaiting manager approval.'),
(5,'INC-2026-0145','nsharma','riyer',4,'network','Warehouse scanner latency','Handheld scanners experience delays during shift change.','high','open','2026-10-27 08:30:00','2026-10-28 18:00:00','Check access point utilization.')
ON DUPLICATE KEY UPDATE subject=VALUES(subject),description=VALUES(description),priority=VALUES(priority),status=VALUES(status),internal_notes=VALUES(internal_notes);

INSERT INTO vendors(vendor_id,vendor_code,vendor_name,category,contact_name,contact_email,phone,payment_terms,vendor_status) VALUES
(1,'VND-001','BluePeak Systems','IT Hardware','Meera Shah','accounts@bluepeak.example','+91-44-4000-0101','Net 30','approved'),
(2,'VND-002','Meridian Cloud Services','Cloud Services','Vikram Bose','billing@meridian.example','+91-80-4000-0202','Net 45','approved'),
(3,'VND-003','Southline Networks','Networking','Anita Joseph','finance@southline.example','+91-422-4000-0303','Net 30','review'),
(4,'VND-004','Cedar Office Supplies','Facilities','Karthik Menon','ap@cedar.example','+91-44-4000-0404','Net 15','approved')
ON DUPLICATE KEY UPDATE vendor_name=VALUES(vendor_name),category=VALUES(category),contact_name=VALUES(contact_name),contact_email=VALUES(contact_email),payment_terms=VALUES(payment_terms),vendor_status=VALUES(vendor_status);

INSERT INTO purchase_orders(po_id,po_number,vendor_id,requested_by,department_id,approved_by,order_date,expected_delivery,total_amount,currency,status,justification) VALUES
(1,'PO-2026-00418',1,'dnair',1,'Raihan','2026-09-18','2026-10-05',337500,'INR','received','Developer workstation refresh.'),
(2,'PO-2026-00427',2,'sdas',5,'Raihan','2026-10-01','2026-10-31',485000,'INR','ordered','Security telemetry retention extension.'),
(3,'PO-2026-00431',3,'riyer',4,NULL,'2026-10-12','2026-11-10',192000,'INR','pending','Replace failing warehouse access switches.')
ON DUPLICATE KEY UPDATE status=VALUES(status),total_amount=VALUES(total_amount),expected_delivery=VALUES(expected_delivery),justification=VALUES(justification);

INSERT INTO invoices(invoice_id,invoice_number,vendor_id,po_id,invoice_date,due_date,amount,tax_amount,status,payment_reference) VALUES
(1,'INV-BPS-2026-118',1,1,'2026-10-06','2026-11-05',337500,60750,'approved',NULL),
(2,'INV-MCS-2026-441',2,2,'2026-10-15','2026-11-29',485000,87300,'received',NULL),
(3,'INV-SLN-2026-092',3,3,'2026-10-18','2026-11-17',192000,34560,'under_review',NULL)
ON DUPLICATE KEY UPDATE status=VALUES(status),amount=VALUES(amount),tax_amount=VALUES(tax_amount);

INSERT INTO audit_logs(audit_id,event_time,actor_username,event_type,resource_type,resource_id,source_ip,outcome,severity,details) VALUES
(1,'2026-10-27 07:42:10','sdas','privileged_login','identity','sdas','10.20.5.44','success','medium',JSON_OBJECT('method','password+mfa','device','NS-CHN-LT1188')),
(2,'2026-10-27 07:45:31','unknown','login_attempt','identity','Raihan','10.20.9.81','failure','high',JSON_OBJECT('reason','invalid password','source','internal subnet')),
(3,'2026-10-27 08:02:05','jthomas','ticket_update','support_ticket','INC-2026-0142','10.20.12.31','success','info',JSON_OBJECT('field','status','from','open','to','in_progress')),
(4,'2026-10-27 08:15:44','arao','report_export','sales_report','Q3-2026','10.20.18.12','success','low',JSON_OBJECT('format','csv','rows',184)),
(5,'2026-10-27 08:59:20','sdas','access_review_opened','access_review','AR-2026-Q4-017','10.20.5.44','success','medium',JSON_OBJECT('system','Employee Portal','review_cycle','Q4-2026')),
(6,'2026-10-27 09:06:02','system','database_connection','mysql','employees','127.0.0.1','success','info',JSON_OBJECT('client','northstar-portal','account','northstar')),
(7,'2026-10-27 09:10:48','unknown','database_authentication','mysql','northstar','10.20.9.81','success','critical',JSON_OBJECT('note','Synthetic lab event; investigate unexpected remote access'))
ON DUPLICATE KEY UPDATE event_time=VALUES(event_time),outcome=VALUES(outcome),severity=VALUES(severity),details=VALUES(details);

INSERT INTO access_reviews(review_id,review_ref,username,system_name,access_level,reviewer_username,review_status,reviewed_at,notes) VALUES
(1,'AR-2026-Q4-015','dnair','Employee Portal','Employee','sdas','approved','2026-10-20 14:10:00','Standard access confirmed.'),
(2,'AR-2026-Q4-016','sdas','Security Console','Security Analyst','Raihan','approved','2026-10-21 16:45:00','Role required for incident response.'),
(3,'AR-2026-Q4-017','Raihan','Employee Portal','Portal Administrator','sdas','pending',NULL,'Privileged access recertification outstanding.'),
(4,'AR-2026-Q4-018','lchen','Source Repository','Contractor','dnair','revoke',NULL,'Contract extension not yet recorded.')
ON DUPLICATE KEY UPDATE review_status=VALUES(review_status),reviewed_at=VALUES(reviewed_at),notes=VALUES(notes);

INSERT INTO app_settings(setting_key,setting_value,environment,description,updated_by) VALUES
('portal.maintenance_mode','false','production','Controls the maintenance banner.','Raihan'),
('portal.session_idle_minutes','30','production','Idle session timeout in minutes.','sdas'),
('portal.directory.page_size','25','production','Default number of directory rows per page.','dnair'),
('security.mfa_required','true','production','Require MFA for privileged users.','sdas'),
('database.read_replica_enabled','false','staging','Whether reporting uses a read replica.','dnair'),
('support.default_queue','IT-OPS','production','Default internal support queue.','kmenon')
ON DUPLICATE KEY UPDATE setting_value=VALUES(setting_value),description=VALUES(description),updated_by=VALUES(updated_by);

INSERT INTO change_requests(change_id,change_ref,requested_by,approved_by,service_name,change_summary,risk_level,status,requested_at,scheduled_for,rollback_plan) VALUES
(1,'CHG-2026-0812','dnair','sdas','Employee Portal','Rotate portal database credentials','high','scheduled','2026-10-21 10:00:00','2026-10-30 22:00:00','Restore prior secret and restart portal service.'),
(2,'CHG-2026-0817','riyer',NULL,'Warehouse Network','Replace access switch in Coimbatore','medium','submitted','2026-10-25 15:30:00',NULL,'Reinstall prior switch configuration.'),
(3,'CHG-2026-0821','sdas','Raihan','Identity Platform','Review privileged group membership','high','approved','2026-10-26 09:20:00','2026-10-29 20:00:00','Restore exported group membership if validation fails.')
ON DUPLICATE KEY UPDATE change_summary=VALUES(change_summary),status=VALUES(status),rollback_plan=VALUES(rollback_plan);

-- The blank password and wildcard host are intentional CTF misconfigurations.
-- Broad SELECT grants make the other synthetic tables discoverable in the lab.
CREATE USER IF NOT EXISTS 'northstar'@'%' IDENTIFIED BY '';
ALTER USER 'northstar'@'%' IDENTIFIED BY ''
  WITH MAX_QUERIES_PER_HOUR 300
       MAX_UPDATES_PER_HOUR 0
       MAX_CONNECTIONS_PER_HOUR 100
       MAX_USER_CONNECTIONS 5;
GRANT SELECT ON employees.* TO 'northstar'@'%';
FLUSH PRIVILEGES;
