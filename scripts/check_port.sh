#!/bin/bash
# 检查端口是否被占用，如果被占用则杀死占用进程

PORT=$1
if [ -z "$PORT" ]; then
    echo "请指定要检查的端口号，例如: ./check_port.sh 80"
    exit 1
fi

echo "检查端口 $PORT 是否被占用..."
PID=$(lsof -t -i:$PORT)

if [ -z "$PID" ]; then
    echo "端口 $PORT 未被占用。"
    exit 0
else
    echo "端口 $PORT 被进程 $PID 占用。尝试终止该进程..."
    kill -9 $PID
    sleep 1
    
    # 再次检查端口是否已释放
    PID=$(lsof -t -i:$PORT)
    if [ -z "$PID" ]; then
        echo "端口 $PORT 已成功释放。"
        exit 0
    else
        echo "无法释放端口 $PORT。请手动检查进程 $PID。"
        exit 1
    fi
fi 