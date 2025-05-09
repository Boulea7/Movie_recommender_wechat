#!/bin/bash
# 微信公众号电影推荐系统启动脚本

echo "启动微信公众号电影推荐系统..."

# 检查端口占用情况
./scripts/check_port.sh 80

# 激活虚拟环境
source venv/bin/activate

# 进入web_server目录
cd web_server

# 在后台启动服务
nohup python3 main.py 80 > ../logs/web_server.log 2>&1 &

# 获取进程ID
PID=$!
echo "$PID" > ../logs/service.pid

echo "服务已启动，进程ID: $PID"
echo "日志文件位置: ../logs/web_server.log" 