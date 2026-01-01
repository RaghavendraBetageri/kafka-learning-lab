#!/bin/bash
# Start Kafka Broker 0

echo "Starting Kafka Broker 0 on port 9092..."
cd ~/kafka-learning-lab
kafka/bin/kafka-server-start.sh config/server-0.properties
