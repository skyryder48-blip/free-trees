-- ============================================================
-- QBX FORESTRY - DATABASE INSTALL
-- Run once on fresh install. Safe to re-run (IF NOT EXISTS).
-- ============================================================

CREATE TABLE IF NOT EXISTS forestry_players (
    citizenid VARCHAR(50) PRIMARY KEY,
    forestry_xp INT NOT NULL DEFAULT 0,
    forestry_level INT NOT NULL DEFAULT 0,
    woodworking_xp INT NOT NULL DEFAULT 0,
    woodworking_level INT NOT NULL DEFAULT 0,
    licenses JSON NOT NULL DEFAULT '{}',
    statistics JSON NOT NULL DEFAULT ('{"trees_felled":0,"logs_processed":0,"lumber_produced":0,"furniture_crafted":0,"contracts_completed":0,"total_earned":0}'),
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS forestry_permits (
    id INT AUTO_INCREMENT PRIMARY KEY,
    citizenid VARCHAR(50) NOT NULL,
    purchased_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at DATETIME NOT NULL,
    UNIQUE KEY idx_citizen (citizenid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS forestry_felled_trees (
    tree_key VARCHAR(100) PRIMARY KEY,
    model_hash BIGINT NOT NULL,
    felled_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    respawns_at DATETIME NOT NULL,
    INDEX idx_respawn (respawns_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS forestry_contracts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    item_name VARCHAR(50) NOT NULL,
    species VARCHAR(30) NULL,
    quantity INT NOT NULL,
    quantity_filled INT NOT NULL DEFAULT 0,
    price_per_unit INT NOT NULL,
    deadline DATETIME NOT NULL,
    fulfilled BOOLEAN NOT NULL DEFAULT FALSE,
    fulfilled_by VARCHAR(50) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_active (fulfilled, deadline),
    INDEX idx_item (item_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS forestry_market (
    item_name VARCHAR(50) PRIMARY KEY,
    base_price INT NOT NULL,
    current_price INT NOT NULL,
    supply INT NOT NULL DEFAULT 0,
    demand INT NOT NULL DEFAULT 100,
    last_updated DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS forestry_export_multipliers (
    species VARCHAR(30) PRIMARY KEY,
    multiplier DECIMAL(3,1) NOT NULL DEFAULT 1.0,
    rotated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS forestry_furniture_export (
    category VARCHAR(30) PRIMARY KEY,
    multiplier DECIMAL(3,1) NOT NULL DEFAULT 1.0,
    rotated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Seed market prices
INSERT IGNORE INTO forestry_market (item_name, base_price, current_price) VALUES
    ('lumber_rough', 30, 30),
    ('lumber_edged', 50, 50),
    ('lumber_finished', 80, 80),
    ('veneer_sheet', 60, 60),
    ('plywood_sheet', 120, 120),
    ('specialty_cut', 150, 150),
    ('turpentine', 60, 60);

-- Seed export multipliers (default 1.0)
INSERT IGNORE INTO forestry_export_multipliers (species, multiplier) VALUES
    ('pine', 1.0), ('oak', 1.0), ('birch', 1.0),
    ('redwood', 1.0), ('cedar', 1.0), ('maple', 1.0);

-- Seed furniture export multipliers
INSERT IGNORE INTO forestry_furniture_export (category, multiplier) VALUES
    ('seating', 1.0), ('tables', 1.0), ('storage', 1.0),
    ('specialty', 1.5), ('utility', 1.0);
