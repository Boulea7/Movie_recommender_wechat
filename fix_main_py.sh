#!/bin/bash
# 快速修复脚本 - 修复web_server/main.py缩进问题
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

# 检查是否有root权限
if [ "$EUID" -ne 0 ]; then
    log_error "请使用root用户或sudo运行此脚本"
    exit 1
fi

INSTALL_DIR=${INSTALL_DIR:-"/opt/recommender"}
BACKUP_DIR="$INSTALL_DIR/backups"
TIMESTAMP=$(date '+%Y%m%d%H%M%S')

# 显示脚本头部
log_section "电影推荐系统Web服务器缩进问题修复脚本"
log_info "开始修复web_server/main.py文件的语法错误..."

# 创建备份目录
mkdir -p "$BACKUP_DIR"

# 备份原始文件
log_section "备份原始文件"
log_info "备份 web_server/main.py 到 $BACKUP_DIR/main.py.bak.$TIMESTAMP"
cp "$INSTALL_DIR/web_server/main.py" "$BACKUP_DIR/main.py.bak.$TIMESTAMP"

# 使用临时文件修复缩进问题
log_section "修复主要缩进问题"
log_info "使用sed修复update_user_info方法的缩进错误"

# 查找update_user_info方法的位置
LINE_START=$(grep -n "def update_user_info" "$INSTALL_DIR/web_server/main.py" | cut -d: -f1)
if [ -z "$LINE_START" ]; then
    log_error "无法找到update_user_info方法，退出修复"
    exit 1
fi

log_info "找到方法位置，行号: $LINE_START"

# 创建临时文件
TMP_FILE=$(mktemp)

# 提取文件头部
head -n $((LINE_START-1)) "$INSTALL_DIR/web_server/main.py" > "$TMP_FILE"

# 添加修复后的update_user_info方法
cat >> "$TMP_FILE" << 'EOF'
	def update_user_info(self, user_name):
		try:
			self.db = pymysql.connect(
				host=DB_CONFIG.get('host', 'localhost'),
				port=int(DB_CONFIG.get('port', 3306)),
				user=DB_CONFIG.get('user', 'douban_user'),
				password=DB_CONFIG.get('password', 'MySQL_20050816Zln@233'),
				db=DB_CONFIG.get('db', 'douban'),
				charset=DB_CONFIG.get('charset', 'utf8mb4')
			)
			self.cursor = self.db.cursor()
			cmd = 'select * from user_info where wx_id = "{}";'.format(user_name)
			self.cursor.execute(cmd)
			results = self.cursor.fetchall()
			if len(results) == 0:
				cmd = 'insert into user_info(wx_id, start_time) values("{}", "{}");'.format(user_name, int(time.time()))
				try:
					self.cursor.execute(cmd)
					self.db.commit()
					logger.info(f"添加新用户: {user_name}")
				except Exception as e:
					self.db.rollback()
					logger.error(f"添加用户失败: {e}")
		except Exception as e:
			logger.error(f"更新用户信息失败: {e}")
EOF

# 查找下一个方法的位置
LINE_END=$(tail -n +$((LINE_START+1)) "$INSTALL_DIR/web_server/main.py" | grep -n "^	def " | head -1 | cut -d: -f1)
LINE_END=$((LINE_START + LINE_END))

# 添加文件剩余部分
tail -n +$((LINE_END)) "$INSTALL_DIR/web_server/main.py" >> "$TMP_FILE"

# 替换原始文件
mv "$TMP_FILE" "$INSTALL_DIR/web_server/main.py"
chmod 644 "$INSTALL_DIR/web_server/main.py"

log_info "已修复 web_server/main.py 文件中的缩进问题"

# 安装缺失的依赖项
log_section "安装缺失的依赖"
if [ -d "$INSTALL_DIR/venv" ]; then
    log_info "检测到虚拟环境，在虚拟环境中安装依赖"
    "$INSTALL_DIR/venv/bin/pip" install mysqlclient
else
    log_info "在系统Python环境中安装依赖"
    pip install mysqlclient
fi

# 重启服务
log_section "重启服务"
systemctl restart movie-recommender.service
log_info "服务已重启"

# 等待服务启动
log_info "等待服务启动..."
sleep 5
if systemctl is-active --quiet movie-recommender.service; then
    log_info "服务已成功启动！"
else
    log_warning "服务可能未正确启动，请检查日志：journalctl -u movie-recommender.service -f"
fi

log_section "修复完成"
log_info "web_server/main.py 文件的语法错误已修复。"
log_info "如果仍有问题，您可以恢复备份文件："
log_info "  sudo cp $BACKUP_DIR/main.py.bak.$TIMESTAMP $INSTALL_DIR/web_server/main.py"
log_info "  sudo systemctl restart movie-recommender.service" 