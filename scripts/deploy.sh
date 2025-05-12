#!/bin/bash
# 电影推荐系统自动部署脚本
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

# 安装目录
INSTALL_DIR=${INSTALL_DIR:-"/opt/recommender"}
BACKUP_DIR="/opt/recommender_backups"
TIMESTAMP=$(date '+%Y%m%d%H%M%S')
PORT=${PORT:-80}
CURRENT_DIR=$(pwd)

# 脚本开始
log_info "开始部署电影推荐系统..."
log_info "项目目录: $CURRENT_DIR"
log_info "安装目录: $INSTALL_DIR"

# 检查是否有root权限
if [ "$EUID" -ne 0 ]; then
    log_error "请使用root用户或sudo运行此脚本"
    exit 1
fi

# 检查系统依赖
log_info "检查系统依赖..."
check_dependency python3
check_dependency python3-pip
check_dependency python3-venv
check_dependency mysql-client
check_dependency libmysqlclient-dev
check_dependency libcap2-bin

# 创建安装目录
log_info "创建安装目录..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$BACKUP_DIR"

# 备份现有安装
if [ -d "$INSTALL_DIR" ] && [ "$(ls -A $INSTALL_DIR)" ]; then
    BACKUP_PATH="$BACKUP_DIR/backup_$TIMESTAMP"
    log_info "备份现有安装到 $BACKUP_PATH..."
    mkdir -p "$BACKUP_PATH"
    cp -R "$INSTALL_DIR"/* "$BACKUP_PATH" 2>/dev/null || true
fi

# 安装系统级依赖
log_info "安装系统依赖..."
apt-get update
apt-get install -y python3 python3-pip python3-venv mysql-client libmysqlclient-dev libcap2-bin

# 复制项目文件到安装目录
log_info "复制项目文件到安装目录..."
cp -R ./* "$INSTALL_DIR"

# 创建日志目录
log_info "创建日志目录..."
mkdir -p "$INSTALL_DIR/logs"

# 创建Python虚拟环境
log_info "创建Python虚拟环境..."
if [ ! -d "$INSTALL_DIR/venv" ]; then
    python3 -m venv "$INSTALL_DIR/venv"
fi

# 安装Python依赖
log_info "安装Python依赖..."
"$INSTALL_DIR/venv/bin/pip" install --upgrade pip
"$INSTALL_DIR/venv/bin/pip" install -r "$INSTALL_DIR/requirements.txt"

# 设置脚本执行权限
log_info "设置脚本执行权限..."
chmod +x "$INSTALL_DIR/scripts/"*.sh
chmod +x "$INSTALL_DIR/data_spider/"*.py
chmod +x "$INSTALL_DIR/web_server/"*.py

# 初始化MySQL服务
log_info "检查和初始化MySQL服务..."
if [ -f "$INSTALL_DIR/scripts/init_mysql.sh" ]; then
    cd "$INSTALL_DIR"
    bash "$INSTALL_DIR/scripts/init_mysql.sh"
    if [ $? -ne 0 ]; then
        log_error "MySQL服务初始化失败，请检查错误并修复"
        log_info "您可以手动运行 bash $INSTALL_DIR/scripts/init_mysql.sh 查看详细错误"
    fi
fi

# 初始化数据库
log_info "初始化数据库..."
cd "$INSTALL_DIR"
bash "$INSTALL_DIR/scripts/init_database.sh"

# 在配置文件中设置正确的端口
log_info "配置服务端口..."
CONFIG_FILE="$INSTALL_DIR/config/database.conf"
if [ -f "$CONFIG_FILE" ]; then
    # 检查配置文件格式
    if grep -q "^\[service\]" "$CONFIG_FILE"; then
        # 更新端口配置
        if grep -q "^port" "$CONFIG_FILE"; then
            sed -i "s/^port = .*/port = $PORT/" "$CONFIG_FILE"
        else
            # 如果没有port配置项，添加到[service]部分
            sed -i "/^\[service\]/a port = $PORT" "$CONFIG_FILE"
        fi
    else
        log_warning "配置文件格式不正确，请手动设置端口"
    fi
else
    log_warning "配置文件不存在，将创建默认配置"
    mkdir -p "$INSTALL_DIR/config"
    cat > "$CONFIG_FILE" << EOF
[database]
host = localhost
port = 3306
user = douban_user
password = MySQL_20050816Zln@233
db = douban
charset = utf8mb4

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
fi

# 创建系统服务
log_info "创建系统服务..."
cat > /etc/systemd/system/movie-recommender.service << EOF
[Unit]
Description=电影推荐系统服务
After=network.target mysql.service
Wants=mysql.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/web_server/main.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=movie-recommender

[Install]
WantedBy=multi-user.target
EOF

# 重载系统服务
log_info "重载系统服务..."
systemctl daemon-reload

# 如果端口小于1024，添加CAP_NET_BIND_SERVICE权限
if [ "$PORT" -lt 1024 ]; then
    log_info "设置低端口绑定权限..."
    setcap 'cap_net_bind_service=+ep' "$INSTALL_DIR/venv/bin/python3"
    # 检查是否成功设置
    if [ $? -ne 0 ]; then
        log_warning "设置CAP_NET_BIND_SERVICE权限失败，将改用端口8080并配置Nginx"
        sed -i "s/^port = .*/port = 8080/" "$CONFIG_FILE"
        log_info "将在后续步骤中配置Nginx作为反向代理"
    else
        log_info "成功设置CAP_NET_BIND_SERVICE权限，可以绑定低端口"
    fi
fi

# 启动电影推荐系统服务
log_info "启动电影推荐系统服务..."
systemctl enable movie-recommender.service
systemctl start movie-recommender.service

# 验证服务是否启动成功
MAX_ATTEMPTS=3
ATTEMPT=1
SUCCESS=false

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    log_warning "服务启动中，尝试 $ATTEMPT/$MAX_ATTEMPTS..."
    sleep 3
    
    if systemctl is-active --quiet movie-recommender.service; then
        SUCCESS=true
        break
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
done

if [ "$SUCCESS" = false ]; then
    log_error "电影推荐系统服务启动失败，请检查日志"
    systemctl status movie-recommender.service
    
    # 检查日志以确定失败原因
    log_info "正在检查日志以确定失败原因..."
    journalctl -u movie-recommender.service -n 30 --no-pager
    
    # 检查是否是缺少web.py模块导致的
    if journalctl -u movie-recommender.service | grep -q "No module named 'web'"; then
        log_warning "缺少web.py模块，尝试修复..."
        "$INSTALL_DIR/venv/bin/pip" install web.py
        systemctl restart movie-recommender.service
        sleep 3
        
        if systemctl is-active --quiet movie-recommender.service; then
            log_info "服务已成功启动！"
            SUCCESS=true
        fi
    fi
    
    # 检查是否是配置解析错误
    if journalctl -u movie-recommender.service | grep -q "get_section"; then
        log_warning "配置解析错误，尝试修复config_parser.py..."
        # 检查是否已修复
        if grep -q "get_section" "$INSTALL_DIR/web_server/config_parser.py"; then
            log_info "config_parser.py已包含get_section方法，重启服务..."
            systemctl restart movie-recommender.service
            sleep 3
            
            if systemctl is-active --quiet movie-recommender.service; then
                log_info "服务已成功启动！"
                SUCCESS=true
            fi
        fi
    fi
    
    if [ "$SUCCESS" = false ]; then
        log_error "无法自动修复服务启动问题，请手动检查"
    fi
fi

# 检查80端口占用情况
log_info "检查80端口占用情况..."
PORT80_OCCUPIED=false
if netstat -tuln | grep -q ":80 "; then
    if ! systemctl is-active --quiet movie-recommender.service; then
        log_warning "80端口被占用，且电影推荐系统服务未成功启动"
        log_info "将尝试使用Nginx作为反向代理..."
        PORT80_OCCUPIED=true
    fi
fi

# 如果端口被占用，使用Nginx作为反向代理
if [ "$PORT80_OCCUPIED" = true ] || [ "$PORT" -ne 80 ]; then
    log_info "配置Nginx反向代理..."
    if [ -f "$INSTALL_DIR/scripts/setup_nginx.sh" ]; then
        bash "$INSTALL_DIR/scripts/setup_nginx.sh"
    else
        log_warning "找不到Nginx配置脚本，请手动配置Nginx"
    fi
fi

# 检查防火墙设置
log_info "检查防火墙设置..."
if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
    log_info "防火墙已启用，确保80端口开放..."
    ufw allow 80/tcp || true
    ufw reload || true
fi

# 部署完成
log_info "部署完成！可以通过以下命令查看服务状态："
log_info "systemctl status movie-recommender.service"
log_info "可以通过以下命令查看日志："
log_info "journalctl -u movie-recommender.service -f"
log_info "安装目录: $INSTALL_DIR"

# 获取服务器IP
SERVER_IP=$(hostname -I | awk '{print $1}')

log_info "----------------------------------------------------------------"
log_info "部署后操作建议:"
log_info "1. 访问 http://$SERVER_IP 测试服务"
log_info "2. 如遇80端口问题，可运行: sudo bash $INSTALL_DIR/scripts/setup_nginx.sh"
log_info "3. 配置微信公众号URL: http://$SERVER_IP"
log_info "4. 配置微信公众号Token: 见 $INSTALL_DIR/config/database.conf 的token值"
log_info "----------------------------------------------------------------" 