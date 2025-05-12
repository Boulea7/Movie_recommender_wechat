#!/bin/bash
# 健康检查端点缩进修复脚本
# 作者：电影推荐系统团队
# 日期：2025-05-13

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
log_section "电影推荐系统健康检查端点缩进修复脚本"
log_info "开始修复健康检查端点缩进问题..."

# 确保备份目录存在
mkdir -p "$BACKUP_DIR"

# 修复main.py中的Health类缩进问题
log_section "修复Health类缩进问题"
MAIN_PY="$INSTALL_DIR/web_server/main.py"

if [ ! -f "$MAIN_PY" ]; then
    log_error "未找到main.py文件: $MAIN_PY"
    exit 1
fi

# 备份原始文件
log_info "备份原始文件..."
cp "$MAIN_PY" "$BACKUP_DIR/main.py.bak.$TIMESTAMP"

# 创建临时文件
TEMP_FILE=$(mktemp)

# 读取main.py文件内容
log_info "分析main.py文件..."
cat "$MAIN_PY" > "$TEMP_FILE"

# 检查Health类并修复其缩进
log_info "修复Health类缩进..."
sed -i 's/class Health(object):/class Health(object):/' "$TEMP_FILE"
sed -i '/class Health(object):/,/def GET/{s/def GET/    def GET/}' "$TEMP_FILE"
sed -i '/def GET/,/return/{s/web\.header/        web.header/}' "$TEMP_FILE"
sed -i '/def GET/,/return/{s/return/        return/}' "$TEMP_FILE"

# 替换原始文件
mv "$TEMP_FILE" "$MAIN_PY"
chmod 644 "$MAIN_PY"
log_info "已修复Health类缩进问题"

# 修复handle_wechat_error方法中可能的缩进问题
log_section "修复handle_wechat_error方法缩进"
log_info "检查handle_wechat_error方法缩进..."

# 创建临时文件
TEMP_FILE=$(mktemp)
cat "$MAIN_PY" > "$TEMP_FILE"

# 修复handle_wechat_error方法缩进
sed -i '/def handle_wechat_error/,/web\.ctx\.status/{s/web\.ctx\.status/        web.ctx.status/}' "$TEMP_FILE"
sed -i '/def handle_wechat_error/,/return web\.ctx/{s/return web\.ctx/        return web.ctx/}' "$TEMP_FILE"

# 替换原始文件
mv "$TEMP_FILE" "$MAIN_PY"
chmod 644 "$MAIN_PY"
log_info "已修复handle_wechat_error方法缩进问题"

# 重启服务
log_section "重启服务"
log_info "重启movie-recommender服务..."
systemctl restart movie-recommender.service

# 等待服务启动
log_info "等待服务启动..."
sleep 5

# 检查服务状态
if systemctl is-active --quiet movie-recommender.service; then
    log_info "服务已成功启动！"
else
    log_warning "服务仍未正确启动，查看状态..."
    systemctl status movie-recommender.service --no-pager
    
    # 显示日志
    log_warning "显示服务日志以诊断问题..."
    journalctl -u movie-recommender.service -n 20 --no-pager
    
    # 尝试更彻底的修复
    log_section "尝试更彻底的修复"
    log_info "重建Health类..."
    
    # 创建临时文件
    TEMP_FILE=$(mktemp)
    
    # 查找URLs定义行
    URLS_LINE=$(grep -n "urls = (" "$MAIN_PY" | cut -d: -f1)
    if [ -n "$URLS_LINE" ]; then
        # 从文件开始到URLs行
        head -n "$URLS_LINE" "$MAIN_PY" > "$TEMP_FILE"
        
        # 添加健康检查URL
        echo "urls = (" >> "$TEMP_FILE"
        echo "    '/health', 'Health'," >> "$TEMP_FILE"
        
        # 继续添加其他URLs
        awk -v line="$URLS_LINE" 'NR > line && NR <= line+1 {next} NR > line+1 {print}' "$MAIN_PY" >> "$TEMP_FILE"
        
        # 在文件末尾添加Health类
        cat >> "$TEMP_FILE" << 'EOF'

class Health:
    def GET(self):
        web.header('Content-Type', 'text/plain')
        return "OK"
EOF
        
        # 替换原始文件
        mv "$TEMP_FILE" "$MAIN_PY"
        chmod 644 "$MAIN_PY"
        log_info "已重建Health类"
        
        # 再次重启服务
        log_info "再次重启服务..."
        systemctl restart movie-recommender.service
        sleep 5
        
        if systemctl is-active --quiet movie-recommender.service; then
            log_info "服务已成功启动！"
        else
            log_error "服务仍然无法启动，请手动检查main.py文件"
        fi
    else
        log_error "无法找到URLs定义行，请手动修复文件"
    fi
fi

log_section "修复完成"
log_info "健康检查端点缩进修复脚本已完成" 