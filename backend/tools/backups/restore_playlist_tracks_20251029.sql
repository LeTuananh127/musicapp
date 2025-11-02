LOCK TABLES `playlist_tracks` WRITE;
/*!40000 ALTER TABLE `playlist_tracks` DISABLE KEYS */;
INSERT INTO `playlist_tracks` (`playlist_id`,`track_id`,`position`,`added_at`) VALUES
(2,87223,0,'2025-10-13 04:41:44'),
(5,224415,0,'2025-10-23 03:08:07'),
(6,213035,1,'2025-10-23 07:29:03'),
(6,224400,0,'2025-10-23 07:06:37'),
(11,224356,0,'2025-10-28 08:53:52');
/*!40000 ALTER TABLE `playlist_tracks` ENABLE KEYS */;
UNLOCK TABLES;
