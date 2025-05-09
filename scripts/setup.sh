#!/bin/bash

# 电影推荐系统一键部署脚本
# 作者：AI工程师
# 日期：2023-05-20

# 定义安装目录
INSTALL_DIR="/opt/recommender"
LOG_FILE="$INSTALL_DIR/logs/setup.log"

# 日志函数
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message"
    echo "$message" >> "$LOG_FILE" 2>/dev/null || true
}

# 错误处理函数
handle_error() {
    log "错误：$1"
    log "部署失败，请查看日志文件了解详情: $LOG_FILE"
    exit 1
}

# 备份函数
backup_database() {
    log "正在备份数据库..."
    BACKUP_FILE="$INSTALL_DIR/backup/douban_$(date +%Y%m%d_%H%M%S).sql"
    mkdir -p "$INSTALL_DIR/backup"
    mysqldump -u douban_user -p'MySQL_20050816Zln@233' douban > "$BACKUP_FILE" 2>/dev/null || handle_error "数据库备份失败"
    log "数据库已备份到: $BACKUP_FILE"
}

echo "=== 电影推荐系统部署脚本启动 ==="
echo "该脚本将自动配置环境并部署电影推荐系统"
echo "安装目录: $INSTALL_DIR"
echo "=============================="

# 判断是否是root用户运行
if [ "$(id -u)" != "0" ]; then
   echo "错误：此脚本需要使用root权限运行。" 
   echo "请使用 'sudo ./setup.sh' 命令运行此脚本。"
   exit 1
fi

# 记录开始时间
start_time=$(date +%s)

# 创建安装目录
mkdir -p "$INSTALL_DIR" || handle_error "无法创建安装目录: $INSTALL_DIR"
cd "$INSTALL_DIR" || handle_error "无法进入安装目录: $INSTALL_DIR"

# 创建所需目录
mkdir -p sql logs test_data scripts data_spider web_server backup || handle_error "无法创建必要的子目录"

# 初始化日志文件
touch "$LOG_FILE" || handle_error "无法创建日志文件: $LOG_FILE"
log "开始部署电影推荐系统"

# 更新系统并安装依赖
log "[1/8] 更新系统并安装依赖..."
apt update || handle_error "系统更新失败"
apt install -y python3 python3-pip python3-venv mysql-server libmysqlclient-dev git || handle_error "依赖安装失败"

# 创建Python虚拟环境
log "[2/8] 创建Python虚拟环境..."
python3 -m venv "$INSTALL_DIR/venv" || handle_error "创建Python虚拟环境失败"
source "$INSTALL_DIR/venv/bin/activate" || handle_error "激活Python虚拟环境失败"
pip install --upgrade pip || handle_error "升级pip失败"

# 复制或创建requirements.txt
cat > "$INSTALL_DIR/requirements.txt" <<EOL
web.py>=0.62
pymysql>=1.0.2
lxml>=4.6.3
requests>=2.25.1
cryptography>=3.4.7
python-dateutil>=2.8.2
APScheduler>=3.9.1
EOL

# 安装Python依赖
pip install -r "$INSTALL_DIR/requirements.txt" || handle_error "安装Python依赖失败"

# 配置MySQL
log "[3/8] 配置MySQL数据库..."
# 检查MySQL服务状态
systemctl start mysql || handle_error "启动MySQL服务失败"
systemctl enable mysql || log "无法设置MySQL开机自启动，请手动设置"

# 创建数据库和用户
mysql -e "CREATE DATABASE IF NOT EXISTS douban DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || handle_error "创建数据库失败"
mysql -e "CREATE USER IF NOT EXISTS 'douban_user'@'localhost' IDENTIFIED BY 'MySQL_20050816Zln@233';" || handle_error "创建数据库用户失败"
mysql -e "GRANT ALL PRIVILEGES ON douban.* TO 'douban_user'@'localhost';" || handle_error "授予数据库权限失败"
mysql -e "FLUSH PRIVILEGES;" || handle_error "刷新数据库权限失败"

# 创建数据库表结构
log "[4/8] 创建数据库表结构..."
cat > "$INSTALL_DIR/sql/init_tables.sql" <<EOL
-- 电影信息表
CREATE TABLE IF NOT EXISTS douban_movie (
    id INT UNSIGNED AUTO_INCREMENT,
    title VARCHAR(100) NOT NULL,
    score FLOAT,
    num INT,
    link VARCHAR(200) NOT NULL,
    time DATE,
    address VARCHAR(50),
    other_release VARCHAR(100),
    actors VARCHAR(1000),
    director VARCHAR(200),
    category VARCHAR(100),
    PRIMARY KEY(id),
    UNIQUE KEY idx_link (link),
    KEY idx_category (category),
    KEY idx_score (score)
) DEFAULT CHARSET=utf8mb4;

-- 用户信息表
CREATE TABLE IF NOT EXISTS user_info (
    id INT UNSIGNED AUTO_INCREMENT,
    wx_id VARCHAR(100) NOT NULL,
    start_time BIGINT,
    last_active_time BIGINT,
    user_name VARCHAR(50),
    PRIMARY KEY(id),
    UNIQUE KEY idx_wx_id (wx_id)
) DEFAULT CHARSET=utf8mb4;

-- 用户搜索记录表
CREATE TABLE IF NOT EXISTS seek_movie (
    id INT UNSIGNED AUTO_INCREMENT,
    user_id INT NOT NULL,
    movie_id INT NOT NULL,
    seek_time BIGINT,
    search_term VARCHAR(100),
    PRIMARY KEY(id),
    KEY idx_user_id (user_id),
    KEY idx_movie_id (movie_id),
    KEY idx_seek_time (seek_time)
) DEFAULT CHARSET=utf8mb4;

-- 用户评分表
CREATE TABLE IF NOT EXISTS like_movie (
    id INT UNSIGNED AUTO_INCREMENT,
    user_id INT NOT NULL,
    movie_id INT NOT NULL,
    liking FLOAT,
    rating_time BIGINT,
    PRIMARY KEY(id),
    UNIQUE KEY idx_user_movie (user_id, movie_id),
    KEY idx_user_id (user_id),
    KEY idx_movie_id (movie_id)
) DEFAULT CHARSET=utf8mb4;
EOL

mysql -u douban_user -p'MySQL_20050816Zln@233' douban < "$INSTALL_DIR/sql/init_tables.sql" || handle_error "创建数据库表结构失败"

# 创建示例电影数据
log "[5/8] 导入示例电影数据..."
# 这里会在后面放置更丰富的电影数据

# 配置文件
log "[6/8] 创建配置文件..."
mkdir -p "$INSTALL_DIR/config"
cat > "$INSTALL_DIR/config/database.conf" <<EOL
[database]
host = localhost
port = 3306
user = douban_user
password = MySQL_20050816Zln@233
db = douban
charset = utf8mb4
EOL

# 修改Python文件使其适配Python 3
log "[7/8] 更新代码到Python 3兼容..."
# 这部分代码将在后续步骤中添加

# 创建启动和检查脚本
log "[8/8] 创建服务启动和端口检查脚本..."

# 端口检查脚本
cat > "$INSTALL_DIR/scripts/check_port.sh" <<EOL
#!/bin/bash
# 检查端口是否被占用，如果被占用则杀死占用进程

PORT=\$1
if [ -z "\$PORT" ]; then
    echo "请指定要检查的端口号，例如: ./check_port.sh 80"
    exit 1
fi

echo "检查端口 \$PORT 是否被占用..."
PID=\$(lsof -t -i:\$PORT)

if [ -z "\$PID" ]; then
    echo "端口 \$PORT 未被占用。"
    exit 0
else
    echo "端口 \$PORT 被进程 \$PID 占用。尝试终止该进程..."
    kill -9 \$PID
    sleep 1
    
    # 再次检查端口是否已释放
    PID=\$(lsof -t -i:\$PORT)
    if [ -z "\$PID" ]; then
        echo "端口 \$PORT 已成功释放。"
        exit 0
    else
        echo "无法释放端口 \$PORT。请手动检查进程 \$PID。"
        exit 1
    fi
fi
EOL

# 服务启动脚本
cat > "$INSTALL_DIR/scripts/start_service.sh" <<EOL
#!/bin/bash
# 微信公众号电影推荐系统启动脚本

INSTALL_DIR="/opt/recommender"
LOG_FILE="\$INSTALL_DIR/logs/web_server.log"

echo "启动微信公众号电影推荐系统..."

# 检查端口占用情况
\$INSTALL_DIR/scripts/check_port.sh 80

# 激活虚拟环境
source \$INSTALL_DIR/venv/bin/activate

# 进入web_server目录
cd \$INSTALL_DIR/web_server

# 在后台启动服务
nohup python3 main.py 80 > \$LOG_FILE 2>&1 &

# 获取进程ID
PID=\$!
echo "\$PID" > \$INSTALL_DIR/logs/service.pid

echo "服务已启动，进程ID: \$PID"
echo "日志文件位置: \$LOG_FILE"
EOL

# 服务重启脚本
cat > "$INSTALL_DIR/scripts/restart_service.sh" <<EOL
#!/bin/bash
# 重启微信公众号电影推荐系统

INSTALL_DIR="/opt/recommender"

echo "重启微信公众号电影推荐系统..."

# 如果存在PID文件，则先停止服务
if [ -f \$INSTALL_DIR/logs/service.pid ]; then
    PID=\$(cat \$INSTALL_DIR/logs/service.pid)
    echo "尝试停止进程 \$PID..."
    kill \$PID 2>/dev/null
    rm \$INSTALL_DIR/logs/service.pid
fi

# 调用检查端口脚本，确保80端口可用
\$INSTALL_DIR/scripts/check_port.sh 80

# 启动服务
\$INSTALL_DIR/scripts/start_service.sh
EOL

# 数据库备份脚本
cat > "$INSTALL_DIR/scripts/backup_db.sh" <<EOL
#!/bin/bash
# 数据库备份脚本

INSTALL_DIR="/opt/recommender"
BACKUP_DIR="\$INSTALL_DIR/backup"
DATE=\$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="\$BACKUP_DIR/douban_\$DATE.sql"

# 创建备份目录
mkdir -p \$BACKUP_DIR

# 备份数据库
echo "正在备份数据库到 \$BACKUP_FILE..."
mysqldump -u douban_user -p'MySQL_20050816Zln@233' douban > "\$BACKUP_FILE"

if [ \$? -eq 0 ]; then
    echo "备份成功！"
    # 删除7天前的备份
    find \$BACKUP_DIR -name "douban_*.sql" -mtime +7 -delete
    echo "已删除7天前的旧备份"
else
    echo "备份失败！请检查错误信息。"
fi
EOL

# 服务健康检查脚本
cat > "$INSTALL_DIR/scripts/health_check.sh" <<EOL
#!/bin/bash
# 系统健康检查脚本

INSTALL_DIR="/opt/recommender"
LOG_FILE="\$INSTALL_DIR/logs/health_check.log"
SERVICE_PID_FILE="\$INSTALL_DIR/logs/service.pid"

log() {
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$1" | tee -a \$LOG_FILE
}

restart_service() {
    log "正在重启服务..."
    \$INSTALL_DIR/scripts/restart_service.sh
    log "服务已重启"
}

# 检查服务是否运行
check_service() {
    if [ ! -f \$SERVICE_PID_FILE ]; then
        log "服务PID文件不存在，服务可能未运行"
        restart_service
        return
    fi
    
    PID=\$(cat \$SERVICE_PID_FILE)
    if ! ps -p \$PID > /dev/null; then
        log "服务进程 \$PID 不存在，重启服务"
        restart_service
    else
        log "服务运行正常，PID: \$PID"
    fi
}

# 检查网站可访问性
check_website() {
    HTTP_CODE=\$(curl -s -o /dev/null -w "%{http_code}" http://localhost)
    if [ "\$HTTP_CODE" != "200" ]; then
        log "网站返回HTTP状态码 \$HTTP_CODE，不是200，重启服务"
        restart_service
    else
        log "网站可正常访问，HTTP状态码: \$HTTP_CODE"
    fi
}

# 检查数据库连接
check_database() {
    if ! mysql -u douban_user -p'MySQL_20050816Zln@233' -e "SELECT 1" douban > /dev/null 2>&1; then
        log "数据库连接失败，尝试重启MySQL服务"
        systemctl restart mysql
    else
        log "数据库连接正常"
    fi
}

# 主函数
main() {
    log "开始系统健康检查..."
    check_service
    check_website
    check_database
    log "健康检查完成"
}

# 执行主函数
main
EOL

# 设置脚本执行权限
chmod +x "$INSTALL_DIR/scripts/"*.sh || handle_error "设置脚本执行权限失败"

# 创建cron任务
log "设置定时任务..."
(crontab -l 2>/dev/null; echo "0 2 * * * $INSTALL_DIR/scripts/backup_db.sh") | crontab - || log "设置备份任务失败，请手动设置"
(crontab -l 2>/dev/null; echo "*/10 * * * * $INSTALL_DIR/scripts/health_check.sh") | crontab - || log "设置健康检查任务失败，请手动设置"

# 设置目录权限
chown -R root:root "$INSTALL_DIR" || handle_error "设置目录所有者失败"
chmod -R 755 "$INSTALL_DIR" || handle_error "设置目录权限失败"

# 计算耗时
end_time=$(date +%s)
duration=$((end_time - start_time))

log "=============================="
log "部署完成！总耗时: $duration 秒"
log "现在您可以启动服务：$INSTALL_DIR/scripts/start_service.sh"
log "==============================" 