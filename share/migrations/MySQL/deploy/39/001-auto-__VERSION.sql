-- 
-- Created by SQL::Translator::Producer::MySQL
-- Created on Mon Apr  9 08:55:00 2018
-- 
;
SET foreign_key_checks=0;
--
-- Table: `dbix_class_deploymenthandler_versions`
--
CREATE TABLE `dbix_class_deploymenthandler_versions` (
  `id` integer NOT NULL auto_increment,
  `version` varchar(50) NOT NULL,
  `ddl` text NULL,
  `upgrade_sql` text NULL,
  PRIMARY KEY (`id`),
  UNIQUE `dbix_class_deploymenthandler_versions_version` (`version`)
);
SET foreign_key_checks=1;
