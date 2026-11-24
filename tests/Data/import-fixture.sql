-- Fixture in the closehub-connector-export format (MySQL syntax, one statement per ';' line end).
SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS `wp_sbx_fixture`;
CREATE TABLE `wp_sbx_fixture` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `txt` longtext COLLATE utf8mb4_unicode_520_ci,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
INSERT INTO `wp_sbx_fixture` (`id`, `txt`) VALUES
('1', 'it\'s \"quoted\" \\ back\nslash 100% ñ €;'),
('2', NULL),
('3', 'a:1:{s:3:\"key\";s:5:\"value\";}');
SET FOREIGN_KEY_CHECKS = 1;
