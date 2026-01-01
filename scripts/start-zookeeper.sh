#!/bin/bash
# Start ZooKeeper for Kafka cluster

echo "Starting ZooKeeper..."
cd ~/kafka-learning-lab
kafka/bin/zookeeper-server-start.sh config/zookeeper.properties
