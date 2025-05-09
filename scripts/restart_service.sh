#!/bin/bash
# 重启微信公众号电影推荐系统

echo "重启微信公众号电影推荐系统..."

# 如果存在PID文件，则先停止服务
if [ -f logs/service.pid ]; then
    PID=$(cat logs/service.pid)
    echo "尝试停止进程 $PID..."
    kill $PID 2>/dev/null
    rm logs/service.pid
fi

# 调用检查端口脚本，确保80端口可用
./scripts/check_port.sh 80

# 启动服务
./scripts/start_service.sh 