# 电影推荐系统部署指南

## 快速重启指南

如果您已经完成部署，但服务无法正常访问，请按以下步骤重启系统：

```bash
# 停止服务
sudo systemctl stop movie-recommender.service

# 编辑服务配置文件
sudo nano /etc/systemd/system/movie-recommender.service

# 修改ExecStart行如下
# ExecStart=/usr/bin/python3 /opt/recommender/web_server/main.py

# 保存并退出(Ctrl+O, Enter, Ctrl+X)

# 重载服务配置
sudo systemctl daemon-reload

# 启动服务
sudo systemctl start movie-recommender.service

# 检查服务状态
sudo systemctl status movie-recommender.service

# 查看详细日志
sudo journalctl -u movie-recommender.service -f
```

如果仍然无法访问，检查防火墙设置：

```bash
# 开放80端口
sudo ufw allow 80/tcp

# 重启防火墙
sudo ufw reload
```

## 电影推荐系统自动化部署指南

> 作者：电影推荐系统团队
> 日期：2023-05-20

本文档将指导您如何在Ubuntu服务器上部署电影推荐系统。适合Linux新手按步骤操作。

## 基础知识

### Ubuntu基本命令

```bash
# 查看当前目录
pwd

# 列出文件和目录
ls -la

# 切换目录
cd /path/to/directory

# 创建目录
mkdir directory_name

# 复制文件或目录
cp source destination

# 移动或重命名文件
mv source destination

# 删除文件
rm filename

# 删除目录及其内容
rm -rf directory_name

# 查看文件内容
cat filename

# 编辑文件
nano filename  # 或 vim filename

# 查看磁盘空间
df -h

# 查看系统进程
ps aux | grep process_name

# 查看网络连接
netstat -tuln

# 安装软件包
sudo apt update
sudo apt install package_name
```

### Git基本命令

```bash
# 克隆远程仓库
git clone https://github.com/username/repository.git

# 获取最新代码
git pull

# 查看状态
git status

# 添加文件到暂存区
git add filename

# 提交更改
git commit -m "提交说明"

# 推送到远程仓库
git push

# 切换分支
git checkout branch_name

# 创建并切换到新分支
git checkout -b new_branch_name
```

## 环境要求

- Ubuntu 服务器（推荐Ubuntu 20.04或以上）
- Python 3.7+
- MySQL 5.7+
- 开放80端口（微信公众号要求）
- root或sudo权限
- 至少1GB RAM和10GB可用磁盘空间

## 电影推荐系统自动化部署指南

> 作者：电影推荐系统团队
> 日期：2023-05-20

### 部署前准备

1. 一台安装了Ubuntu系统的服务器（推荐Ubuntu 18.04或更高版本）
2. 具有root或sudo权限的用户帐号
3. 已安装MySQL服务器（推荐MySQL 5.7或更高版本）

### 自动化部署步骤

#### 1. 获取项目代码

```bash
# 创建项目目录
mkdir -p /tmp/recommender

# 下载项目代码（根据实际情况替换为你的Git地址）
git clone https://github.com/Boulea7/Movie_recommender_wechat /tmp/recommender
# 或者使用scp从本地上传
# scp -r /path/to/local/recommender/* user@server:/tmp/recommender/
```

#### 2. 运行自动部署脚本

```bash
# 进入项目目录
cd /tmp/recommender

# 添加脚本执行权限
chmod +x scripts/*.sh

# 运行部署脚本（需要root权限）
sudo INSTALL_DIR=/opt/recommender bash scripts/deploy.sh
```

部署脚本会自动完成以下操作：
- 安装必要的系统依赖
- 设置应用程序目录结构
- 备份现有安装（如果存在）
- 安装Python依赖包
- 初始化数据库和导入样本数据
- 配置系统服务并启动应用

#### 3. 验证部署结果

部署完成后，可以通过以下命令检查服务状态：

```bash
# 查看服务状态
sudo systemctl status movie-recommender.service

# 查看应用日志
sudo journalctl -u movie-recommender.service -f
```

应用默认会监听80端口，可以通过访问 `http://服务器IP` 来验证应用是否正常运行。

### 手动部署步骤（如自动部署失败）

如果自动部署脚本运行失败，可以按照以下步骤手动部署：

#### 1. 安装系统依赖

```bash
sudo apt-get update
sudo apt-get install -y python python-pip mysql-client libmysqlclient-dev
```

#### 2. 配置应用程序目录

```bash
# 创建安装目录
sudo mkdir -p /opt/recommender

# 复制项目文件
sudo cp -r /tmp/recommender/* /opt/recommender/

# 设置执行权限
sudo chmod +x /opt/recommender/scripts/*.sh
```

#### 3. 安装Python依赖

```bash
cd /opt/recommender
sudo pip install -r requirements.txt
```

#### 4. 初始化数据库

```bash
# 配置数据库连接信息（根据实际情况修改）
export DB_HOST=localhost
export DB_PORT=3306
export DB_ROOT_PASSWORD=your_mysql_root_password
export DB_NAME=douban
export DB_USER=douban_user
export DB_PASSWORD=your_user_password

# 运行数据库初始化脚本
sudo -E bash /opt/recommender/scripts/init_database.sh
```

#### 5. 手动启动应用

```bash
cd /opt/recommender
sudo python web_server/server.py
```

要将应用设置为后台服务，可以创建系统服务文件：

```bash
sudo bash -c 'cat > /etc/systemd/system/movie-recommender.service << EOF
[Unit]
Description=电影推荐系统服务
After=network.target mysql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/recommender
ExecStart=/usr/bin/python /opt/recommender/web_server/server.py
Restart=on-failure
RestartSec=5
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=movie-recommender

[Install]
WantedBy=multi-user.target
EOF'

# 重载系统服务
sudo systemctl daemon-reload

# 启动服务
sudo systemctl enable movie-recommender.service
sudo systemctl start movie-recommender.service
```

### 故障排除

如果部署过程中遇到问题，请检查以下几点：

1. MySQL服务是否正常运行？
   ```bash
   sudo systemctl status mysql
   ```

2. 数据库是否正确初始化？
   ```bash
   mysql -u root -p -e "SHOW DATABASES;"
   mysql -u root -p -e "USE douban; SHOW TABLES;"
   ```

3. 检查应用日志文件：
   ```bash
   sudo cat /opt/recommender/logs/deploy_*.log
   sudo cat /opt/recommender/logs/db_init_*.log
   sudo cat /opt/recommender/logs/data_processing.log
   ```

4. 检查系统服务日志：
   ```bash
   sudo journalctl -u movie-recommender.service
   ```

5. 检查防火墙是否允许80端口通信：
   ```bash
   sudo ufw status
   # 如需开放端口
   sudo ufw allow 80/tcp
   ```

### 更新应用

如需更新应用，只需重新运行部署脚本即可。脚本会自动备份现有安装，然后再部署新版本：

```bash
# 进入新版本代码目录
cd /path/to/new/version

# 运行部署脚本
sudo bash scripts/deploy.sh
```

### 系统维护

#### 重启服务

```bash
sudo systemctl restart movie-recommender.service
```

#### 停止服务

```bash
sudo systemctl stop movie-recommender.service
```

#### 查看日志

```bash
# 查看实时日志
sudo journalctl -u movie-recommender.service -f

# 查看最近100行日志
sudo journalctl -u movie-recommender.service -n 100
```

#### 数据库备份

```bash
# 备份数据库
mysqldump -u root -p douban > /opt/recommender_backups/douban_$(date +%Y%m%d).sql
```

#### 系统备份

```bash
# 备份整个系统
sudo cp -r /opt/recommender /opt/recommender_backups/recommender_$(date +%Y%m%d)
```

## 手动部署详细步骤

如果自动部署脚本出现问题，您可以按照以下步骤手动部署：

### 1. 准备安装目录

```bash
# 创建安装目录
sudo mkdir -p /opt/recommender
sudo mkdir -p /opt/recommender/{web_server,data_spider,scripts,sql,test_data,logs,backup,config}
```

### 2. 系统依赖安装

```bash
sudo apt update
sudo apt install -y python3 python3-pip python3-venv mysql-server libmysqlclient-dev git curl lsof
```

### 3. 创建Python虚拟环境

```bash
cd /opt/recommender
sudo python3 -m venv venv
sudo /opt/recommender/venv/bin/pip install --upgrade pip

# 创建requirements.txt
sudo bash -c 'cat > /opt/recommender/requirements.txt' << 'EOL'
web.py>=0.62
pymysql>=1.0.2
lxml>=4.6.3
requests>=2.25.1
cryptography>=3.4.7
python-dateutil>=2.8.2
APScheduler>=3.9.1
EOL

# 安装Python依赖
sudo /opt/recommender/venv/bin/pip install -r /opt/recommender/requirements.txt
```

### 4. 设置MySQL数据库

```bash
# 启动并设置MySQL自启动
sudo systemctl start mysql
sudo systemctl enable mysql

# 创建数据库和用户
sudo mysql -e "CREATE DATABASE IF NOT EXISTS douban DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
sudo mysql -e "CREATE USER IF NOT EXISTS 'douban_user'@'localhost' IDENTIFIED BY 'MySQL_20050816Zln@233';"
sudo mysql -e "GRANT ALL PRIVILEGES ON douban.* TO 'douban_user'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"
```

### 5. 创建数据库表结构

```bash
# 创建数据库表结构SQL文件
sudo bash -c 'cat > /opt/recommender/sql/init_tables.sql' << 'EOL'
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

# 导入表结构
sudo mysql -u douban_user -p'MySQL_20050816Zln@233' douban < /opt/recommender/sql/init_tables.sql
```

### 6. 创建数据库配置文件

```bash
sudo bash -c 'cat > /opt/recommender/config/database.conf' << 'EOL'
[database]
host = localhost
port = 3306
user = douban_user
password = MySQL_20050816Zln@233
db = douban
charset = utf8mb4
EOL
```

### 7. 创建启动和监控脚本

各种脚本的创建（启动、重启、健康检查等）请参见一键部署脚本的内容。

### 8. 设置文件权限

```bash
sudo chown -R root:root /opt/recommender
sudo chmod -R 755 /opt/recommender
sudo chmod +x /opt/recommender/scripts/*.sh
```

## 系统维护

### 1. 启动/停止/重启服务

```bash
# 启动服务
sudo /opt/recommender/scripts/start_service.sh

# 重启服务
sudo /opt/recommender/scripts/restart_service.sh

# 停止服务
sudo kill $(cat /opt/recommender/logs/service.pid)
```

### 2. 查看日志

```bash
# 查看实时服务日志
sudo tail -f /opt/recommender/logs/web_server.log

# 查看健康检查日志
sudo cat /opt/recommender/logs/health_check.log
```

### 3. 手动备份数据库

```bash
sudo /opt/recommender/scripts/backup_db.sh
```

### 4. 检查服务健康状态

```bash
sudo /opt/recommender/scripts/health_check.sh
```

### 5. 更新代码

```bash
# 进入代码目录
cd /opt/recommender

# 拉取最新代码
sudo git pull

# 重启服务
sudo /opt/recommender/scripts/restart_service.sh
```

## 常见问题排查

### 1. 服务无法启动

检查80端口是否被占用：

```bash
sudo netstat -tuln | grep 80
```

如果端口被占用，释放端口：

```bash
sudo /opt/recommender/scripts/check_port.sh 80
```

### 2. 数据库连接问题

检查数据库连接配置是否正确：

```bash
mysql -u douban_user -p'MySQL_20050816Zln@233' -e "SELECT 1;" douban
```

如果连接失败，可能需要重启MySQL：

```bash
sudo systemctl restart mysql
```

### 3. 微信公众号无法接收消息

检查微信公众号配置和服务器状态：

```bash
# 检查服务是否运行
ps aux | grep python

# 检查端口是否正常监听
sudo netstat -tuln | grep 80

# 测试服务可访问性
curl -v http://localhost/
```

确保URL、Token等微信公众平台配置正确。

### 4. 磁盘空间不足

检查并清理磁盘空间：

```bash
# 检查磁盘使用情况
df -h

# 检查日志大小
du -sh /opt/recommender/logs/

# 清理旧日志文件
find /opt/recommender/logs/ -name "*.log" -mtime +30 -delete

# 清理旧备份
find /opt/recommender/backup/ -name "*.sql" -mtime +30 -delete
```

### 5. 系统崩溃后的恢复

```bash
# 重启服务器后，可能需要手动启动服务
sudo /opt/recommender/scripts/start_service.sh

# 如果数据库损坏，可以从备份恢复
# 选择最新的备份文件
BACKUP_FILE=$(ls -t /opt/recommender/backup/douban_*.sql | head -1)
# 恢复数据库
mysql -u douban_user -p'MySQL_20050816Zln@233' douban < $BACKUP_FILE
```

## 安全建议

1. 定期更改数据库密码
2. 设置防火墙，仅开放必要端口
3. 定期更新系统和依赖包
4. 设置HTTPS提高安全性
5. 定期备份重要数据

### 4. 重启和维护系统

如果您需要重启系统，可以使用以下命令：

```bash
# 重启电影推荐系统服务
sudo systemctl restart movie-recommender.service

# 查看服务状态
sudo systemctl status movie-recommender.service

# 查看日志
sudo journalctl -u movie-recommender.service -f
```

如果遇到问题，可以检查日志文件：

```bash
# 查看Web服务器日志
sudo cat /opt/recommender/logs/web_server.log

# 查看数据库初始化日志
sudo ls -la /opt/recommender/logs/db_init_*.log
sudo cat /opt/recommender/logs/db_init_[最新日期].log
```

### 5. 常见问题排查

#### 1. 服务无法启动

检查服务状态和日志：
```bash
sudo systemctl status movie-recommender.service
sudo journalctl -u movie-recommender.service -n 50
```

可能的原因和解决方法：
- Python路径错误：修改服务文件中的Python路径
- 权限问题：确保服务有足够的权限
- 端口冲突：检查80端口是否被其他服务占用

#### 2. 网页可以访问但微信无法连接

- 检查微信公众号配置的URL是否正确
- 确认服务器80端口是否对外开放
- 验证Token配置是否正确（应与config/database.conf中的token一致）

#### 3. 数据库连接失败

```bash
# 检查数据库服务是否运行
sudo systemctl status mysql

# 尝试手动连接数据库
mysql -udouban_user -pMySQL_20050816Zln@233 -h localhost douban
```

可能的原因：
- MySQL服务未启动
- 数据库用户密码不正确
- 数据库权限配置有误 