// Hack & Shield Service 9 / Blockstar Games internal build vault seed.
// Idempotent: updates catalogue metadata and indexes without overwriting existing dev_tokens.

const dbName = process.env.MONGO_DB_NAME || "blockstar_internal";
const targetDb = db.getSiblingDB(dbName);
const serviceFlag = process.env.SERVICE9_FLAG;

if (!serviceFlag) {
    throw new Error("SERVICE9_FLAG must be set to the protected Service 9 flag before seeding.");
}

function genDevToken() {
    // Fail loudly rather than fall back to a predictable generator.
    return require("crypto").randomBytes(32).toString("hex"); // 64 hex chars
}

const nowIso = new Date().toISOString();

// --------------------------------------------------
// 1. Indexes
// --------------------------------------------------

targetDb.studios.createIndex({ studio_id: 1 }, { unique: true });
targetDb.platforms.createIndex({ platform_id: 1 }, { unique: true });
targetDb.builds.createIndex({ game_id: 1 }, { unique: true });
targetDb.builds.createIndex({ classified: 1, display_order: 1 });
targetDb.builds.createIndex({ studio_id: 1 });
targetDb.build_specs.createIndex({ game_id: 1, spec_key: 1 }, { unique: true });
targetDb.qa_tickets.createIndex({ ticket_id: 1 }, { unique: true });
targetDb.qa_tickets.createIndex({ game_id: 1, created_at: -1 });
targetDb.cdn_mirrors.createIndex({ mirror_id: 1 }, { unique: true });

// --------------------------------------------------
// 2. Studios
// --------------------------------------------------

const studios = [
    {
        studio_id: "bstar-north",
        name: "Blockstar North",
        region: "Edinburgh, UK",
        contact_email: "builds-north@blockstar-internal.local",
        lead_time_hours: 4
    },
    {
        studio_id: "bstar-sandiego",
        name: "Blockstar San Diego",
        region: "California, US",
        contact_email: "builds-sd@blockstar-internal.local",
        lead_time_hours: 6
    },
    {
        studio_id: "bstar-toronto",
        name: "Blockstar Toronto",
        region: "Ontario, CA",
        contact_email: "builds-yyz@blockstar-internal.local",
        lead_time_hours: 5
    },
    {
        studio_id: "bstar-india",
        name: "Blockstar Technopark Studio",
        region: "Chennai, IN",
        contact_email: "builds-maa@blockstar-internal.local",
        lead_time_hours: 2
    },
    {
        studio_id: "bstar-vault",
        name: "Blockstar Executive Vault",
        region: "Classified / Internal",
        contact_email: "nda-ops@blockstar-internal.local",
        lead_time_hours: 0
    }
];

studios.forEach(s => {
    targetDb.studios.updateOne(
        { studio_id: s.studio_id },
        { $set: s, $setOnInsert: { created_at: nowIso } },
        { upsert: true }
    );
});

// --------------------------------------------------
// 3. Target Platforms
// --------------------------------------------------

const platforms = [
    {
        platform_id: "pc-devkit",
        name: "PC / Dev Kit",
        sdk_version: "RAGE-SDK 4.18.2",
        architecture: "x86_64-avx2"
    },
    {
        platform_id: "classified-nda",
        name: "Classified",
        sdk_version: "RAGE-NEXT 9.0.0-internal",
        architecture: "custom-devkit"
    }
];

platforms.forEach(p => {
    targetDb.platforms.updateOne(
        { platform_id: p.platform_id },
        { $set: p },
        { upsert: true }
    );
});

// --------------------------------------------------
// 4. Repository Builds (Preserves existing game_ids & UI fields)
// --------------------------------------------------

const builds = [
    {
        game_id: "bar1",
        sku: "BS-BLD-001",
        name: "Blue Alive Redemption",
        studio_id: "bstar-sandiego",
        build: "v1.2.3-dev",
        platform: "PC / Dev Kit",
        size_mb: 48210,
        classified: false,
        active: true,
        display_order: 10
    },
    {
        game_id: "asv1",
        sku: "BS-BLD-002",
        name: "Automobile Stealer V",
        studio_id: "bstar-north",
        build: "v5.0.1-dev",
        platform: "PC / Dev Kit",
        size_mb: 61770,
        classified: false,
        active: true,
        display_order: 20
    },
    {
        game_id: "rdos2",
        sku: "BS-BLD-003",
        name: "Red Dirt Outlaw Simulator 2",
        studio_id: "bstar-sandiego",
        build: "v2.0.0-dev",
        platform: "PC / Dev Kit",
        size_mb: 73540,
        classified: false,
        active: true,
        display_order: 30
    },
    {
        game_id: "mp3",
        sku: "BS-BLD-004",
        name: "Maximum Pain 3",
        studio_id: "bstar-toronto",
        build: "v3.1.4-dev",
        platform: "PC / Dev Kit",
        size_mb: 39680,
        classified: false,
        active: true,
        display_order: 40
    },
    {
        game_id: "gta7",
        sku: "BS-NDA-777",
        name: "Grand Theft Aunty VII",
        studio_id: "bstar-vault",
        build: "UNRELEASED / INTERNAL-ONLY",
        platform: "Classified",
        size_mb: 94210,
        classified: true,
        flag: serviceFlag,
        active: true,
        display_order: 99
    }
];

builds.forEach(b => {
    targetDb.builds.updateOne(
        { game_id: b.game_id },
        {
            $set: Object.assign({}, b, { updated_at: nowIso }),
            $setOnInsert: {
                dev_token: genDevToken(),
                created_at: nowIso
            }
        },
        { upsert: true }
    );
});

// --------------------------------------------------
// 5. Build Technical Specifications
// --------------------------------------------------

const buildSpecs = [
    { game_id: "bar1", spec_key: "engine_branch", spec_value: "rage-western-v1" },
    { game_id: "bar1", spec_key: "shader_cache", spec_value: "Vulkan / DX12 precompiled" },
    { game_id: "asv1", spec_key: "engine_branch", spec_value: "rage-metro-v5" },
    { game_id: "asv1", spec_key: "netcode", spec_value: "P2P Relay Mesh v3" },
    { game_id: "rdos2", spec_key: "engine_branch", spec_value: "rage-frontier-v2" },
    { game_id: "rdos2", spec_key: "weather_sim", spec_value: "Volumetric mud & dust v2.4" },
    { game_id: "mp3", spec_key: "engine_branch", spec_value: "rage-bullet-time-v3" },
    { game_id: "mp3", spec_key: "physics", spec_value: "Euphoria Ragdoll 3.1" },
    { game_id: "gta7", spec_key: "engine_branch", spec_value: "rage-next-chappal-physics" },
    { game_id: "gta7", spec_key: "security_tier", spec_value: "Executive NDA Token Required" }
];

buildSpecs.forEach(spec => {
    targetDb.build_specs.updateOne(
        { game_id: spec.game_id, spec_key: spec.spec_key },
        { $set: spec },
        { upsert: true }
    );
});

// --------------------------------------------------
// 6. Internal QA Tickets
// --------------------------------------------------

const qaTickets = [
    {
        ticket_id: 2001,
        game_id: "bar1",
        reporter_alias: "qa_arjun",
        severity: 3,
        title: "Horse animations desync on steep slopes",
        notes: "Reproducible when galloping up 80-degree inclines near canyon pass.",
        verified_build: true,
        created_at: "2026-08-14T11:20:00Z"
    },
    {
        ticket_id: 2002,
        game_id: "asv1",
        reporter_alias: "net_kavya",
        severity: 2,
        title: "Lobby migration timeout under high packet loss",
        notes: "Session host handoff takes >8s when latency exceeds 180ms.",
        verified_build: true,
        created_at: "2026-09-02T15:45:00Z"
    },
    {
        ticket_id: 2003,
        game_id: "rdos2",
        reporter_alias: "gfx_rohan",
        severity: 4,
        title: "Lantern reflections flicker in rain",
        notes: "Screen-space reflections clip when camera pitch is below -35 degrees.",
        verified_build: true,
        created_at: "2026-09-19T09:10:00Z"
    },
    {
        ticket_id: 2004,
        game_id: "mp3",
        reporter_alias: "phys_meera",
        severity: 3,
        title: "Slow-motion dive clips through glass doors",
        notes: "Collision capsule shrinks by 15% during dive transition.",
        verified_build: true,
        created_at: "2026-10-01T18:05:00Z"
    }
];

qaTickets.forEach(ticket => {
    targetDb.qa_tickets.updateOne(
        { ticket_id: ticket.ticket_id },
        { $setOnInsert: ticket },
        { upsert: true }
    );
});

// --------------------------------------------------
// 7. Internal CDN Mirrors
// --------------------------------------------------

const cdnMirrors = [
    { mirror_id: "MAA-CDN-01", warehouse_code: "IN-SOUTH", capacity_tb: 240, active: true },
    { mirror_id: "EDI-CDN-01", warehouse_code: "UK-NORTH", capacity_tb: 500, active: true },
    { mirror_id: "SJC-CDN-02", warehouse_code: "US-WEST", capacity_tb: 650, active: true },
    { mirror_id: "NDA-VAULT-00", warehouse_code: "AIRGAPPED", capacity_tb: 120, active: true }
];

cdnMirrors.forEach(mirror => {
    targetDb.cdn_mirrors.updateOne(
        { mirror_id: mirror.mirror_id },
        { $set: Object.assign({}, mirror, { updated_at: nowIso }) },
        { upsert: true }
    );
});

print(`[blockstar-seed] Seeded ${dbName} collections and indexes successfully.`);
