-- 创建数据库表结构
-- 作者：AI工程师
-- 日期：2023-05-20

-- 电影信息表
CREATE TABLE IF NOT EXISTS `douban_movie` (
    `id` INT UNSIGNED AUTO_INCREMENT,
    `title` VARCHAR(100) NOT NULL,
    `score` FLOAT,
    `num` INT,
    `link` VARCHAR(200) NOT NULL,
    `time` DATE,
    `address` VARCHAR(50),
    `other_release` VARCHAR(100),
    `actors` VARCHAR(1000),
    PRIMARY KEY (`id`),
    UNIQUE KEY `idx_link` (`link`) 
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 用户信息表
CREATE TABLE IF NOT EXISTS `user_info` (
    `id` INT UNSIGNED AUTO_INCREMENT,
    `wx_id` VARCHAR(100) NOT NULL,
    `start_time` BIGINT,
    PRIMARY KEY (`id`),
    UNIQUE KEY `idx_wx_id` (`wx_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 用户搜索记录表
CREATE TABLE IF NOT EXISTS `seek_movie` (
    `id` INT UNSIGNED AUTO_INCREMENT,
    `user_id` INT NOT NULL,
    `movie_id` INT NOT NULL,
    `seek_time` BIGINT,
    PRIMARY KEY (`id`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_movie_id` (`movie_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 用户评分表
CREATE TABLE IF NOT EXISTS `like_movie` (
    `id` INT UNSIGNED AUTO_INCREMENT,
    `user_id` INT NOT NULL,
    `movie_id` INT NOT NULL,
    `liking` FLOAT,
    PRIMARY KEY (`id`),
    UNIQUE KEY `idx_user_movie` (`user_id`, `movie_id`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_movie_id` (`movie_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 添加外键约束（可选，如果需要强制引用完整性）
-- ALTER TABLE `seek_movie` ADD CONSTRAINT `fk_seek_user` FOREIGN KEY (`user_id`) REFERENCES `user_info` (`id`) ON DELETE CASCADE;
-- ALTER TABLE `seek_movie` ADD CONSTRAINT `fk_seek_movie` FOREIGN KEY (`movie_id`) REFERENCES `douban_movie` (`id`) ON DELETE CASCADE;
-- ALTER TABLE `like_movie` ADD CONSTRAINT `fk_like_user` FOREIGN KEY (`user_id`) REFERENCES `user_info` (`id`) ON DELETE CASCADE;
-- ALTER TABLE `like_movie` ADD CONSTRAINT `fk_like_movie` FOREIGN KEY (`movie_id`) REFERENCES `douban_movie` (`id`) ON DELETE CASCADE; 