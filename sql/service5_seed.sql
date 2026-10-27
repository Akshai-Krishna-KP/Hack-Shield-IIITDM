-- Hack & Shield Service 5 / HackMart catalogue seed.
-- Idempotent: does not delete users, sessions, wallets, inventory, or purchases.
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS categories (
    id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE,
    description TEXT NOT NULL, display_order INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS brands (
    id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE,
    country TEXT NOT NULL, support_url TEXT
);
CREATE TABLE IF NOT EXISTS suppliers (
    id TEXT PRIMARY KEY, name TEXT NOT NULL, region TEXT NOT NULL,
    contact_email TEXT NOT NULL UNIQUE,
    lead_time_days INTEGER NOT NULL CHECK (lead_time_days >= 0)
);
CREATE TABLE IF NOT EXISTS products (
    id TEXT PRIMARY KEY, sku TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
    category_id TEXT NOT NULL REFERENCES categories(id),
    brand_id TEXT REFERENCES brands(id), supplier_id TEXT REFERENCES suppliers(id),
    price INTEGER NOT NULL CHECK (price >= 0), description TEXT NOT NULL,
    image TEXT, active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0,1)),
    is_digital INTEGER NOT NULL DEFAULT 0 CHECK (is_digital IN (0,1)),
    display_order INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS product_specs (
    product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    spec_key TEXT NOT NULL, spec_value TEXT NOT NULL,
    PRIMARY KEY (product_id, spec_key)
);
CREATE TABLE IF NOT EXISTS product_reviews (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    reviewer_alias TEXT NOT NULL, rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
    review_title TEXT NOT NULL, review_text TEXT NOT NULL,
    verified_purchase INTEGER NOT NULL DEFAULT 0 CHECK (verified_purchase IN (0,1)),
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS stock_levels (
    product_id TEXT PRIMARY KEY REFERENCES products(id) ON DELETE CASCADE,
    warehouse_code TEXT NOT NULL, quantity_on_hand INTEGER NOT NULL CHECK (quantity_on_hand >= 0),
    reorder_threshold INTEGER NOT NULL DEFAULT 5 CHECK (reorder_threshold >= 0),
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS promotions (
    id TEXT PRIMARY KEY, code TEXT NOT NULL UNIQUE, title TEXT NOT NULL,
    credit_amount INTEGER NOT NULL CHECK (credit_amount >= 0),
    max_claims_per_user INTEGER NOT NULL DEFAULT 1 CHECK (max_claims_per_user > 0),
    starts_at TEXT NOT NULL, ends_at TEXT,
    active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0,1))
);
CREATE TABLE IF NOT EXISTS product_promotions (
    product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    promotion_id TEXT NOT NULL REFERENCES promotions(id) ON DELETE CASCADE,
    PRIMARY KEY (product_id, promotion_id)
);

CREATE INDEX IF NOT EXISTS idx_products_category_active ON products(category_id, active, display_order);
CREATE INDEX IF NOT EXISTS idx_products_brand ON products(brand_id);
CREATE INDEX IF NOT EXISTS idx_reviews_product_date ON product_reviews(product_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_stock_reorder ON stock_levels(quantity_on_hand, reorder_threshold);

INSERT INTO categories (id,name,description,display_order) VALUES
 ('accessories','Accessories','Everyday peripherals and desk accessories.',10),
 ('storage','Storage','Portable and high-speed data storage.',20),
 ('displays','Displays','Monitors and visual workspace equipment.',30),
 ('audio','Audio','Headphones and personal audio gear.',40),
 ('workspace','Workspace','Ergonomic products for desks and laptops.',50),
 ('power','Power','Portable power and charging products.',60),
 ('networking','Networking','Routers and connectivity hardware.',70),
 ('challenge','Challenge item','Restricted digital item for the security exercise.',99)
ON CONFLICT(id) DO UPDATE SET name=excluded.name,description=excluded.description,display_order=excluded.display_order;

INSERT INTO brands (id,name,country,support_url) VALUES
 ('keychron','Keychron','Hong Kong','https://www.keychron.com/'),
 ('logitech','Logitech','Switzerland','https://www.logitech.com/'),
 ('sandisk','SanDisk','United States','https://www.westerndigital.com/'),
 ('viewmax','ViewMax','India','https://example.invalid/viewmax-support'),
 ('soniq','Soniq Audio','India','https://example.invalid/soniq-support'),
 ('samsung','Samsung','South Korea','https://www.samsung.com/'),
 ('orbit','Orbit Workspace','India','https://example.invalid/orbit-support'),
 ('voltix','Voltix','India','https://example.invalid/voltix-support'),
 ('netlink','NetLink','Taiwan','https://example.invalid/netlink-support'),
 ('hackmart','HackMart Digital','India','https://example.invalid/hackmart')
ON CONFLICT(id) DO UPDATE SET name=excluded.name,country=excluded.country,support_url=excluded.support_url;

INSERT INTO suppliers (id,name,region,contact_email,lead_time_days) VALUES
 ('sup-chennai','Chennai Components & Peripherals','Tamil Nadu, IN','orders@chennai-components.example',3),
 ('sup-bengaluru','Bengaluru Digital Supply','Karnataka, IN','sales@bds.example',4),
 ('sup-mumbai','Western Tech Distribution','Maharashtra, IN','dispatch@wtd.example',6),
 ('sup-import','Global Import Desk','International','procurement@gid.example',12),
 ('sup-digital','HackMart Digital Fulfilment','India','digital-ops@hackmart.example',0)
ON CONFLICT(id) DO UPDATE SET name=excluded.name,region=excluded.region,contact_email=excluded.contact_email,lead_time_days=excluded.lead_time_days;

-- Existing product IDs, names, prices, copy, ordering and SVG filenames are preserved.
INSERT INTO products (id,sku,name,category_id,brand_id,supplier_id,price,description,image,active,is_digital,display_order) VALUES
 ('keyboard','HM-ACC-001','Mechanical Keyboard','accessories','keychron','sup-chennai',120,'A compact mechanical keyboard for everyday work.','keyboard.svg',1,0,10),
 ('mouse','HM-ACC-002','Wireless Mouse','accessories','logitech','sup-bengaluru',80,'A reliable wireless mouse with a comfortable grip.','mouse.svg',1,0,20),
 ('usb','HM-STO-001','USB Drive','storage','sandisk','sup-mumbai',90,'Portable storage for files and backups.','usb.svg',1,0,30),
 ('monitor','HM-DSP-001','HD Monitor','displays','viewmax','sup-import',450,'A crisp display for work, study, and entertainment.','monitor.svg',1,0,40),
 ('headphones','HM-AUD-001','Studio Headphones','audio','soniq','sup-chennai',300,'Comfortable over-ear headphones for focused listening.','headphones.svg',1,0,50),
 ('webcam','HM-ACC-003','HD Webcam','accessories','logitech','sup-bengaluru',250,'A simple webcam for meetings and streaming.','webcam.svg',1,0,60),
 ('ssd','HM-STO-002','Portable SSD','storage','samsung','sup-import',600,'Fast external storage in a compact form.','ssd.svg',1,0,70),
 ('stand','HM-WKS-001','Laptop Stand','workspace','orbit','sup-chennai',150,'A sturdy stand to improve your desk setup.','stand.svg',1,0,80),
 ('powerbank','HM-PWR-001','Power Bank','power','voltix','sup-mumbai',500,'Extra power when you are away from a socket.','powerbank.svg',1,0,90),
 ('router','HM-NET-001','Wi-Fi Router','networking','netlink','sup-import',700,'A dependable router for a connected home.','router.svg',1,0,100),
 ('flag','HM-DIG-CTF','FLAG.txt','challenge','hackmart','sup-digital',1000,'A restricted digital item. Purchase it to complete the challenge.',NULL,1,1,110)
ON CONFLICT(id) DO UPDATE SET sku=excluded.sku,name=excluded.name,category_id=excluded.category_id,
 brand_id=excluded.brand_id,supplier_id=excluded.supplier_id,price=excluded.price,
 description=excluded.description,image=excluded.image,active=excluded.active,
 is_digital=excluded.is_digital,display_order=excluded.display_order,updated_at=CURRENT_TIMESTAMP;

INSERT INTO product_specs (product_id,spec_key,spec_value) VALUES
 ('keyboard','layout','Compact 87-key layout'),('keyboard','connection','USB-C wired'),('keyboard','switch_type','Tactile mechanical'),
 ('mouse','connection','2.4 GHz wireless'),('mouse','sensor','1600 DPI optical'),('mouse','battery','1 x AA'),
 ('usb','capacity','64 GB'),('usb','interface','USB 3.2 Gen 1'),('usb','warranty','5 years'),
 ('monitor','resolution','1920 x 1080'),('monitor','refresh_rate','75 Hz'),('monitor','panel','IPS'),
 ('headphones','connection','3.5 mm wired'),('headphones','frequency_response','20 Hz - 20 kHz'),('headphones','cable_length','1.8 m'),
 ('webcam','resolution','1080p at 30 fps'),('webcam','microphone','Dual built-in microphones'),('webcam','mount','Universal monitor clip'),
 ('ssd','capacity','1 TB'),('ssd','interface','USB 3.2 Gen 2'),('ssd','read_speed','Up to 1,000 MB/s'),
 ('stand','material','Aluminium alloy'),('stand','adjustment','6 angle positions'),('stand','compatibility','11-17 inch laptops'),
 ('powerbank','capacity','20,000 mAh'),('powerbank','output','USB-C PD 20 W'),('powerbank','ports','2 USB-A, 1 USB-C'),
 ('router','wireless','Dual-band 2.4/5 GHz'),('router','ports','4 x Gigabit LAN'),('router','security','WPA2/WPA3 mixed mode'),
 ('flag','delivery','Digital download after verified purchase'),('flag','access','Competition challenge item')
ON CONFLICT(product_id,spec_key) DO UPDATE SET spec_value=excluded.spec_value;

INSERT INTO stock_levels (product_id,warehouse_code,quantity_on_hand,reorder_threshold) VALUES
 ('keyboard','MAA-01',42,8),('mouse','MAA-01',68,12),('usb','BLR-02',120,20),
 ('monitor','MUM-01',17,5),('headphones','MAA-01',24,6),('webcam','BLR-02',31,8),
 ('ssd','MUM-01',14,5),('stand','MAA-01',53,10),('powerbank','MUM-01',19,6),
 ('router','BLR-02',11,4),('flag','DIGITAL',999999,0)
ON CONFLICT(product_id) DO UPDATE SET warehouse_code=excluded.warehouse_code,
 quantity_on_hand=excluded.quantity_on_hand,reorder_threshold=excluded.reorder_threshold,updated_at=CURRENT_TIMESTAMP;

INSERT INTO product_reviews (id,product_id,reviewer_alias,rating,review_title,review_text,verified_purchase,created_at) VALUES
 (1001,'keyboard','byte_blossom',5,'Good for the price','Compact layout and consistent key feel for daily coding.',1,'2026-08-12 10:14:00'),
 (1002,'keyboard','desksetup_7',4,'Solid starter board','Works well; would like a detachable cable.',1,'2026-09-03 16:40:00'),
 (1003,'mouse','pixelpilot',4,'Comfortable shape','Easy to use through long study sessions.',1,'2026-07-29 09:30:00'),
 (1004,'mouse','rhea_codes',5,'Simple and reliable','No unnecessary setup and tracking is accurate.',1,'2026-09-11 12:02:00'),
 (1005,'usb','backup_buddy',5,'Useful travel drive','Good capacity for project backups and documents.',1,'2026-06-21 18:10:00'),
 (1006,'monitor','visualstack',4,'Clear everyday display','Text is sharp and the stand is easy to adjust.',1,'2026-08-28 14:20:00'),
 (1007,'headphones','soundcheck',4,'Comfortable fit','Good for lectures and calls, even after a few hours.',1,'2026-09-05 20:15:00'),
 (1008,'webcam','meet_ready',5,'Clear image','Good lighting performance for remote meetings.',1,'2026-07-18 08:45:00'),
 (1009,'ssd','data_nomad',5,'Fast transfers','Large project folders copy much faster than my old drive.',1,'2026-09-19 11:05:00'),
 (1010,'stand','ergodesk',4,'Better viewing angle','Lightweight and stable on a small desk.',1,'2026-08-07 13:55:00'),
 (1011,'powerbank','commuter_k',4,'Useful capacity','Enough reserve for a full day out.',1,'2026-09-22 17:25:00'),
 (1012,'router','home_lab',4,'Easy to configure','Coverage is solid in a small apartment.',1,'2026-10-02 19:40:00')
ON CONFLICT(id) DO NOTHING;

INSERT INTO promotions (id,code,title,credit_amount,max_claims_per_user,starts_at,ends_at,active) VALUES
 ('welcome-100','HM-WELCOME-100','New member welcome credit',100,1,'2026-01-01 00:00:00',NULL,1),
 ('campus-week','CAMPUS-WEEK','Campus tech week promotion',50,1,'2026-08-01 00:00:00','2026-12-31 23:59:59',1)
ON CONFLICT(id) DO UPDATE SET code=excluded.code,title=excluded.title,credit_amount=excluded.credit_amount,
 max_claims_per_user=excluded.max_claims_per_user,starts_at=excluded.starts_at,ends_at=excluded.ends_at,active=excluded.active;

INSERT INTO product_promotions (product_id,promotion_id) VALUES
 ('keyboard','campus-week'),('mouse','campus-week'),('usb','campus-week'),('stand','campus-week')
ON CONFLICT(product_id,promotion_id) DO NOTHING;
