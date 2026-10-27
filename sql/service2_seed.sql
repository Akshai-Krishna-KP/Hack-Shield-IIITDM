-- Hack & Shield / ShoeMart Service 2 database
-- Synthetic CTF data only. No real customer or payment data.
-- The application expects products(id, product_name, price, sku) and
-- admin_users(username, password). Search is intentionally vulnerable in app.py.
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = DELETE;

CREATE TABLE categories (
  id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE, slug TEXT NOT NULL UNIQUE,
  description TEXT, parent_id INTEGER REFERENCES categories(id)
);
CREATE TABLE brands (
  id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE, country TEXT, website TEXT
);
CREATE TABLE suppliers (
  id INTEGER PRIMARY KEY, company_name TEXT NOT NULL, contact_name TEXT,
  email TEXT, phone TEXT, city TEXT, lead_time_days INTEGER NOT NULL DEFAULT 7,
  status TEXT NOT NULL DEFAULT 'active'
);
CREATE TABLE products (
  id INTEGER PRIMARY KEY, product_name TEXT NOT NULL, slug TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL, price NUMERIC NOT NULL CHECK(price >= 0),
  compare_at_price NUMERIC, sku TEXT NOT NULL UNIQUE,
  category_id INTEGER NOT NULL REFERENCES categories(id),
  brand_id INTEGER REFERENCES brands(id), supplier_id INTEGER REFERENCES suppliers(id),
  material TEXT, color TEXT, gender TEXT, size_range TEXT,
  weight_grams INTEGER, is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE TABLE product_images (
  id INTEGER PRIMARY KEY, product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  image_url TEXT NOT NULL, alt_text TEXT, sort_order INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE inventory (
  id INTEGER PRIMARY KEY, product_id INTEGER NOT NULL UNIQUE REFERENCES products(id),
  warehouse_code TEXT NOT NULL, quantity_on_hand INTEGER NOT NULL DEFAULT 0,
  quantity_reserved INTEGER NOT NULL DEFAULT 0, reorder_level INTEGER NOT NULL DEFAULT 5,
  bin_location TEXT, last_counted_at TEXT
);
CREATE TABLE customers (
  id INTEGER PRIMARY KEY, customer_code TEXT NOT NULL UNIQUE,
  first_name TEXT NOT NULL, last_name TEXT NOT NULL, email TEXT NOT NULL UNIQUE,
  phone TEXT, date_joined TEXT NOT NULL, segment TEXT NOT NULL DEFAULT 'standard',
  loyalty_points INTEGER NOT NULL DEFAULT 0, marketing_opt_in INTEGER NOT NULL DEFAULT 0,
  account_status TEXT NOT NULL DEFAULT 'active'
);
CREATE TABLE customer_addresses (
  id INTEGER PRIMARY KEY, customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  address_type TEXT NOT NULL, recipient_name TEXT NOT NULL, line1 TEXT NOT NULL,
  line2 TEXT, city TEXT NOT NULL, state TEXT NOT NULL, postal_code TEXT NOT NULL,
  country TEXT NOT NULL DEFAULT 'India', is_default INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE coupons (
  id INTEGER PRIMARY KEY, code TEXT NOT NULL UNIQUE, description TEXT,
  discount_type TEXT NOT NULL CHECK(discount_type IN ('percent','fixed')),
  discount_value NUMERIC NOT NULL, min_order_value NUMERIC NOT NULL DEFAULT 0,
  starts_at TEXT NOT NULL, expires_at TEXT NOT NULL, usage_limit INTEGER,
  usage_count INTEGER NOT NULL DEFAULT 0, is_active INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE orders (
  id INTEGER PRIMARY KEY, order_number TEXT NOT NULL UNIQUE,
  customer_id INTEGER NOT NULL REFERENCES customers(id), placed_at TEXT NOT NULL,
  order_status TEXT NOT NULL, currency TEXT NOT NULL DEFAULT 'INR',
  subtotal NUMERIC NOT NULL, discount_amount NUMERIC NOT NULL DEFAULT 0,
  shipping_amount NUMERIC NOT NULL DEFAULT 0, tax_amount NUMERIC NOT NULL DEFAULT 0,
  grand_total NUMERIC NOT NULL, coupon_id INTEGER REFERENCES coupons(id),
  billing_address_id INTEGER REFERENCES customer_addresses(id),
  shipping_address_id INTEGER REFERENCES customer_addresses(id), notes TEXT
);
CREATE TABLE order_items (
  id INTEGER PRIMARY KEY, order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id INTEGER NOT NULL REFERENCES products(id), sku_snapshot TEXT NOT NULL,
  product_name_snapshot TEXT NOT NULL, unit_price NUMERIC NOT NULL,
  quantity INTEGER NOT NULL CHECK(quantity > 0), line_total NUMERIC NOT NULL,
  size TEXT, color TEXT
);
CREATE TABLE payments (
  id INTEGER PRIMARY KEY, order_id INTEGER NOT NULL REFERENCES orders(id),
  provider TEXT NOT NULL, provider_reference TEXT UNIQUE, payment_method TEXT NOT NULL,
  amount NUMERIC NOT NULL, currency TEXT NOT NULL DEFAULT 'INR', payment_status TEXT NOT NULL,
  card_brand TEXT, card_last4 TEXT, authorized_at TEXT, captured_at TEXT,
  gateway_response_code TEXT
);
CREATE TABLE shipments (
  id INTEGER PRIMARY KEY, order_id INTEGER NOT NULL REFERENCES orders(id),
  carrier TEXT NOT NULL, tracking_number TEXT UNIQUE, shipment_status TEXT NOT NULL,
  shipped_at TEXT, estimated_delivery TEXT, delivered_at TEXT, tracking_url TEXT
);
CREATE TABLE returns (
  id INTEGER PRIMARY KEY, order_item_id INTEGER NOT NULL REFERENCES order_items(id),
  customer_id INTEGER NOT NULL REFERENCES customers(id), requested_at TEXT NOT NULL,
  reason TEXT NOT NULL, return_status TEXT NOT NULL, refund_amount NUMERIC,
  resolution_notes TEXT
);
CREATE TABLE reviews (
  id INTEGER PRIMARY KEY, product_id INTEGER NOT NULL REFERENCES products(id),
  customer_id INTEGER NOT NULL REFERENCES customers(id), order_id INTEGER REFERENCES orders(id),
  rating INTEGER NOT NULL CHECK(rating BETWEEN 1 AND 5), title TEXT, review_text TEXT,
  moderation_status TEXT NOT NULL DEFAULT 'published', created_at TEXT NOT NULL,
  UNIQUE(product_id, customer_id, order_id)
);
CREATE TABLE support_tickets (
  id INTEGER PRIMARY KEY, ticket_number TEXT NOT NULL UNIQUE,
  customer_id INTEGER NOT NULL REFERENCES customers(id), order_id INTEGER REFERENCES orders(id),
  subject TEXT NOT NULL, category TEXT NOT NULL, priority TEXT NOT NULL,
  ticket_status TEXT NOT NULL, assigned_team TEXT, created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL, internal_note TEXT
);
CREATE TABLE ticket_messages (
  id INTEGER PRIMARY KEY, ticket_id INTEGER NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
  sender_type TEXT NOT NULL, sender_name TEXT NOT NULL, message TEXT NOT NULL,
  is_internal INTEGER NOT NULL DEFAULT 0, sent_at TEXT NOT NULL
);
CREATE TABLE admin_users (
  id INTEGER PRIMARY KEY, username TEXT NOT NULL UNIQUE, password TEXT NOT NULL,
  display_name TEXT NOT NULL, role TEXT NOT NULL DEFAULT 'admin',
  is_active INTEGER NOT NULL DEFAULT 1, last_login TEXT
);
CREATE TABLE audit_logs (
  id INTEGER PRIMARY KEY, actor_username TEXT, action TEXT NOT NULL,
  entity_type TEXT NOT NULL, entity_id TEXT, source_ip TEXT, user_agent TEXT,
  outcome TEXT NOT NULL, created_at TEXT NOT NULL, details TEXT
);
CREATE TABLE newsletter_subscribers (
  id INTEGER PRIMARY KEY, email TEXT NOT NULL UNIQUE, first_name TEXT,
  subscribed_at TEXT NOT NULL, source TEXT, status TEXT NOT NULL DEFAULT 'subscribed'
);
CREATE TABLE warehouse_transfers (
  id INTEGER PRIMARY KEY, product_id INTEGER NOT NULL REFERENCES products(id),
  from_warehouse TEXT NOT NULL, to_warehouse TEXT NOT NULL,
  quantity INTEGER NOT NULL, transfer_status TEXT NOT NULL,
  requested_at TEXT NOT NULL, completed_at TEXT
);

CREATE INDEX idx_products_category ON products(category_id);
CREATE INDEX idx_products_brand ON products(brand_id);
CREATE INDEX idx_products_name ON products(product_name);
CREATE INDEX idx_orders_customer_date ON orders(customer_id, placed_at);
CREATE INDEX idx_orders_status ON orders(order_status);
CREATE INDEX idx_order_items_order ON order_items(order_id);
CREATE INDEX idx_tickets_status_priority ON support_tickets(ticket_status, priority);
CREATE INDEX idx_reviews_product ON reviews(product_id, moderation_status);

INSERT INTO categories VALUES
(1,'Running','running','Road and track running shoes',NULL),
(2,'Lifestyle','lifestyle','Everyday casual footwear',NULL),
(3,'Hiking','hiking','Trail and outdoor footwear',NULL),
(4,'Formal','formal','Office and occasion footwear',NULL),
(5,'Training','training','Gym and court training shoes',NULL),
(6,'Accessories','accessories','Shoe care and accessories',NULL),
(7,'Kids','kids','Footwear for younger customers',2);
INSERT INTO brands VALUES
(1,'Northstar Athletics','India','https://northstar.example.test'),
(2,'StrideWorks','India','https://strideworks.example.test'),
(3,'TerraTrek','Vietnam','https://terratrek.example.test'),
(4,'Crown & Hide','India','https://crownhide.example.test'),
(5,'Everyday Co.','India','https://everyday.example.test'),
(6,'PaceLab','Singapore','https://pacelab.example.test');
INSERT INTO suppliers VALUES
(1,'Chennai Footwear Manufacturing','K. Suresh','ops@chennai-supplier.example.test','+91-44-5550-0101','Chennai',5,'active'),
(2,'Western Sole Distributors','Nisha Patel','supply@westernsole.example.test','+91-22-5550-0202','Mumbai',8,'active'),
(3,'Malabar Outdoor Goods','Faisal Rahman','orders@malabar.example.test','+91-484-555-0303','Kochi',10,'active'),
(4,'Crown Leather Works','Anita Joseph','vendor@crownleather.example.test','+91-80-5550-0404','Bengaluru',12,'active'),
(5,'Metro Sports Imports','Dev Khanna','inventory@metrosports.example.test','+91-11-5550-0505','Delhi',14,'review');

INSERT INTO products VALUES
(1,'Air Runner 2000','air-runner-2000','Lightweight daily road running shoe with breathable mesh upper.',4999,5999,'SHM-RUN-1001',1,1,1,'Engineered mesh','Blue/White','Unisex','UK 6-11',265,1,'2025-08-12','2026-09-18'),
(2,'Marathon Flyweight','marathon-flyweight','Responsive long-distance shoe with cushioned midsole.',7499,8999,'SHM-RUN-1002',1,6,5,'Knit mesh','Black/Volt','Unisex','UK 6-12',228,1,'2025-09-02','2026-09-20'),
(3,'Road Tempo Lite','road-tempo-lite','Light tempo trainer built for interval sessions.',6299,6999,'SHM-RUN-1003',1,2,2,'Mesh','Grey/Coral','Unisex','UK 5-11',242,1,'2025-11-11','2026-09-21'),
(4,'Classic Leather Loafer','classic-leather-loafer','Minimal leather loafer for smart casual wear.',3499,4299,'SHM-LIF-2001',2,4,4,'Full-grain leather','Tan','Men','UK 7-11',390,1,'2025-06-22','2026-08-15'),
(5,'Street Canvas Low-Top','street-canvas-low-top','Everyday canvas sneaker with vulcanized rubber sole.',1999,2499,'SHM-LIF-2002',2,5,1,'Canvas','Off-white','Unisex','UK 4-10',315,1,'2025-05-10','2026-09-10'),
(6,'Retro Court 88','retro-court-88','Retro-inspired court sneaker with padded collar.',3899,4499,'SHM-LIF-2003',2,2,2,'Synthetic leather','White/Green','Unisex','UK 5-11',340,1,'2025-10-01','2026-09-09'),
(7,'Trail Grip Hiking Boot','trail-grip-hiking-boot','Water-resistant hiking boot with aggressive outsole.',6999,7999,'SHM-HIK-3001',3,3,3,'Nubuck/synthetic','Olive','Unisex','UK 6-12',610,1,'2025-07-17','2026-09-16'),
(8,'Monsoon Trek Mid','monsoon-trek-mid','Mid-cut trail shoe with reinforced toe protection.',5799,6499,'SHM-HIK-3002',3,3,3,'Ripstop textile','Charcoal','Unisex','UK 5-11',485,1,'2025-12-03','2026-09-14'),
(9,'Office Oxford','office-oxford','Classic lace-up Oxford for business and formal occasions.',3999,4999,'SHM-FOR-4001',4,4,4,'Polished leather','Black','Men','UK 7-12',430,1,'2025-04-14','2026-08-22'),
(10,'Mira Block Heel','mira-block-heel','Comfort-fit block heel with cushioned footbed.',3299,3799,'SHM-FOR-4002',4,5,2,'Synthetic leather','Burgundy','Women','UK 3-8',355,1,'2025-09-28','2026-09-05'),
(11,'Court Pro Sneaker','court-pro-sneaker','Stable court shoe designed for lateral movement.',5499,6299,'SHM-TRN-5001',5,1,5,'Mesh/synthetic','White/Navy','Unisex','UK 5-12',370,1,'2025-10-18','2026-09-19'),
(12,'Flex Studio Trainer','flex-studio-trainer','Flexible cross-training shoe for gym sessions.',4599,5299,'SHM-TRN-5002',5,6,5,'Knit textile','Lilac','Women','UK 3-9',255,1,'2026-01-05','2026-09-19'),
(13,'Junior Sprint','junior-sprint','Durable lightweight shoe for school sports.',1799,2199,'SHM-KID-7001',7,1,1,'Mesh','Red/Black','Kids','UK 1-5',190,1,'2025-08-20','2026-09-01'),
(14,'Suede Desert Boot','suede-desert-boot','Soft suede ankle boot with crepe-style sole.',4299,4999,'SHM-LIF-2004',2,4,4,'Suede','Sand','Men','UK 7-11',465,1,'2025-07-30','2026-08-28'),
(15,'Cedar Shoe Care Kit','cedar-shoe-care-kit','Brush, cloth and neutral conditioner for leather shoes.',799,999,'SHM-ACC-6001',6,5,1,'Wood/cotton','Natural','Unisex','One size',180,1,'2026-02-10','2026-09-02'),
(16,'Archive Runner 91','archive-runner-91','Heritage runner with layered panels and soft lining.',0,3499,'SHM-OLD-9001',2,2,2,'Synthetic/textile','Navy/Gold','Unisex','UK 5-10',350,0,'2024-03-12','2025-12-01');
INSERT INTO product_images VALUES
(1,1,'/static/assets/air-runner-blue.webp','Air Runner 2000 in blue',1),
(2,4,'/static/assets/classic-loafer-tan.webp','Classic leather loafer in tan',1),
(3,7,'/static/assets/trail-grip-olive.webp','Trail Grip hiking boot in olive',1),
(4,9,'/static/assets/office-oxford-black.webp','Office Oxford in black',1),
(5,11,'/static/assets/court-pro-white.webp','Court Pro sneaker in white',1);
INSERT INTO inventory VALUES
(1,1,'CHN-01',48,4,10,'A-01-04','2026-10-02'),(2,2,'CHN-01',19,2,8,'A-02-01','2026-10-02'),
(3,3,'MUM-02',12,1,6,'B-04-02','2026-10-01'),(4,4,'BLR-01',31,3,8,'C-01-03','2026-10-02'),
(5,5,'CHN-01',67,5,15,'D-02-04','2026-10-02'),(6,6,'MUM-02',24,1,8,'B-01-02','2026-10-01'),
(7,7,'KOC-01',9,2,6,'E-03-01','2026-09-30'),(8,8,'KOC-01',15,1,6,'E-03-02','2026-09-30'),
(9,9,'BLR-01',21,2,8,'C-04-01','2026-10-02'),(10,10,'BLR-01',17,1,6,'C-05-02','2026-10-02'),
(11,11,'MUM-02',28,3,8,'B-05-01','2026-10-01'),(12,12,'MUM-02',5,1,8,'B-05-04','2026-10-01'),
(13,13,'CHN-01',43,0,12,'D-01-01','2026-10-02'),(14,14,'BLR-01',7,1,6,'C-02-02','2026-10-02'),
(15,15,'CHN-01',102,4,20,'F-01-01','2026-10-02'),(16,16,'CHN-01',0,0,5,'Z-RET-01','2026-10-02');

INSERT INTO customers VALUES
(1,'CUS-10001','Aarav','Menon','aarav.menon@example.test','+91-90000-10001','2025-01-12','gold',820,1,'active'),
(2,'CUS-10002','Diya','Sharma','diya.sharma@example.test','+91-90000-10002','2025-02-21','silver',340,1,'active'),
(3,'CUS-10003','Rohan','Nair','rohan.nair@example.test','+91-90000-10003','2025-04-03','standard',90,0,'active'),
(4,'CUS-10004','Meera','Iyer','meera.iyer@example.test','+91-90000-10004','2025-05-17','gold',1240,1,'active'),
(5,'CUS-10005','Ishaan','Reddy','ishaan.reddy@example.test','+91-90000-10005','2025-06-02','standard',55,1,'active'),
(6,'CUS-10006','Ananya','Das','ananya.das@example.test','+91-90000-10006','2025-07-19','silver',430,1,'active'),
(7,'CUS-10007','Kabir','Joshi','kabir.joshi@example.test','+91-90000-10007','2025-08-11','standard',20,0,'active'),
(8,'CUS-10008','Sara','Thomas','sara.thomas@example.test','+91-90000-10008','2025-08-26','gold',990,1,'active'),
(9,'CUS-10009','Vikram','Pillai','vikram.pillai@example.test','+91-90000-10009','2025-09-09','standard',70,0,'active'),
(10,'CUS-10010','Nila','Krishnan','nila.krishnan@example.test','+91-90000-10010','2025-10-14','silver',280,1,'active'),
(11,'CUS-10011','Arjun','Kapoor','arjun.kapoor@example.test','+91-90000-10011','2026-01-05','standard',45,1,'active'),
(12,'CUS-10012','Tara','Fernandes','tara.fernandes@example.test','+91-90000-10012','2026-03-28','standard',10,0,'active');
INSERT INTO customer_addresses VALUES
(1,1,'shipping','Aarav Menon','12 Lake View Road','Flat 3B','Chennai','Tamil Nadu','600042','India',1),
(2,1,'billing','Aarav Menon','12 Lake View Road','Flat 3B','Chennai','Tamil Nadu','600042','India',1),
(3,2,'shipping','Diya Sharma','44 Indiranagar 2nd Stage',NULL,'Bengaluru','Karnataka','560038','India',1),
(4,3,'shipping','Rohan Nair','8 Marine Drive','Apt 11','Kochi','Kerala','682031','India',1),
(5,4,'shipping','Meera Iyer','17 Race Course Road',NULL,'Coimbatore','Tamil Nadu','641018','India',1),
(6,5,'shipping','Ishaan Reddy','29 Jubilee Hills','Block C','Hyderabad','Telangana','500033','India',1),
(7,6,'shipping','Ananya Das','6 Salt Lake Sector 1',NULL,'Kolkata','West Bengal','700064','India',1),
(8,7,'shipping','Kabir Joshi','90 Baner Road',NULL,'Pune','Maharashtra','411045','India',1),
(9,8,'shipping','Sara Thomas','22 Vyttila Junction',NULL,'Kochi','Kerala','682019','India',1),
(10,9,'shipping','Vikram Pillai','31 Ashok Nagar',NULL,'Chennai','Tamil Nadu','600083','India',1),
(11,10,'shipping','Nila Krishnan','15 HSR Layout','Sector 2','Bengaluru','Karnataka','560102','India',1),
(12,11,'shipping','Arjun Kapoor','10 Civil Lines',NULL,'Jaipur','Rajasthan','302006','India',1),
(13,12,'shipping','Tara Fernandes','5 Panjim Market Road',NULL,'Panaji','Goa','403001','India',1);
INSERT INTO coupons VALUES
(1,'WELCOME10','10 percent off first order','percent',10,999,'2026-01-01','2027-01-01',5000,128,1),
(2,'RUNCLUB15','Running club promotion','percent',15,3000,'2026-08-01','2026-12-31',800,211,1),
(3,'SHIPFREE','Free shipping threshold promotion','fixed',150,1499,'2026-06-01','2026-11-30',1200,388,1),
(4,'MONSOON25','Expired seasonal campaign','percent',25,2500,'2026-06-01','2026-08-31',300,300,0);
INSERT INTO orders VALUES
(1,'SM-2026-10001',1,'2026-09-01 10:24:00','delivered','INR',4999,500,99,828,5426,1,2,1,'Gift wrap requested'),
(2,'SM-2026-10002',2,'2026-09-04 15:42:00','shipped','INR',3499,0,99,648,4246,NULL,3,3,NULL),
(3,'SM-2026-10003',3,'2026-09-07 09:11:00','processing','INR',6999,0,0,1259,8258,NULL,4,4,'Call before delivery'),
(4,'SM-2026-10004',4,'2026-09-10 18:05:00','delivered','INR',1999,200,99,324,2222,1,5,5,NULL),
(5,'SM-2026-10005',5,'2026-09-13 12:30:00','cancelled','INR',5499,0,99,0,0,NULL,6,6,'Customer requested cancellation'),
(6,'SM-2026-10006',6,'2026-09-16 20:15:00','delivered','INR',4299,300,99,720,4818,2,7,7,NULL),
(7,'SM-2026-10007',8,'2026-09-20 11:48:00','return_requested','INR',7499,1125,0,1147,7521,2,9,9,'Heel cushioning issue reported'),
(8,'SM-2026-10008',9,'2026-09-22 14:02:00','shipped','INR',3999,0,99,738,4836,NULL,10,10,NULL),
(9,'SM-2026-10009',10,'2026-09-25 16:19:00','delivered','INR',4599,460,99,745,4983,1,11,11,NULL),
(10,'SM-2026-10010',11,'2026-10-01 08:56:00','paid','INR',1799,0,99,342,2240,NULL,12,12,'School sports event'),
(11,'SM-2026-10011',12,'2026-10-04 17:37:00','payment_failed','INR',6299,0,99,1134,7532,NULL,13,13,'Retry payment after gateway timeout');
INSERT INTO order_items VALUES
(1,1,1,'SHM-RUN-1001','Air Runner 2000',4999,1,4999,'UK 8','Blue/White'),
(2,2,4,'SHM-LIF-2001','Classic Leather Loafer',3499,1,3499,'UK 9','Tan'),
(3,3,7,'SHM-HIK-3001','Trail Grip Hiking Boot',6999,1,6999,'UK 10','Olive'),
(4,4,5,'SHM-LIF-2002','Street Canvas Low-Top',1999,1,1999,'UK 6','Off-white'),
(5,5,11,'SHM-TRN-5001','Court Pro Sneaker',5499,1,5499,'UK 9','White/Navy'),
(6,6,14,'SHM-LIF-2004','Suede Desert Boot',4299,1,4299,'UK 9','Sand'),
(7,7,2,'SHM-RUN-1002','Marathon Flyweight',7499,1,7499,'UK 7','Black/Volt'),
(8,8,9,'SHM-FOR-4001','Office Oxford',3999,1,3999,'UK 10','Black'),
(9,9,12,'SHM-TRN-5002','Flex Studio Trainer',4599,1,4599,'UK 6','Lilac'),
(10,10,13,'SHM-KID-7001','Junior Sprint',1799,1,1799,'UK 3','Red/Black'),
(11,11,3,'SHM-RUN-1003','Road Tempo Lite',6299,1,6299,'UK 8','Grey/Coral');
INSERT INTO payments VALUES
(1,1,'Razorpay','pay_demo_10001','UPI',5426,'INR','captured',NULL,NULL,'2026-09-01 10:24:18','2026-09-01 10:24:21','captured'),
(2,2,'PayU','pay_demo_10002','card',4246,'INR','captured','VISA','8821','2026-09-04 15:42:20','2026-09-04 15:42:25','00'),
(3,3,'Razorpay','pay_demo_10003','netbanking',8258,'INR','authorized',NULL,NULL,'2026-09-07 09:11:34',NULL,'authorized'),
(4,4,'PayU','pay_demo_10004','UPI',2222,'INR','captured',NULL,NULL,'2026-09-10 18:05:12','2026-09-10 18:05:15','captured'),
(5,5,'Razorpay','pay_demo_10005','card',0,'INR','voided','MASTERCARD','1190','2026-09-13 12:30:11',NULL,'cancelled'),
(6,6,'PayU','pay_demo_10006','wallet',4818,'INR','captured',NULL,NULL,'2026-09-16 20:15:22','2026-09-16 20:15:24','00'),
(7,7,'Razorpay','pay_demo_10007','card',7521,'INR','captured','VISA','6654','2026-09-20 11:48:10','2026-09-20 11:48:15','captured'),
(8,8,'PayU','pay_demo_10008','UPI',4836,'INR','captured',NULL,NULL,'2026-09-22 14:02:10','2026-09-22 14:02:12','00'),
(9,9,'Razorpay','pay_demo_10009','card',4983,'INR','captured','VISA','4417','2026-09-25 16:19:40','2026-09-25 16:19:44','captured'),
(10,10,'Razorpay','pay_demo_10010','UPI',2240,'INR','captured',NULL,NULL,'2026-10-01 08:56:18','2026-10-01 08:56:22','captured'),
(11,11,'PayU','pay_demo_10011','netbanking',7532,'INR','failed',NULL,NULL,'2026-10-04 17:37:02',NULL,'gateway_timeout');
INSERT INTO shipments VALUES
(1,1,'BlueDart','BD-DEMO-10001','delivered','2026-09-02','2026-09-05','2026-09-04','https://tracking.example.test/BD-DEMO-10001'),
(2,2,'Delhivery','DL-DEMO-10002','in_transit','2026-09-05','2026-09-09',NULL,'https://tracking.example.test/DL-DEMO-10002'),
(3,4,'India Post','IP-DEMO-10004','delivered','2026-09-11','2026-09-16','2026-09-15','https://tracking.example.test/IP-DEMO-10004'),
(4,6,'BlueDart','BD-DEMO-10006','delivered','2026-09-17','2026-09-20','2026-09-19','https://tracking.example.test/BD-DEMO-10006'),
(5,7,'Delhivery','DL-DEMO-10007','return_initiated','2026-09-21','2026-09-25',NULL,'https://tracking.example.test/DL-DEMO-10007'),
(6,8,'BlueDart','BD-DEMO-10008','in_transit','2026-09-23','2026-09-27',NULL,'https://tracking.example.test/BD-DEMO-10008'),
(7,9,'India Post','IP-DEMO-10009','delivered','2026-09-26','2026-10-01','2026-09-30','https://tracking.example.test/IP-DEMO-10009');
INSERT INTO returns VALUES
(1,7,8,'2026-09-24 10:10:00','Cushioning feels different from product description','inspection_pending',7499,'Awaiting warehouse quality check');
INSERT INTO reviews VALUES
(1,1,1,1,5,'Great for daily runs','Lightweight and comfortable even after 5 km.','published','2026-09-06'),
(2,4,2,2,4,'Good finish','Leather looks premium; needed a day to break in.','published','2026-09-12'),
(3,7,3,3,3,'Solid grip','Good on wet paths but runs a little narrow.','published','2026-09-18'),
(4,5,4,4,5,'Everyday favourite','Simple, versatile and worth the price.','published','2026-09-19'),
(5,2,8,7,2,'Expected more cushioning','Comfort is okay for short distances only.','published','2026-09-26'),
(6,9,9,8,4,'Office staple','Looks sharp and arrived in good packaging.','published','2026-10-02');
INSERT INTO support_tickets VALUES
(1,'TKT-260901-001',1,1,'Order arrived with damaged box','delivery','low','closed','customer-care','2026-09-05 09:20:00','2026-09-06 13:10:00','Refund shipping fee approved by supervisor.'),
(2,'TKT-260907-002',3,3,'Need delivery estimate','shipping','medium','open','logistics','2026-09-08 11:40:00','2026-09-08 11:40:00','Internal note: carrier pickup was delayed.'),
(3,'TKT-260920-003',8,7,'Cushioning concern - return request','returns','high','in_progress','returns-desk','2026-09-24 10:10:00','2026-09-25 16:45:00','Do not promise refund until inspection complete.'),
(4,'TKT-260925-004',10,9,'Invoice GST details correction','billing','medium','closed','finance','2026-09-26 14:25:00','2026-09-27 10:00:00','Corrected invoice emailed.'),
(5,'TKT-261004-005',12,11,'Payment failed but bank shows debit','payment','urgent','open','payments','2026-10-04 17:40:00','2026-10-04 17:40:00','Check gateway reconciliation before retrying.');
INSERT INTO ticket_messages VALUES
(1,1,'customer','Aarav Menon','The outer carton was torn when delivered.',0,'2026-09-05 09:20:00'),
(2,1,'agent','Customer Care','Sorry about that. We have recorded the packaging issue.',0,'2026-09-05 10:05:00'),
(3,2,'customer','Rohan Nair','Could you share the expected delivery date?',0,'2026-09-08 11:40:00'),
(4,2,'agent','Logistics Desk','The shipment is awaiting carrier scan.',0,'2026-09-08 12:15:00'),
(5,3,'customer','Sara Thomas','I would like to return these due to the cushioning.',0,'2026-09-24 10:10:00'),
(6,3,'agent','Returns Desk','We have opened a return request for inspection.',0,'2026-09-24 11:02:00'),
(7,3,'agent','Returns Desk','Internal: compare batch NS-MF-08 against QA reports.',1,'2026-09-25 16:45:00'),
(8,5,'customer','Tara Fernandes','Payment page failed, but I received a bank debit alert.',0,'2026-10-04 17:40:00');
INSERT INTO admin_users VALUES
(1,'admin','ShoeMart_Admin_2026!','Store Administrator','admin',1,NULL),
(2,'support_lead','SupportLead_Demo_2026!','Support Team Lead','support',1,'2026-10-01 09:15:00'),
(3,'inventory_ops','InventoryOps_Demo_2026!','Inventory Operations','inventory',1,'2026-10-02 16:20:00');
INSERT INTO audit_logs VALUES
(1,'admin','login_success','session','1','10.0.2.20','Mozilla/5.0 (CTF demo)','success','2026-10-01 09:14:52','Admin portal login'),
(2,'inventory_ops','stock_adjustment','inventory','12','10.0.2.21','ShoeMartOps/1.4','success','2026-10-02 16:18:03','Flex Studio Trainer stock count corrected'),
(3,'support_lead','ticket_assignment','support_tickets','5','10.0.2.22','Mozilla/5.0 (CTF demo)','success','2026-10-04 17:45:01','Assigned payment dispute to payments team'),
(4,'unknown','login_failure','admin_users','admin','10.0.2.88','curl/8.5.0','denied','2026-10-05 02:01:19','Repeated invalid login attempt - synthetic event');
INSERT INTO newsletter_subscribers VALUES
(1,'aarav.menon@example.test','Aarav','2025-01-12','checkout','subscribed'),
(2,'diya.sharma@example.test','Diya','2025-02-21','footer_form','subscribed'),
(3,'sara.thomas@example.test','Sara','2025-08-26','campaign_runclub','subscribed'),
(4,'deactivated@example.test','Demo','2025-04-10','checkout','unsubscribed');
INSERT INTO warehouse_transfers VALUES
(1,3,'MUM-02','CHN-01',12,'completed','2026-09-20 08:30:00','2026-09-22 14:15:00'),
(2,12,'CHN-01','MUM-02',10,'in_transit','2026-10-02 10:00:00',NULL),
(3,7,'KOC-01','BLR-01',6,'requested','2026-10-03 11:45:00',NULL);

-- A few more realistic operational rows; all names and contact data are synthetic.
INSERT INTO product_images VALUES
(6,2,'/static/assets/marathon-flyweight-black.webp','Marathon Flyweight in black and volt',1),
(7,5,'/static/assets/street-canvas-offwhite.webp','Street Canvas Low-Top in off-white',1),
(8,14,'/static/assets/desert-boot-sand.webp','Suede Desert Boot in sand',1);
INSERT INTO audit_logs VALUES
(5,'admin','coupon_status_change','coupons','4','10.0.2.20','ShoeMartAdmin/2.0','success','2026-08-31 18:00:00','Disabled expired MONSOON25 promotion'),
(6,'support_lead','return_review','returns','1','10.0.2.22','ShoeMartSupport/1.1','pending','2026-09-25 16:47:00','Return awaiting warehouse inspection');

PRAGMA user_version = 2;
