#!/bin/bash
# Stop Kafka cluster cleanly

echo "Stopping Kafka brokers..."
kafka/bin/kafka-server-stop.sh

sleep 3

echo "Stopping ZooKeeper..."
kafka/bin/zookeeper-server-stop.sh

echo "All Kafka services stopped."
