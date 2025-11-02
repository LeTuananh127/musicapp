SET FOREIGN_KEY_CHECKS=0;
LOCK TABLES `tracks` WRITE;
/*!40000 ALTER TABLE `tracks` DISABLE KEYS */;
INSERT IGNORE INTO `tracks` VALUES
(87223,'Phoenix',NULL,10933,29000,'https://cdnt-preview.dzcdn.net/api/1/1/b/0/d/0/b0d7ed1caaeddaba89c1468f78987bbc.mp3?hdnea=exp=1760073965~acl=/api/1/1/b/0/d/0/b0d7ed1caaeddaba89c1468f78987bbc.mp3*~data=user_id=0,application_id=42~hmac=0555afb18fde490c23eda0128c5c12a31a2c302f7c44936552af3f427fa0da85',0,'https://cdn-images.dzcdn.net/images/cover/b870579c8650cd59b1cce656dde2ef17/250x250-000000-80-0-0.jpg',NULL,NULL,NULL,0),
(224415,'Breaking the Back',61638,19586,29000,'https://cdnt-preview.dzcdn.net/api/1/1/6/d/1/0/6d1c61ab981b23590ec4e9bb6af203ca.mp3?hdnea=exp=1761722628~acl=/api/1/1/6/d/1/0/6d1c61ab981b23590ec4e9bb6af203ca.mp3*~data=user_id=0,application_id=42~hmac=78b5aba0d4d891bd527806a7b7a2801dbca8525f6c077ac2298aabe0967139dd',0,'https://api.deezer.com/album/11864402/image',NULL,NULL,NULL,6),
(213035,'So Contagious (Album Version)',56222,17652,29000,'https://cdnt-preview.dzcdn.net/api/1/1/3/d/c/0/3dc16ac0621a00b9f802ae96c6bd21db.mp3?hdnea=exp=1760500053~acl=/api/1/1/3/d/c/0/3dc16ac0621a00b9f802ae96c6bd21db.mp3*~data=user_id=0,application_id=42~hmac=da975e92578ddb4793f36ac6cabc7ca9c3fb6708f0e57e32bd842ad0af4c0cc9',0,'https://api.deezer.com/album/72933/image',NULL,NULL,NULL,0),
(224400,'Without Someone',61625,17629,29000,'https://cdnt-preview.dzcdn.net/api/1/1/e/2/9/0/e2972a71513d0bc50c9f6b9ded55c8df.mp3?hdnea=exp=1761723844~acl=/api/1/1/e/2/9/0/e2972a71513d0bc50c9f6b9ded55c8df.mp3*~data=user_id=0,application_id=42~hmac=029d3997282d7596fdc30245b5106cce2231af737b8fe14e799d81459dda7968',0,'https://api.deezer.com/album/11674560/image',NULL,NULL,NULL,3),
(224356,'Falling to Pieces',61603,19581,29000,'https://cdnt-preview.dzcdn.net/api/1/1/2/3/7/0/2371326cd399f1901611ba1258e93f59.mp3?hdnea=exp=1760584478~acl=/api/1/1/2/3/7/0/2371326cd399f1901611ba1258e93f59.mp3*~data=user_id=0,application_id=42~hmac=233bbfb27e587b017116e26200adb5bc173680c25c987e5ddefa39fdb258c4c1',0,'https://api.deezer.com/album/11329500/image',NULL,NULL,NULL,0);
/*!40000 ALTER TABLE `tracks` ENABLE KEYS */;
UNLOCK TABLES;
SET FOREIGN_KEY_CHECKS=1;
