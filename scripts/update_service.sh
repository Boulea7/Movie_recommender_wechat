#!/bin/bash
# 电影推荐系统服务更新脚本
# 作者：电影推荐系统团队
# 日期：2025-05-09

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

# 检查是否有root权限
if [ "$EUID" -ne 0 ]; then
    log_error "请使用root用户或sudo运行此脚本"
    exit 1
fi

# 安装目录
INSTALL_DIR=${INSTALL_DIR:-"/opt/recommender"}
TIMESTAMP=$(date '+%Y%m%d%H%M%S')

# 创建日志目录
mkdir -p "$INSTALL_DIR/logs"
LOG_FILE="$INSTALL_DIR/logs/service_update_${TIMESTAMP}.log"

log_info "开始更新电影推荐系统服务..." | tee -a "$LOG_FILE"

# 停止当前服务
log_info "停止当前服务..." | tee -a "$LOG_FILE"
systemctl stop movie-recommender.service || true

# 确保日志目录存在并有正确的权限
log_info "确保日志目录存在..." | tee -a "$LOG_FILE"
mkdir -p "$INSTALL_DIR/logs" | tee -a "$LOG_FILE"
chmod 755 "$INSTALL_DIR/logs" | tee -a "$LOG_FILE"

# 更新系统服务文件
log_info "更新系统服务配置..." | tee -a "$LOG_FILE"
cat > /etc/systemd/system/movie-recommender.service << EOF
[Unit]
Description=电影推荐系统服务
After=network.target mysql.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $INSTALL_DIR/web_server/main.py
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=movie-recommender
# 允许绑定特权端口(80)
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

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

# 检查端口监听情况
log_info "检查端口监听情况..." | tee -a "$LOG_FILE"
netstat -tuln | grep -E ':80|:8080' | tee -a "$LOG_FILE"

log_info "服务更新完成！可以通过以下命令查看服务状态：" | tee -a "$LOG_FILE"
log_info "systemctl status movie-recommender.service" | tee -a "$LOG_FILE"
log_info "可以通过以下命令查看日志：" | tee -a "$LOG_FILE"
log_info "journalctl -u movie-recommender.service -f" | tee -a "$LOG_FILE" 