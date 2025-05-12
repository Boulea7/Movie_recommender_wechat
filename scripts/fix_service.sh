#!/bin/bash
# 服务修复检查脚本
# 作者：电影推荐系统团队
# 日期：2023-05-13

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

# 安装目录
INSTALL_DIR=${INSTALL_DIR:-"/opt/recommender"}
BACKUP_DIR="$INSTALL_DIR/backups"
TIMESTAMP=$(date '+%Y%m%d%H%M%S')

# 检查是否有root权限
if [ "$EUID" -ne 0 ]; then
    log_error "请使用root用户或sudo运行此脚本"
    exit 1
fi

# 显示脚本头部
log_section "电影推荐系统服务修复脚本"
log_info "正在检查服务状态和日志..."

# 检查服务状态
log_section "检查服务状态"
systemctl status movie-recommender.service || true

# 检查服务日志
log_section "检查服务日志"
journalctl -u movie-recommender.service -n 50 || true

# 创建所有必要的目录
log_section "确保目录结构完整"
mkdir -p "$INSTALL_DIR/logs"
chmod 755 "$INSTALL_DIR/logs"
chown -R root:root "$INSTALL_DIR/logs"
log_info "已创建日志目录 $INSTALL_DIR/logs"

mkdir -p "$INSTALL_DIR/config"
chmod 755 "$INSTALL_DIR/config"
log_info "已创建配置目录 $INSTALL_DIR/config"

# 检查配置文件
log_section "检查配置文件"
CONFIG_FILE="$INSTALL_DIR/config/database.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    log_warning "配置文件不存在，创建默认配置..."
    cat > "$CONFIG_FILE" << EOF
[database]
host = localhost
port = 3306
user = douban_user
password = MySQL_20050816Zln@233
db = douban
charset = utf8mb4
pool_size = 5
timeout = 60
reconnect_attempts = 3

[service]
port = 80
token = HelloMovieRecommender
encoding_key = X5hyGsEzWugANKlq9uDjtpGQZ40yL1axD9m147dPa1a
debug = false
log_level = INFO

[recommender]
similarity_threshold = 0.5
min_ratings = 3
max_recommendations = 10
EOF
    log_info "已创建默认配置文件"
fi

# 检查Python解释器
log_section "检查Python环境"
if [ -d "$INSTALL_DIR/venv" ]; then
    log_info "检查虚拟环境中的Python包..."
    "$INSTALL_DIR/venv/bin/pip" list | grep -E "web.py|lxml|pymysql" || true
    
    # 安装可能缺失的依赖
    log_info "安装必要的Python依赖..."
    "$INSTALL_DIR/venv/bin/pip" install web.py lxml pymysql
else
    log_warning "找不到虚拟环境，创建新的虚拟环境..."
    python3 -m venv "$INSTALL_DIR/venv"
    "$INSTALL_DIR/venv/bin/pip" install --upgrade pip
    "$INSTALL_DIR/venv/bin/pip" install web.py lxml pymysql
    
    if [ -f "$INSTALL_DIR/requirements.txt" ]; then
        "$INSTALL_DIR/venv/bin/pip" install -r "$INSTALL_DIR/requirements.txt"
    fi
    
    log_info "已创建并配置虚拟环境"
fi

# 修复main.py中的缩进问题
log_section "修复main.py中的缩进问题"
if [ -f "$INSTALL_DIR/web_server/main.py" ]; then
    # 备份原始文件
    mkdir -p "$BACKUP_DIR"
    cp "$INSTALL_DIR/web_server/main.py" "$BACKUP_DIR/main.py.bak.$TIMESTAMP"
    
    # 修复update_user_info方法的缩进问题
    log_info "修复update_user_info方法的缩进问题..."
    sed -i 's/^\tdef update_user_info(self, user_name):/\tdef update_user_info(self, user_name):/' "$INSTALL_DIR/web_server/main.py"
    sed -i 's/^\ttry:/\t\ttry:/' "$INSTALL_DIR/web_server/main.py"
    
    # 添加导入pymysql作为MySQLdb的兼容性包装
    log_info "添加MySQLdb兼容性导入..."
    cat > "$INSTALL_DIR/web_server/mysqldb_wrapper.py" << 'EOF'
"""
MySQLdb兼容性包装器，使用pymysql作为替代方案
当无法安装原生MySQLdb时使用此模块
"""
import pymysql
import sys

# 将pymysql设置为MySQLdb的别名
sys.modules['MySQLdb'] = pymysql
EOF
    
    chmod 644 "$INSTALL_DIR/web_server/mysqldb_wrapper.py"
    log_info "已创建MySQLdb兼容性包装器"
    
    # 确保导入头部包含pymysql
    if grep -q "import MySQLdb" "$INSTALL_DIR/web_server/main.py"; then
        log_info "替换MySQLdb导入为pymysql..."
        sed -i 's/import MySQLdb/import pymysql as MySQLdb/' "$INSTALL_DIR/web_server/main.py"
    fi
    
    log_info "main.py修复完成"
else
    log_warning "找不到main.py文件"
fi

# 更新并重启服务
log_section "更新服务配置"
SERVICE_FILE="/etc/systemd/system/movie-recommender.service"

if [ -f "$SERVICE_FILE" ]; then
    # 备份服务文件
    cp "$SERVICE_FILE" "$SERVICE_FILE.bak.$TIMESTAMP"
    
    # 获取正确的Python路径
    PYTHON_PATH="$INSTALL_DIR/venv/bin/python"
    if [ ! -f "$PYTHON_PATH" ]; then
        PYTHON_PATH="$INSTALL_DIR/venv/bin/python3"
    fi
    
    # 更新服务文件
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=电影推荐系统服务
After=network.target mysql.service
Wants=mysql.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
Environment="PYTHONPATH=$INSTALL_DIR"
ExecStart=$PYTHON_PATH $INSTALL_DIR/web_server/main.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=movie-recommender
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
    
    # 重载并重启服务
    log_info "重载systemd配置..."
    systemctl daemon-reload
    
    log_info "重启服务..."
    systemctl restart movie-recommender.service
    
    # 等待服务启动
    log_info "等待服务启动..."
    sleep 5
    
    # 检查服务状态
    if systemctl is-active --quiet movie-recommender.service; then
        log_info "服务已成功启动！"
        systemctl status movie-recommender.service --no-pager
    else
        log_warning "服务可能仍未启动，请检查日志"
        systemctl status movie-recommender.service --no-pager
        journalctl -u movie-recommender.service -n 20 --no-pager
    fi
else
    log_warning "找不到服务文件，创建新的服务文件..."
    
    # 获取正确的Python路径
    PYTHON_PATH="$INSTALL_DIR/venv/bin/python"
    if [ ! -f "$PYTHON_PATH" ]; then
        PYTHON_PATH="$INSTALL_DIR/venv/bin/python3"
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
Environment="PYTHONPATH=$INSTALL_DIR"
ExecStart=$PYTHON_PATH $INSTALL_DIR/web_server/main.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=movie-recommender
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
    
    # 重载并启动服务
    log_info "重载systemd配置..."
    systemctl daemon-reload
    
    log_info "启动服务..."
    systemctl enable movie-recommender.service
    systemctl start movie-recommender.service
    
    # 等待服务启动
    log_info "等待服务启动..."
    sleep 5
    
    # 检查服务状态
    if systemctl is-active --quiet movie-recommender.service; then
        log_info "服务已成功启动！"
        systemctl status movie-recommender.service --no-pager
    else
        log_warning "服务可能未启动，请检查日志"
        systemctl status movie-recommender.service --no-pager
        journalctl -u movie-recommender.service -n 20 --no-pager
    fi
fi

log_section "修复完成"
log_info "修复脚本已执行完毕，如果服务仍未启动，请检查日志以获取详细错误信息"
log_info "您可以使用以下命令查看服务状态：systemctl status movie-recommender.service"
log_info "您可以使用以下命令查看服务日志：journalctl -u movie-recommender.service -f" 