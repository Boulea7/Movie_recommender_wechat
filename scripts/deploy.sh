#!/bin/bash
# 电影推荐系统自动部署脚本
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

# 安装目录
INSTALL_DIR=${INSTALL_DIR:-"/opt/recommender"}
BACKUP_DIR="/opt/recommender_backups"

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( dirname "$SCRIPT_DIR" )"
TIMESTAMP=$(date '+%Y%m%d%H%M%S')

# 创建日志目录
mkdir -p "$PROJECT_ROOT/logs"
LOG_FILE="$PROJECT_ROOT/logs/deploy_${TIMESTAMP}.log"

log_info "开始部署电影推荐系统..." | tee -a "$LOG_FILE"
log_info "项目目录: $PROJECT_ROOT" | tee -a "$LOG_FILE"
log_info "安装目录: $INSTALL_DIR" | tee -a "$LOG_FILE"

# 检查是否有root权限
if [ "$EUID" -ne 0 ]; then
    log_error "请使用root用户或sudo运行此脚本" | tee -a "$LOG_FILE"
    exit 1
fi

# 创建安装目录
log_info "创建安装目录..." | tee -a "$LOG_FILE"
mkdir -p "$INSTALL_DIR" | tee -a "$LOG_FILE"
mkdir -p "$BACKUP_DIR" | tee -a "$LOG_FILE"

# 如果安装目录已存在内容，备份它
if [ "$(ls -A $INSTALL_DIR)" ]; then
    BACKUP_PATH="${BACKUP_DIR}/backup_${TIMESTAMP}"
    log_info "备份现有安装到 $BACKUP_PATH..." | tee -a "$LOG_FILE"
    mkdir -p "$BACKUP_PATH" | tee -a "$LOG_FILE"
    cp -r "$INSTALL_DIR"/* "$BACKUP_PATH"/ | tee -a "$LOG_FILE"
fi

# 安装必要的系统依赖
log_info "安装系统依赖..." | tee -a "$LOG_FILE"
apt-get update | tee -a "$LOG_FILE"
apt-get install -y python python-pip mysql-client libmysqlclient-dev | tee -a "$LOG_FILE"

# 复制项目文件到安装目录
log_info "复制项目文件到安装目录..." | tee -a "$LOG_FILE"
cp -r "$PROJECT_ROOT"/* "$INSTALL_DIR"/ | tee -a "$LOG_FILE"

# 安装Python依赖
log_info "安装Python依赖..." | tee -a "$LOG_FILE"
cd "$INSTALL_DIR" | tee -a "$LOG_FILE"
pip install -r requirements.txt | tee -a "$LOG_FILE"

# 确保脚本具有执行权限
log_info "设置脚本执行权限..." | tee -a "$LOG_FILE"
chmod +x "$INSTALL_DIR/scripts/"*.sh | tee -a "$LOG_FILE"

# 初始化数据库
log_info "初始化数据库..." | tee -a "$LOG_FILE"
bash "$INSTALL_DIR/scripts/init_database.sh" | tee -a "$LOG_FILE"

# 创建系统服务文件
log_info "创建系统服务..." | tee -a "$LOG_FILE"
cat > /etc/systemd/system/movie-recommender.service << EOF
[Unit]
Description=电影推荐系统服务
After=network.target mysql.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python $INSTALL_DIR/web_server/server.py
Restart=on-failure
RestartSec=5
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=movie-recommender

[Install]
WantedBy=multi-user.target
EOF

# 重载系统服务
log_info "重载系统服务..." | tee -a "$LOG_FILE"
systemctl daemon-reload | tee -a "$LOG_FILE"

# 启动服务
log_info "启动电影推荐系统服务..." | tee -a "$LOG_FILE"
systemctl enable movie-recommender.service | tee -a "$LOG_FILE"
systemctl start movie-recommender.service | tee -a "$LOG_FILE"

# 检查服务状态
sleep 3
if systemctl is-active --quiet movie-recommender.service; then
    log_info "电影推荐系统服务已成功启动！" | tee -a "$LOG_FILE"
else
    log_error "电影推荐系统服务启动失败，请检查日志" | tee -a "$LOG_FILE"
    systemctl status movie-recommender.service | tee -a "$LOG_FILE"
fi

log_info "部署完成！可以通过以下命令查看服务状态：" | tee -a "$LOG_FILE"
log_info "systemctl status movie-recommender.service" | tee -a "$LOG_FILE"
log_info "可以通过以下命令查看日志：" | tee -a "$LOG_FILE"
log_info "journalctl -u movie-recommender.service -f" | tee -a "$LOG_FILE"
log_info "安装目录: $INSTALL_DIR" | tee -a "$LOG_FILE" 