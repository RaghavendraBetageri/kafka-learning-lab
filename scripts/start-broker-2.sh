#!/bin/bash
# Start Kafka Broker 2

echo "Starting Kafka Broker 2 on port 9094..."
cd ~/kafka-learning-lab
kafka/bin/kafka-server-start.sh config/server-2.properties
