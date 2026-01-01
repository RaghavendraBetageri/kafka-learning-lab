#!/bin/bash
# Start Kafka Broker 1

echo "Starting Kafka Broker 1 on port 9093..."
cd ~/kafka-learning-lab
kafka/bin/kafka-server-start.sh config/server-1.properties
