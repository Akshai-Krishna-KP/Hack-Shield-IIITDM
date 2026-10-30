PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS doctors (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    specialty TEXT NOT NULL,
    email TEXT NOT NULL,
    office TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS patients (
    uuid TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    doctor_id INTEGER NOT NULL,
    dob TEXT NOT NULL,
    gender TEXT NOT NULL,
    phone TEXT NOT NULL,
    diagnosis TEXT NOT NULL,
    last_visit TEXT NOT NULL,
    FOREIGN KEY (doctor_id) REFERENCES doctors(id)
);

CREATE TABLE IF NOT EXISTS documents (
    id INTEGER PRIMARY KEY,
    title TEXT NOT NULL,
    filename TEXT NOT NULL,
    file_path TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS shares (
    share_id INTEGER PRIMARY KEY,
    owner_id INTEGER NOT NULL,
    document_id INTEGER NOT NULL,
    expiry TEXT NOT NULL,
    FOREIGN KEY (document_id) REFERENCES documents(id)
);

INSERT OR REPLACE INTO doctors (id, name, specialty, email, office) VALUES
(1, 'Dr. Nadia Iyer', 'Internal Medicine', 'nadia.iyer@byteforge.local', 'Block A - 204'),
(2, 'Dr. Sameer Bose', 'Cardiology', 'sameer.bose@byteforge.local', 'Block B - 118'),
(3, 'Dr. Tara Menon', 'Orthopedics', 'tara.menon@byteforge.local', 'Block C - 302');

INSERT OR REPLACE INTO patients (uuid, name, doctor_id, dob, gender, phone, diagnosis, last_visit) VALUES
('8a5d3f4b-4e31-4f0d-8b6d-0b8d3d6f1001', 'Ananya Rao', 1, '1991-02-14', 'Female', '9876501001', 'Hypertension', '2026-10-12'),
('8a5d3f4b-4e31-4f0d-8b6d-0b8d3d6f1002', 'Mohit Varma', 2, '1987-07-03', 'Male', '9876501002', 'Arrhythmia follow-up', '2026-10-08'),
('8a5d3f4b-4e31-4f0d-8b6d-0b8d3d6f1003', 'Sahana Krish', 3, '1994-11-26', 'Female', '9876501003', 'Knee injury rehab', '2026-10-15'),
('8a5d3f4b-4e31-4f0d-8b6d-0b8d3d6f1004', 'Arjun Nair', 1, '1989-05-09', 'Male', '9876501004', 'Diabetes management', '2026-10-18');

INSERT OR REPLACE INTO documents (id, title, filename, file_path) VALUES
(21, 'Reception Schedule', 'reception_schedule.txt', 'documents/reception_schedule.txt'),
(22, 'Patient Transfer Notes', 'patient_transfer_notes.txt', 'documents/patient_transfer_notes.txt'),
(23, 'Vendor List', 'vendor_list.txt', 'documents/vendor_list.txt'),
(51, 'October Backup Manifest', 'october_backup_manifest.txt', 'documents/october_backup_manifest.txt'),
(52, 'Payroll Snapshot', 'payroll_snapshot.txt', 'documents/payroll_snapshot.txt'),
(53, 'Executive Contacts', 'executive_contacts.txt', 'documents/executive_contacts.txt');

INSERT OR REPLACE INTO shares (share_id, owner_id, document_id, expiry) VALUES
(908, 1, 21, '2026-12-31'),
(909, 2, 22, '2026-12-31'),
(910, 3, 23, '2026-12-31');
