#!/bin/bash
# Robust Kafka + ZooKeeper shutdown script

set -e

echo "=============================="
echo "Stopping Kafka Cluster Safely"
echo "=============================="

echo ""
echo "🔍 Detecting Kafka broker processes..."

KAFKA_PIDS=$(pgrep -f 'kafka.Kafka' || true)

if [ -z "$KAFKA_PIDS" ]; then
  echo "✅ No Kafka brokers running"
else
  echo "⚠️  Found Kafka brokers: $KAFKA_PIDS"
  echo "🛑 Sending SIGTERM to Kafka brokers..."
  kill $KAFKA_PIDS

  sleep 10

  STILL_RUNNING=$(pgrep -f 'kafka.Kafka' || true)
  if [ -n "$STILL_RUNNING" ]; then
    echo "🔥 Kafka still running. Forcing shutdown..."
    kill -9 $STILL_RUNNING
  fi

  echo "✅ Kafka brokers stopped"
fi

echo ""
echo "🔍 Detecting ZooKeeper processes..."

ZK_PIDS=$(pgrep -f 'zookeeper' || true)

if [ -z "$ZK_PIDS" ]; then
  echo "✅ ZooKeeper not running"
else
  echo "⚠️  Found ZooKeeper PID(s): $ZK_PIDS"
  echo "🛑 Stopping ZooKeeper..."
  kill $ZK_PIDS

  sleep 5

  STILL_RUNNING_ZK=$(pgrep -f 'zookeeper' || true)
  if [ -n "$STILL_RUNNING_ZK" ]; then
    echo "🔥 ZooKeeper still running. Forcing shutdown..."
    kill -9 $STILL_RUNNING_ZK
  fi

  echo "✅ ZooKeeper stopped"
fi

echo ""
echo "🎯 Kafka cluster shutdown completed cleanly"
