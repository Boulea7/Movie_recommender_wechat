#!/bin/bash
# 电影推荐系统一体化部署脚本
# 作者：电影推荐系统团队
# 日期：2025-05-10
# 
# 此脚本整合了所有部署步骤，并自动处理常见的部署问题：
# 1. 端口问题：自动处理80/8080端口配置
# 2. 权限问题：自动设置绑定低端口特权
# 3. Python环境问题：使用虚拟环境解决依赖安装问题
# 4. 配置解析问题：确保ConfigParser包含必要的方法
# 5. 数据库问题：自动配置和启动MySQL服务

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

log_section() {
    echo ""
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${BLUE}>>> $1${NC}"
    echo -e "${BLUE}==================================================${NC}"
}

# 检查是否有root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用root用户或sudo运行此脚本"
        exit 1
    fi
}

# 检查依赖
check_dependency() {
    if ! command -v $1 &> /dev/null; then
        log_warning "$1 未安装，正在安装..."
        apt-get update
        apt-get install -y $1
        if [ $? -ne 0 ]; then
            log_error "安装 $1 失败！"
            exit 1
        fi
    fi
}

# 备份配置
backup_config() {
    if [ -f "$1" ]; then
        log_info "备份配置文件 $1 到 $1.bak"
        cp "$1" "$1.bak"
    fi
}

# 恢复配置
restore_config() {
    if [ -f "$1.bak" ]; then
        log_info "从备份恢复配置文件 $1"
        cp "$1.bak" "$1"
    fi
}

# 显示脚本头部
log_section "电影推荐系统一体化部署脚本"
log_info "开始部署电影推荐系统..."
log_info "此脚本将自动处理所有部署步骤并修复常见问题"

# 检查root权限
check_root

# 安装目录
INSTALL_DIR=${INSTALL_DIR:-"/opt/recommender"}
BACKUP_DIR="/opt/recommender_backups"
TIMESTAMP=$(date '+%Y%m%d%H%M%S')
PORT=${PORT:-80}
USE_NGINX=${USE_NGINX:-false}
CURRENT_DIR=$(pwd)

# 配置参数
log_section "设置部署参数"
log_info "项目目录: $CURRENT_DIR"
log_info "安装目录: $INSTALL_DIR"
log_info "端口配置: $PORT"
log_info "时间戳: $TIMESTAMP"

# 创建安装和备份目录
mkdir -p "$INSTALL_DIR"
mkdir -p "$BACKUP_DIR"
mkdir -p "$INSTALL_DIR/logs"

# 如果已有安装，备份它
if [ -d "$INSTALL_DIR" ] && [ "$(ls -A $INSTALL_DIR)" ]; then
    BACKUP_PATH="$BACKUP_DIR/backup_$TIMESTAMP"
    log_info "备份现有安装到 $BACKUP_PATH..."
    mkdir -p "$BACKUP_PATH"
    cp -R "$INSTALL_DIR"/* "$BACKUP_PATH" 2>/dev/null || true
fi

# 第一步：检查和安装系统依赖
log_section "安装系统依赖"
apt-get update

# 检查基本依赖
log_info "检查系统基本依赖..."
check_dependency python3
check_dependency python3-pip
check_dependency python3-venv
check_dependency mysql-client
check_dependency libmysqlclient-dev
check_dependency libcap2-bin
check_dependency curl
check_dependency jq
check_dependency netstat || check_dependency net-tools

# 安装更多系统依赖
log_info "安装所有必要的系统依赖..."
apt-get install -y python3 python3-pip python3-venv mysql-client libmysqlclient-dev libcap2-bin curl jq net-tools

# 第二步：配置MySQL服务
log_section "配置MySQL服务"
log_info "检查MySQL服务器是否已安装..."

# 检查MySQL服务器是否已安装
if ! command -v mysqld &> /dev/null; then
    if ! dpkg -l | grep -q "mysql-server"; then
        log_warning "MySQL服务器未安装，正在安装..."
        apt-get install -y mysql-server
    fi
fi

# 检查MySQL服务是否运行
log_info "确保MySQL服务正在运行..."
if ! systemctl is-active --quiet mysql; then
    log_warning "MySQL服务未运行，正在启动..."
    systemctl start mysql
    systemctl enable mysql
fi

# 第三步：复制项目文件
log_section "部署项目文件"
log_info "复制项目文件到安装目录..."
cp -R "$CURRENT_DIR"/* "$INSTALL_DIR/"

# 设置执行权限
log_info "设置脚本执行权限..."
chmod +x "$INSTALL_DIR/scripts/"*.sh
chmod +x "$INSTALL_DIR/web_server/"*.py
chmod +x "$INSTALL_DIR/data_spider/"*.py

# 第四步：创建和配置Python虚拟环境
log_section "配置Python环境"
VENV_DIR="$INSTALL_DIR/venv"
log_info "创建Python虚拟环境 $VENV_DIR..."

# 创建虚拟环境
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi

# 安装Python依赖
log_info "使用虚拟环境安装Python依赖..."
"$VENV_DIR/bin/pip" install --upgrade pip
"$VENV_DIR/bin/pip" install -r "$INSTALL_DIR/requirements.txt"

# 确保安装了web.py模块
if ! "$VENV_DIR/bin/pip" list | grep -q "web.py"; then
    log_warning "未找到web.py模块，正在安装..."
    "$VENV_DIR/bin/pip" install web.py
fi

# 第五步：检查ConfigParser类
log_section "检查配置解析器"
CONFIG_PARSER_FILE="$INSTALL_DIR/web_server/config_parser.py"

# 检查ConfigParser是否包含get_section方法
if [ -f "$CONFIG_PARSER_FILE" ]; then
    if ! grep -q "def get_section" "$CONFIG_PARSER_FILE"; then
        log_warning "ConfigParser类缺少get_section方法，正在添加..."
        # 创建临时文件
        TMP_FILE=$(mktemp)
        
        # 定位类内的适当位置并插入get_section方法
        awk '
        /class ConfigParser/{class_found=1}
        /def get_database_config/{if(class_found && !method_added) {
            print "    def get_section(self, section):"
            print "        \"\"\""
            print "        获取指定配置部分"
            print "        "
            print "        参数:"
            print "            section: 配置部分名称 (database, service, recommender)"
            print "        "
            print "        返回:"
            print "            dict: 配置部分字典"
            print "        \"\"\""
            print "        if section == '\''database'\'':"
            print "            return self.get_database_config()"
            print "        elif section == '\''service'\'':"
            print "            return self.get_service_config()"
            print "        elif section == '\''recommender'\'':"
            print "            return self.get_recommender_config()"
            print "        else:"
            print "            # 对于未知部分，尝试直接获取"
            print "            try:"
            print "                if section in self.config:"
            print "                    return dict(self.config[section])"
            print "                else:"
            print "                    print(f\"警告: 配置部分 {section} 不存在\")"
            print "                    return {}"
            print "            except Exception as e:"
            print "                print(f\"获取配置部分 {section} 出错: {str(e)}\")"
            print "                return {}"
            print ""
            method_added=1
        }}
        {print}
        ' "$CONFIG_PARSER_FILE" > "$TMP_FILE"
        
        # 备份原文件并应用更改
        cp "$CONFIG_PARSER_FILE" "${CONFIG_PARSER_FILE}.bak"
        mv "$TMP_FILE" "$CONFIG_PARSER_FILE"
        log_info "已添加get_section方法到ConfigParser类"
    else
        log_info "ConfigParser类已包含get_section方法"
    fi
else
    log_error "未找到ConfigParser文件: $CONFIG_PARSER_FILE"
    exit 1
fi

# 第六步：配置数据库
log_section "配置数据库"
DB_NAME="douban"
DB_USER="douban_user"
DB_PASS="MySQL_20050816Zln@233"

# 尝试使用root用户访问MySQL
log_info "配置数据库和用户..."
ROOT_ACCESS="unknown"

# 尝试无密码方式
if mysql -u root -e "SELECT VERSION();" &>/dev/null; then
    ROOT_ACCESS="no_password"
    log_info "MySQL root用户无密码登录成功"
    
    # 创建数据库和用户
    log_info "创建数据库和用户..."
    mysql -u root << EOF
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'%';
FLUSH PRIVILEGES;
EOF
# 尝试socket方式
elif mysql -u root -S /var/run/mysqld/mysqld.sock -e "SELECT VERSION();" &>/dev/null; then
    ROOT_ACCESS="socket"
    log_info "MySQL root用户通过socket登录成功"
    
    # 创建数据库和用户
    log_info "创建数据库和用户..."
    mysql -u root -S /var/run/mysqld/mysqld.sock << EOF
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'%';
FLUSH PRIVILEGES;
EOF
else
    ROOT_ACCESS="password"
    log_warning "无法以root用户免密码登录MySQL"
    
    # 尝试交互式获取密码
    log_info "请输入MySQL root密码（如果没有请直接按回车）:"
    read -s DB_ROOT_PASSWORD
    echo ""
    
    if [ -n "$DB_ROOT_PASSWORD" ]; then
        if mysql -u root -p"$DB_ROOT_PASSWORD" -e "SELECT VERSION();" &>/dev/null; then
            log_info "成功使用密码登录MySQL"
            
            # 创建数据库和用户
            log_info "创建数据库和用户..."
            mysql -u root -p"$DB_ROOT_PASSWORD" << EOF
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'%';
FLUSH PRIVILEGES;
EOF
        else
            log_error "无法连接到MySQL服务器，请检查root密码"
            log_warning "尝试使用配置的用户凭据..."
            
            # 尝试使用配置的用户连接
            if mysql -u "$DB_USER" -p"$DB_PASS" -e "SELECT VERSION();" &>/dev/null; then
                log_info "成功使用配置的用户凭据连接MySQL"
                
                # 尝试查询是否已存在数据库
                if mysql -u "$DB_USER" -p"$DB_PASS" -e "SHOW DATABASES LIKE '$DB_NAME';" | grep -q "$DB_NAME"; then
                    log_info "数据库 $DB_NAME 已存在"
                else
                    log_warning "数据库 $DB_NAME 不存在，但无法创建（需要root权限）"
                    log_warning "请手动创建数据库或提供正确的root密码"
                fi
            else
                log_error "无法连接到MySQL服务器，跳过数据库初始化"
                log_error "请在脚本完成后手动配置数据库"
            fi
        fi
    else
        log_warning "未提供root密码，跳过数据库初始化"
        log_warning "请在脚本完成后手动配置数据库"
    fi
fi

# 初始化数据库表
log_section "初始化数据库表"
if mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME; SELECT 1;" &>/dev/null; then
    log_info "成功连接到数据库，创建基本表结构..."
    
    # 创建必要的表
    mysql -u "$DB_USER" -p"$DB_PASS" $DB_NAME -e "
    CREATE TABLE IF NOT EXISTS movie_link_list (
        id INT AUTO_INCREMENT PRIMARY KEY,
        link VARCHAR(200) NOT NULL,
        title VARCHAR(100) NOT NULL,
        score VARCHAR(10),
        num VARCHAR(20),
        time VARCHAR(50),
        actors TEXT
    ) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    
    CREATE TABLE IF NOT EXISTS douban_mov_bak (
        id INT AUTO_INCREMENT PRIMARY KEY,
        title VARCHAR(100) NOT NULL,
        score VARCHAR(10),
        num VARCHAR(20),
        link VARCHAR(200) NOT NULL,
        time VARCHAR(50),
        actors TEXT
    ) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    
    CREATE TABLE IF NOT EXISTS user_info (
        id INT AUTO_INCREMENT PRIMARY KEY,
        wx_id VARCHAR(50) NOT NULL UNIQUE,
        start_time INT NOT NULL,
        last_time INT NOT NULL DEFAULT 0,
        nickname VARCHAR(50),
        avatar VARCHAR(200),
        INDEX (wx_id)
    ) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    
    CREATE TABLE IF NOT EXISTS like_movie (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        movie_id INT NOT NULL,
        liking FLOAT DEFAULT NULL,
        INDEX (user_id),
        INDEX (movie_id),
        UNIQUE KEY user_movie (user_id, movie_id)
    ) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    
    CREATE TABLE IF NOT EXISTS seek_movie (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        movie_id INT NOT NULL,
        seek_time INT NOT NULL,
        INDEX (user_id),
        INDEX (movie_id)
    ) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    
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
    "
    
    # 导入示例数据
    TEST_DATA_FILE="$INSTALL_DIR/test_data/sample_movies.sql"
    if [ -f "$TEST_DATA_FILE" ]; then
        log_info "导入示例电影数据..."
        mysql -u "$DB_USER" -p"$DB_PASS" $DB_NAME < "$TEST_DATA_FILE"
    fi
    
    # 处理数据
    log_info "运行数据处理脚本..."
    cd "$INSTALL_DIR"
    if [ -f "$INSTALL_DIR/data_spider/create_target_table.py" ]; then
        "$VENV_DIR/bin/python" "$INSTALL_DIR/data_spider/create_target_table.py" || log_warning "数据处理脚本执行失败，这是非致命错误，继续执行"
    fi
else
    log_error "无法连接到数据库，跳过表初始化"
    log_error "请在脚本完成后手动初始化数据库表"
fi

# 第七步：配置服务端口
log_section "配置服务端口"
CONFIG_FILE="$INSTALL_DIR/config/database.conf"

# 确保配置目录存在
mkdir -p "$INSTALL_DIR/config"

# 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    log_warning "配置文件不存在，创建默认配置..."
    cat > "$CONFIG_FILE" << EOF
[database]
host = localhost
port = 3306
user = $DB_USER
password = $DB_PASS
db = $DB_NAME
charset = utf8mb4
pool_size = 5
timeout = 60
reconnect_attempts = 3

[service]
port = $PORT
token = HelloMovieRecommender
encoding_key = X5hyGsEzWugANKlq9uDjtpGQZ40yL1axD9m147dPa1a
debug = false
log_level = INFO

[recommender]
similarity_threshold = 0.5
min_ratings = 3
max_recommendations = 10
EOF
else
    # 更新端口配置
    if grep -q "^\[service\]" "$CONFIG_FILE"; then
        if grep -q "^port" "$CONFIG_FILE"; then
            sed -i "s/^port = .*/port = $PORT/" "$CONFIG_FILE"
        else
            sed -i "/^\[service\]/a port = $PORT" "$CONFIG_FILE"
        fi
    else
        # 添加service部分
        echo "" >> "$CONFIG_FILE"
        echo "[service]" >> "$CONFIG_FILE"
        echo "port = $PORT" >> "$CONFIG_FILE"
        echo "token = HelloMovieRecommender" >> "$CONFIG_FILE"
        echo "encoding_key = X5hyGsEzWugANKlq9uDjtpGQZ40yL1axD9m147dPa1a" >> "$CONFIG_FILE"
        echo "debug = false" >> "$CONFIG_FILE"
        echo "log_level = INFO" >> "$CONFIG_FILE"
    fi
fi

# 第八步：检查并处理低端口绑定权限
log_section "配置端口绑定权限"
if [ "$PORT" -lt 1024 ]; then
    log_info "配置为使用低端口号: $PORT，需要特权权限"
    
    # 检查是否已有端口占用
    PORT_OCCUPIED=false
    if netstat -tuln | grep -q ":$PORT "; then
        log_warning "端口 $PORT 已被占用"
        PORT_OCCUPIED=true
    fi
    
    # 如果端口未被占用，尝试设置特权
    if [ "$PORT_OCCUPIED" = false ]; then
        log_info "尝试授予低端口绑定权限..."
        # 确保Python二进制文件存在
        PYTHON_BIN="$VENV_DIR/bin/python3"
        if [ ! -f "$PYTHON_BIN" ]; then
            PYTHON_BIN="$VENV_DIR/bin/python"
        fi
        
        # 设置权限
        if [ -f "$PYTHON_BIN" ]; then
            setcap 'cap_net_bind_service=+ep' "$PYTHON_BIN"
            
            # 验证权限设置
            if [ $? -eq 0 ]; then
                log_info "成功设置低端口绑定权限"
            else
                log_warning "设置绑定权限失败，将配置Nginx反向代理"
                USE_NGINX=true
                # 更新配置文件使用8080端口
                sed -i "s/^port = .*/port = 8080/" "$CONFIG_FILE"
            fi
        else
            log_warning "无法找到Python二进制文件，将配置Nginx反向代理"
            USE_NGINX=true
            # 更新配置文件使用8080端口
            sed -i "s/^port = .*/port = 8080/" "$CONFIG_FILE"
        fi
    else
        log_warning "端口已占用，将配置Nginx反向代理"
        USE_NGINX=true
        # 更新配置文件使用8080端口
        sed -i "s/^port = .*/port = 8080/" "$CONFIG_FILE"
    fi
fi

# 第九步：创建系统服务
log_section "创建系统服务"
SERVICE_FILE="/etc/systemd/system/movie-recommender.service"

# 获取正确的Python路径
PYTHON_BIN="$VENV_DIR/bin/python"
if [ ! -f "$PYTHON_BIN" ]; then
    PYTHON_BIN="$VENV_DIR/bin/python3"
fi

# 创建服务文件
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=电影推荐系统服务
After=network.target mysql.service
Wants=mysql.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$PYTHON_BIN $INSTALL_DIR/web_server/main.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=movie-recommender

[Install]
WantedBy=multi-user.target
EOF

# 重载systemd
log_info "重载systemd配置..."
systemctl daemon-reload

# 启用并启动服务
log_info "启用电影推荐系统服务..."
systemctl enable movie-recommender.service

log_info "启动电影推荐系统服务..."
systemctl start movie-recommender.service

# 等待服务启动
log_info "等待服务启动..."
MAX_ATTEMPTS=5
ATTEMPT=1
SUCCESS=false

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    log_info "检查服务状态，尝试 $ATTEMPT/$MAX_ATTEMPTS..."
    sleep 3
    
    if systemctl is-active --quiet movie-recommender.service; then
        SUCCESS=true
        log_info "服务已成功启动！"
        break
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
done

# 诊断服务启动问题
if [ "$SUCCESS" = false ]; then
    log_warning "服务启动失败，开始诊断问题..."
    
    # 检查服务状态
    log_info "服务状态："
    systemctl status movie-recommender.service --no-pager
    
    # 检查日志
    log_info "服务日志："
    journalctl -u movie-recommender.service -n 30 --no-pager
    
    # 检查常见问题并尝试修复
    if journalctl -u movie-recommender.service | grep -q "No module named 'web'"; then
        log_warning "缺少web.py模块，尝试修复..."
        "$VENV_DIR/bin/pip" install web.py
        log_info "重启服务..."
        systemctl restart movie-recommender.service
        sleep 3
        
        if systemctl is-active --quiet movie-recommender.service; then
            SUCCESS=true
            log_info "服务已成功启动！"
        else
            log_warning "修复后服务仍然无法启动"
        fi
    fi
    
    if journalctl -u movie-recommender.service | grep -q "mysql"; then
        log_warning "可能存在数据库连接问题，请检查MySQL配置"
    fi
    
    if journalctl -u movie-recommender.service | grep -q "Permission denied"; then
        log_warning "可能存在权限问题，请检查目录权限设置"
    fi
    
    if [ "$SUCCESS" = false ]; then
        log_error "无法自动解决服务启动问题"
        log_info "请手动检查日志: journalctl -u movie-recommender.service -f"
    fi
fi

# 第十步：配置Nginx（如果需要）
if [ "$USE_NGINX" = true ]; then
    log_section "配置Nginx反向代理"
    
    # 检查Nginx是否已安装
    if ! command -v nginx &> /dev/null; then
        log_info "安装Nginx..."
        apt-get install -y nginx
    fi
    
    # 创建Nginx配置
    log_info "创建Nginx配置..."
    NGINX_CONF="/etc/nginx/sites-available/recommender"
    
    # 获取服务器IP
    SERVER_IP=$(hostname -I | awk '{print $1}')
    
    cat > "$NGINX_CONF" << EOF
server {
    listen 80;
    server_name $SERVER_IP;

    access_log /var/log/nginx/recommender_access.log;
    error_log /var/log/nginx/recommender_error.log;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # 增加超时时间
        proxy_read_timeout 300;
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
        
        # WebSocket支持（如果需要）
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
    
    # 启用配置
    log_info "启用Nginx配置..."
    ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
    
    # 禁用默认配置
    if [ -f "/etc/nginx/sites-enabled/default" ]; then
        rm -f /etc/nginx/sites-enabled/default
    fi
    
    # 测试配置
    log_info "测试Nginx配置..."
    if nginx -t; then
        log_info "Nginx配置有效"
    else
        log_error "Nginx配置无效，请手动检查"
    fi
    
    # 重启Nginx
    log_info "重启Nginx..."
    systemctl restart nginx
    
    # 确保Nginx开机自启
    systemctl enable nginx
fi

# 第十一步：检查防火墙设置
log_section "检查防火墙设置"
if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
    log_info "防火墙已启用，确保端口开放..."
    ufw allow 80/tcp || true
    ufw reload || true
fi

# 部署完成
log_section "部署完成"
if [ "$SUCCESS" = true ]; then
    log_info "电影推荐系统已成功部署！"
else
    log_warning "电影推荐系统部署完成，但服务可能未正确启动"
    log_info "请检查日志并手动排查问题"
fi

# 获取服务器IP
SERVER_IP=$(hostname -I | awk '{print $1}')

log_info "========================================================"
log_info "部署摘要:"
log_info "1. 安装目录: $INSTALL_DIR"
log_info "2. 服务状态: $(systemctl is-active movie-recommender.service)"
log_info "3. 微信公众号访问URL: http://$SERVER_IP/"
log_info "4. 微信公众号Token: $(grep "token" "$CONFIG_FILE" | head -1 | cut -d'=' -f2 | tr -d ' ')"
log_info "========================================================"
log_info "常用管理命令:"
log_info "- 查看服务状态: systemctl status movie-recommender.service"
log_info "- 查看服务日志: journalctl -u movie-recommender.service -f"
log_info "- 重启服务: systemctl restart movie-recommender.service"
log_info "- 测试服务: curl http://$SERVER_IP/"
log_info "========================================================"

# 提供微信调试工具
log_info "您可以使用微信调试工具验证服务配置："
log_info "$PYTHON_BIN $INSTALL_DIR/scripts/wechat_debug.py --validate"
log_info "========================================================" 