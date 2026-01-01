#!/bin/bash
# Clean up all Kafka and ZooKeeper data (WARNING: Deletes all data!)

echo "WARNING: This will delete all Kafka and ZooKeeper data!"
read -p "Are you sure? (yes/no): " confirm

if [ "$confirm" == "yes" ]; then
    echo "Stopping all services first..."
    ~/kafka-learning-lab/scripts/stop-all.sh
    
    sleep 3
    
    echo "Removing Kafka logs..."
    rm -rf /tmp/kafka-logs-0 /tmp/kafka-logs-1 /tmp/kafka-logs-2
    
    echo "Removing ZooKeeper data..."
    rm -rf /tmp/zookeeper
    
    echo "Cleanup complete!"
else
    echo "Cleanup cancelled."
fi
