#!/bin/bash
# Stop all Kafka brokers and ZooKeeper

echo "Stopping all Kafka brokers..."
pkill -f 'kafka.Kafka'

echo "Stopping ZooKeeper..."
pkill -f 'zookeeper'

echo "All services stopped."
