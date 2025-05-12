#!/bin/bash
# 数据库初始化脚本
# 用于创建数据库和必要的用户权限
# 作者：电影推荐系统团队
# 日期：2025-05-10

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
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD:-""}
DB_NAME=${DB_NAME:-"douban"}
DB_USER=${DB_USER:-"douban_user"}
DB_PASSWORD=${DB_PASSWORD:-"MySQL_20050816Zln@233"}
VENV_DIR="/opt/recommender/venv"

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

# 首先运行MySQL检查脚本，确保MySQL服务已启动且正确配置
log_info "确保MySQL服务已启动和配置..." | tee -a "$LOG_FILE"
if [ -f "$SCRIPT_DIR/init_mysql.sh" ]; then
    bash "$SCRIPT_DIR/init_mysql.sh" | tee -a "$LOG_FILE"
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        log_error "MySQL检查失败，请修复MySQL问题后重试" | tee -a "$LOG_FILE"
        exit 1
    fi
    
    # 从配置文件读取用户名和密码
    CONFIG_FILE="$PROJECT_ROOT/config/database.conf"
    if [ -f "$CONFIG_FILE" ]; then
        DB_USER=$(grep -A10 '\[database\]' "$CONFIG_FILE" | grep "user" | head -1 | cut -d'=' -f2 | tr -d ' ')
        DB_PASSWORD=$(grep -A10 '\[database\]' "$CONFIG_FILE" | grep "password" | head -1 | cut -d'=' -f2 | tr -d ' ')
        DB_NAME=$(grep -A10 '\[database\]' "$CONFIG_FILE" | grep "db" | head -1 | cut -d'=' -f2 | tr -d ' ')
    fi
else
    log_warning "MySQL检查脚本不存在，跳过MySQL检查" | tee -a "$LOG_FILE"
    # 如果没有提供ROOT密码，尝试交互式获取
    if [ -z "$DB_ROOT_PASSWORD" ]; then
        log_info "请输入MySQL root密码（如果没有请直接按回车）:" | tee -a "$LOG_FILE"
        read -s DB_ROOT_PASSWORD
        echo ""
    fi
fi

# 构建MySQL命令
if [ -z "$DB_ROOT_PASSWORD" ]; then
    MYSQL_CMD="mysql -h${DB_HOST} -P${DB_PORT} -uroot"
else
    MYSQL_CMD="mysql -h${DB_HOST} -P${DB_PORT} -uroot -p${DB_ROOT_PASSWORD}"
fi

# 检查MySQL客户端是否可用
if ! command -v mysql &> /dev/null; then
    log_error "找不到MySQL客户端，请先安装 MySQL 客户端工具" | tee -a "$LOG_FILE"
    log_info "可以使用: sudo apt install -y mysql-client" | tee -a "$LOG_FILE"
    exit 1
fi

# 检查能否连接到MySQL服务器
log_info "检查MySQL连接..." | tee -a "$LOG_FILE"
if ! $MYSQL_CMD -e "SELECT 1" &>/dev/null; then
    log_error "无法连接到MySQL服务器，请检查配置和密码" | tee -a "$LOG_FILE"
    
    # 尝试不带密码连接
    if [ ! -z "$DB_ROOT_PASSWORD" ] && mysql -h${DB_HOST} -P${DB_PORT} -uroot -e "SELECT 1" &>/dev/null; then
        log_info "成功通过无密码连接到MySQL，将以无密码方式继续" | tee -a "$LOG_FILE"
        MYSQL_CMD="mysql -h${DB_HOST} -P${DB_PORT} -uroot"
    # 尝试通过socket连接
    elif mysql -uroot -S /var/run/mysqld/mysqld.sock -e "SELECT 1" &>/dev/null; then
        log_info "成功通过socket连接到MySQL，将以socket方式继续" | tee -a "$LOG_FILE"
        MYSQL_CMD="mysql -uroot -S /var/run/mysqld/mysqld.sock"
    # 尝试使用配置的用户直接连接
    elif mysql -h${DB_HOST} -P${DB_PORT} -u${DB_USER} -p${DB_PASSWORD} -e "SELECT 1" &>/dev/null; then
        log_info "成功使用 $DB_USER 用户连接到MySQL，将直接使用此用户" | tee -a "$LOG_FILE"
        # 检查是否已存在数据库
        if mysql -h${DB_HOST} -P${DB_PORT} -u${DB_USER} -p${DB_PASSWORD} -e "SHOW DATABASES LIKE '$DB_NAME';" | grep -q "$DB_NAME"; then
            log_info "数据库 $DB_NAME 已存在，将直接使用" | tee -a "$LOG_FILE"
            # 跳转到数据导入部分
            goto_data_import=true
        else
            log_error "数据库 $DB_NAME 不存在，且当前用户可能没有创建数据库的权限" | tee -a "$LOG_FILE"
            exit 1
        fi
    else
        log_error "无法以任何方式连接到MySQL，请检查MySQL服务是否运行" | tee -a "$LOG_FILE"
        exit 1
    fi
fi

# 创建数据库和用户
if [ "$goto_data_import" != "true" ]; then
    log_info "创建数据库及用户..." | tee -a "$LOG_FILE"

    # 尝试创建数据库
    if ! $MYSQL_CMD -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>> "$LOG_FILE"; then
        log_error "创建数据库失败" | tee -a "$LOG_FILE"
        exit 1
    fi

    # 尝试创建用户和授权
    if ! $MYSQL_CMD -e "CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';" 2>> "$LOG_FILE" || \
       ! $MYSQL_CMD -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'%';" 2>> "$LOG_FILE" || \
       ! $MYSQL_CMD -e "FLUSH PRIVILEGES;" 2>> "$LOG_FILE"; then
        log_error "创建用户或授权失败" | tee -a "$LOG_FILE"
        exit 1
    fi

    log_info "数据库和用户创建成功" | tee -a "$LOG_FILE"
fi

# 验证新创建的用户可以连接数据库
log_info "验证数据库用户连接..." | tee -a "$LOG_FILE"
if ! mysql -h${DB_HOST} -P${DB_PORT} -u${DB_USER} -p${DB_PASSWORD} -e "USE \`$DB_NAME\`; SELECT 1;" &>/dev/null; then
    log_error "无法使用新创建的用户连接数据库，请检查权限" | tee -a "$LOG_FILE"
    exit 1
fi

# 为movie_link_list表创建基本结构
log_info "创建基本数据表结构..." | tee -a "$LOG_FILE"
mysql -h${DB_HOST} -P${DB_PORT} -u${DB_USER} -p${DB_PASSWORD} $DB_NAME -e "
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
mysql -h${DB_HOST} -P${DB_PORT} -u${DB_USER} -p${DB_PASSWORD} $DB_NAME -e "
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
    mysql -h${DB_HOST} -P${DB_PORT} -u${DB_USER} -p${DB_PASSWORD} $DB_NAME < "$TEST_DATA_DIR/sample_movies.sql" 2>> "$LOG_FILE"
    log_info "样本数据导入成功" | tee -a "$LOG_FILE"
else
    log_warning "样本数据文件不存在: $TEST_DATA_DIR/sample_movies.sql" | tee -a "$LOG_FILE"
fi

# 创建必要的应用表
log_info "创建应用所需的其他表..." | tee -a "$LOG_FILE"

# 用户信息表
mysql -h${DB_HOST} -P${DB_PORT} -u${DB_USER} -p${DB_PASSWORD} $DB_NAME -e "
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
mysql -h${DB_HOST} -P${DB_PORT} -u${DB_USER} -p${DB_PASSWORD} $DB_NAME -e "
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
mysql -h${DB_HOST} -P${DB_PORT} -u${DB_USER} -p${DB_PASSWORD} $DB_NAME -e "
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
mysql -h${DB_HOST} -P${DB_PORT} -u${DB_USER} -p${DB_PASSWORD} $DB_NAME -e "
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

# 检查虚拟环境是否存在，使用虚拟环境中的Python
if [ -d "$VENV_DIR" ] && [ -f "$VENV_DIR/bin/python" ]; then
    log_info "使用虚拟环境中的Python运行数据处理脚本..." | tee -a "$LOG_FILE"
    "$VENV_DIR/bin/python" data_spider/create_target_table.py 2>> "$LOG_FILE" || log_warning "数据处理脚本执行失败，非致命错误，继续执行" | tee -a "$LOG_FILE"
else
    # 尝试使用系统Python
    log_warning "虚拟环境不存在，尝试使用系统Python..." | tee -a "$LOG_FILE"
    python3 data_spider/create_target_table.py 2>> "$LOG_FILE" || log_warning "数据处理脚本执行失败，非致命错误，继续执行" | tee -a "$LOG_FILE"
fi

log_info "数据库初始化完成!" | tee -a "$LOG_FILE"
log_info "数据库名: $DB_NAME" | tee -a "$LOG_FILE"
log_info "用户名: $DB_USER" | tee -a "$LOG_FILE"
log_info "现在可以启动电影推荐系统服务了!" | tee -a "$LOG_FILE" 