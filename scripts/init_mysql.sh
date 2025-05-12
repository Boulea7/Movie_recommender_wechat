#!/bin/bash
# MySQL服务初始化与检查脚本
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

log_info "开始检查MySQL服务..."

# 检查MySQL是否已安装
if ! command -v mysql &> /dev/null; then
    log_warning "MySQL客户端未安装，正在安装..."
    apt update
    apt install -y mysql-client
    
    if [ $? -ne 0 ]; then
        log_error "安装MySQL客户端失败！"
        exit 1
    fi
fi

# 检查MySQL服务器是否已安装
if ! command -v mysqld &> /dev/null; then
    if ! dpkg -l | grep -q "mysql-server"; then
        log_warning "MySQL服务器未安装，正在安装..."
        apt update
        apt install -y mysql-server
        
        if [ $? -ne 0 ]; then
            log_error "安装MySQL服务器失败！"
            exit 1
        fi
    fi
fi

# 检查MySQL服务是否正在运行
if ! systemctl is-active --quiet mysql; then
    log_warning "MySQL服务未运行，正在启动..."
    systemctl start mysql
    
    if [ $? -ne 0 ]; then
        log_error "启动MySQL服务失败！"
        systemctl status mysql
        exit 1
    fi
    
    # 设置MySQL服务开机自启
    systemctl enable mysql
fi

log_info "MySQL服务状态检查："
systemctl status mysql --no-pager

# 尝试使用不同的用户访问MySQL
log_info "检查MySQL root用户访问权限..."

# 尝试无密码方式
if mysql -u root -e "SELECT VERSION();" &>/dev/null; then
    log_info "MySQL root用户无密码登录成功"
    ROOT_ACCESS="no_password"
# 尝试socket方式
elif mysql -u root -S /var/run/mysqld/mysqld.sock -e "SELECT VERSION();" &>/dev/null; then
    log_info "MySQL root用户通过socket登录成功"
    ROOT_ACCESS="socket"
else
    log_warning "无法使用root用户免密码登录MySQL，可能需要输入密码"
    ROOT_ACCESS="password"
    
    # 从配置文件读取用户名和密码
    CONFIG_FILE="/opt/recommender/config/database.conf"
    if [ -f "$CONFIG_FILE" ]; then
        DB_USER=$(grep -A10 '\[database\]' "$CONFIG_FILE" | grep "user" | head -1 | cut -d'=' -f2 | tr -d ' ')
        DB_PASS=$(grep -A10 '\[database\]' "$CONFIG_FILE" | grep "password" | head -1 | cut -d'=' -f2 | tr -d ' ')
        DB_NAME=$(grep -A10 '\[database\]' "$CONFIG_FILE" | grep "db" | head -1 | cut -d'=' -f2 | tr -d ' ')
        
        log_info "尝试使用配置文件中的凭据连接MySQL..."
        if mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME; SELECT 1;" &>/dev/null; then
            log_info "使用$DB_USER用户连接成功"
        else
            log_warning "使用$DB_USER用户连接失败，可能需要创建用户或修改密码"
        fi
    fi
fi

# 获取MySQL版本
MYSQL_VERSION=$(mysql --version | awk '{print $3}')
log_info "MySQL版本: $MYSQL_VERSION"

# 检查数据库配置
DB_NAME=${DB_NAME:-"douban"}
DB_USER=${DB_USER:-"douban_user"}
DB_PASS=${DB_PASS:-"MySQL_20050816Zln@233"}

log_info "检查数据库 $DB_NAME 是否存在..."

# 根据可用的访问方式创建数据库和用户
if [ "$ROOT_ACCESS" = "no_password" ]; then
    # 检查数据库是否存在
    if ! mysql -u root -e "USE $DB_NAME;" &>/dev/null; then
        log_info "创建数据库 $DB_NAME..."
        mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    else
        log_info "数据库 $DB_NAME 已存在"
    fi
    
    # 创建或更新用户
    log_info "确保用户 $DB_USER 存在且有正确权限..."
    mysql -u root << EOF
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'%';
FLUSH PRIVILEGES;
EOF
elif [ "$ROOT_ACCESS" = "socket" ]; then
    # 检查数据库是否存在
    if ! mysql -u root -S /var/run/mysqld/mysqld.sock -e "USE $DB_NAME;" &>/dev/null; then
        log_info "创建数据库 $DB_NAME..."
        mysql -u root -S /var/run/mysqld/mysqld.sock -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    else
        log_info "数据库 $DB_NAME 已存在"
    fi
    
    # 创建或更新用户
    log_info "确保用户 $DB_USER 存在且有正确权限..."
    mysql -u root -S /var/run/mysqld/mysqld.sock << EOF
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'%';
FLUSH PRIVILEGES;
EOF
else
    log_warning "无法以root用户免密码方式登录MySQL，请手动确保数据库和用户正确配置"
    log_info "您可以通过以下SQL命令创建数据库和用户："
    echo "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    echo "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
    echo "CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASS';"
    echo "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';"
    echo "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'%';"
    echo "FLUSH PRIVILEGES;"
fi

# 最终验证连接
log_info "验证 $DB_USER 用户连接到 $DB_NAME 数据库..."
if mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME; SELECT 1;" &>/dev/null; then
    log_info "连接成功！MySQL服务已正确配置"
else
    log_error "验证连接失败，请检查用户名、密码和权限"
    exit 1
fi

# 显示MySQL状态信息
log_info "MySQL服务器状态："
mysqladmin -u "$DB_USER" -p"$DB_PASS" status

log_info "MySQL初始化和检查完成！"
log_info "数据库名: $DB_NAME"
log_info "用户名: $DB_USER"
log_info "密码: $DB_PASS" 