-- Player Wagons Table
CREATE TABLE IF NOT EXISTS `rex_wagons` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `citizen_id` varchar(50) NOT NULL,
  `wagon_id` varchar(50) NOT NULL,
  `model` varchar(50) NOT NULL,
  `plate` varchar(8) NOT NULL,
  `label` varchar(100) DEFAULT NULL,
  `price` int(11) DEFAULT 0,
  `storage` int(11) DEFAULT 10000,
  `slots` int(11) DEFAULT 1,
  `description` longtext DEFAULT NULL,
  `stored` tinyint(1) DEFAULT 0,
  `storage_shop` varchar(50) DEFAULT 'valentine',
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `is_active` tinyint(1) DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `plate` (`plate`),
  KEY `idx_citizen_id` (`citizen_id`),
  KEY `idx_plate` (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;