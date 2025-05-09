#!/bin/bash
# 数据库初始化脚本
# 用于创建数据库和必要的用户权限
# 作者：电影推荐系统团队
# 日期：2023-05-20

set -e  # 遇到错误立即退出

# 日志颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无色

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}"
}

log_error() {
    echo -e "${RED}[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}" >&2
}

# 配置参数
DB_HOST=${DB_HOST:-"localhost"}
DB_PORT=${DB_PORT:-"3306"}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD:-"186386"}
DB_NAME=${DB_NAME:-"douban"}
DB_USER=${DB_USER:-"douban_user"}
DB_PASSWORD=${DB_PASSWORD:-"MySQL_20050816Zln@233"}

MYSQL_CMD="mysql -h${DB_HOST} -P${DB_PORT} -uroot -p${DB_ROOT_PASSWORD}"

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( dirname "$SCRIPT_DIR" )"
SQL_DIR="$PROJECT_ROOT/sql"
TEST_DATA_DIR="$PROJECT_ROOT/test_data"

# 创建日志目录
mkdir -p "$PROJECT_ROOT/logs"
LOG_FILE="$PROJECT_ROOT/logs/db_init_$(date '+%Y%m%d%H%M%S').log"

log_info "初始化数据库脚本开始执行..." | tee -a "$LOG_FILE"
log_info "项目根目录: $PROJECT_ROOT" | tee -a "$LOG_FILE"

# 检查MySQL客户端是否可用
if ! command -v mysql &> /dev/null; then
    log_error "找不到MySQL客户端，请先安装 MySQL 客户端工具" | tee -a "$LOG_FILE"
    exit 1
fi

# 检查能否连接到MySQL服务器
log_info "检查MySQL连接..." | tee -a "$LOG_FILE"
if ! $MYSQL_CMD -e "SELECT 1" &>/dev/null; then
    log_error "无法连接到MySQL服务器，请检查配置和密码" | tee -a "$LOG_FILE"
    exit 1
fi

# 创建数据库和用户
log_info "创建数据库及用户..." | tee -a "$LOG_FILE"
$MYSQL_CMD -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>> "$LOG_FILE"
$MYSQL_CMD -e "CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';" 2>> "$LOG_FILE"
$MYSQL_CMD -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'%';" 2>> "$LOG_FILE"
$MYSQL_CMD -e "FLUSH PRIVILEGES;" 2>> "$LOG_FILE"

log_info "数据库和用户创建成功" | tee -a "$LOG_FILE"

# 为movie_link_list表创建基本结构
log_info "创建基本数据表结构..." | tee -a "$LOG_FILE"
$MYSQL_CMD $DB_NAME -e "
CREATE TABLE IF NOT EXISTS movie_link_list (
    id INT AUTO_INCREMENT PRIMARY KEY,
    link VARCHAR(200) NOT NULL,
    title VARCHAR(100) NOT NULL,
    score VARCHAR(10),
    num VARCHAR(20),
    time VARCHAR(50),
    actors TEXT
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
" 2>> "$LOG_FILE"

# 创建备份表结构
$MYSQL_CMD $DB_NAME -e "
CREATE TABLE IF NOT EXISTS douban_mov_bak (
    id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(100) NOT NULL,
    score VARCHAR(10),
    num VARCHAR(20),
    link VARCHAR(200) NOT NULL,
    time VARCHAR(50),
    actors TEXT
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
" 2>> "$LOG_FILE"

# 导入样本数据
if [[ -f "$TEST_DATA_DIR/sample_movies.sql" ]]; then
    log_info "导入样本电影数据..." | tee -a "$LOG_FILE"
    $MYSQL_CMD $DB_NAME < "$TEST_DATA_DIR/sample_movies.sql" 2>> "$LOG_FILE"
    log_info "样本数据导入成功" | tee -a "$LOG_FILE"
else
    log_warning "样本数据文件不存在: $TEST_DATA_DIR/sample_movies.sql" | tee -a "$LOG_FILE"
fi

# 创建必要的应用表
log_info "创建应用所需的其他表..." | tee -a "$LOG_FILE"

# 用户信息表
$MYSQL_CMD $DB_NAME -e "
CREATE TABLE IF NOT EXISTS user_info (
    id INT AUTO_INCREMENT PRIMARY KEY,
    wx_id VARCHAR(50) NOT NULL UNIQUE,
    start_time INT NOT NULL,
    last_time INT NOT NULL DEFAULT 0,
    nickname VARCHAR(50),
    avatar VARCHAR(200),
    INDEX (wx_id)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
" 2>> "$LOG_FILE"

# 用户评分表
$MYSQL_CMD $DB_NAME -e "
CREATE TABLE IF NOT EXISTS like_movie (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    movie_id INT NOT NULL,
    liking FLOAT DEFAULT NULL,
    INDEX (user_id),
    INDEX (movie_id),
    UNIQUE KEY user_movie (user_id, movie_id)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
" 2>> "$LOG_FILE"

# 搜索记录表
$MYSQL_CMD $DB_NAME -e "
CREATE TABLE IF NOT EXISTS seek_movie (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    movie_id INT NOT NULL,
    seek_time INT NOT NULL,
    INDEX (user_id),
    INDEX (movie_id)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
" 2>> "$LOG_FILE"

# 主电影表
$MYSQL_CMD $DB_NAME -e "
CREATE TABLE IF NOT EXISTS douban_movie (
    id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(100) NOT NULL,
    score FLOAT DEFAULT NULL,
    num INT DEFAULT 0,
    link VARCHAR(200) DEFAULT NULL,
    time VARCHAR(50) DEFAULT NULL,
    address VARCHAR(200) DEFAULT NULL,
    other_address VARCHAR(200) DEFAULT NULL,
    actors TEXT,
    director VARCHAR(100) DEFAULT NULL,
    category VARCHAR(50) DEFAULT NULL,
    INDEX (title)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
" 2>> "$LOG_FILE"

# 运行电影数据处理脚本
log_info "处理电影数据..." | tee -a "$LOG_FILE"
cd "$PROJECT_ROOT"
python3 data_spider/create_target_table.py 2>> "$LOG_FILE"

log_info "数据库初始化完成!" | tee -a "$LOG_FILE" 