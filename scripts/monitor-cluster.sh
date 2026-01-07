#!/bin/bash
# Smart cluster monitor - General cluster info OR specific topic monitoring

TOPIC=${1:-}  # Empty by default
ONE_TIME=${2:-false}
BROKER_PORTS=(9092 9093 9094)

# Determine mode
if [ -z "$TOPIC" ]; then
  MODE="cluster"
  echo "===== Kafka Cluster Overview Monitor ====="
else
  MODE="topic"
  echo "===== Monitoring Topic: $TOPIC ====="
fi

echo "Running on: $(uname -s) $(uname -m)"
echo "Press Ctrl+C to stop"
echo ""

# Function: Get any available broker
get_available_broker() {
  for port in "${BROKER_PORTS[@]}"; do
    if nc -z -w 1 localhost $port 2>/dev/null; then
      echo "$port"
      return 0
    fi
  done
  return 1
}

# Function: Try to get topic info from any available broker
get_topic_info() {
  local topic=$1
  
  for port in "${BROKER_PORTS[@]}"; do
    if nc -z -w 1 localhost $port 2>/dev/null; then
      local result
      if command -v gtimeout > /dev/null 2>&1; then
        result=$(gtimeout 3 ~/kafka-learning-lab/kafka/bin/kafka-topics.sh --describe \
          --topic "$topic" \
          --bootstrap-server "localhost:$port" \
          --command-config <(echo "request.timeout.ms=2000") 2>/dev/null)
      else
        result=$(timeout_command 3 ~/kafka-learning-lab/kafka/bin/kafka-topics.sh --describe \
          --topic "$topic" \
          --bootstrap-server "localhost:$port" \
          --command-config <(echo "request.timeout.ms=2000") 2>/dev/null)
      fi
      
      if [ $? -eq 0 ] && [ -n "$result" ]; then
        echo "$result"
        echo ""
        echo "  📡 Connected via localhost:$port (Broker $((port - 9092)))"
        return 0
      fi
    fi
  done
  
  echo "  ⚠️  Cannot connect to any broker"
  return 1
}

# Function: Get cluster-wide info
get_cluster_info() {
  local port
  port=$(get_available_broker)
  
  if [ -z "$port" ]; then
    echo "  ⚠️  No brokers available"
    return 1
  fi
  
  echo "📊 Cluster Metadata:"
  echo ""
  
  # Get cluster ID and controller
  if command -v gtimeout > /dev/null 2>&1; then
    CLUSTER_INFO=$(gtimeout 3 ~/kafka-learning-lab/kafka/bin/kafka-metadata.sh \
      --bootstrap-server "localhost:$port" \
      --command-config <(echo "request.timeout.ms=2000") 2>/dev/null | head -5)
  fi
  
  # Get broker list
  echo "  Registered Brokers:"
  if command -v gtimeout > /dev/null 2>&1; then
    BROKER_LIST=$(gtimeout 3 ~/kafka-learning-lab/kafka/bin/kafka-broker-api-versions.sh \
      --bootstrap-server "localhost:$port" 2>/dev/null | grep -E "^localhost:" | sort)
  else
    BROKER_LIST=$(timeout_command 3 ~/kafka-learning-lab/kafka/bin/kafka-broker-api-versions.sh \
      --bootstrap-server "localhost:$port" 2>/dev/null | grep -E "^localhost:" | sort)
  fi
  
  if [ -n "$BROKER_LIST" ]; then
    echo "$BROKER_LIST" | while read -r line; do
      broker_port=$(echo "$line" | cut -d: -f2 | cut -d'(' -f1)
      broker_id=$((broker_port - 9092))
      echo "    ✅ Broker $broker_id (localhost:$broker_port)"
    done
  else
    echo "    ⚠️  Could not fetch broker list"
  fi
  
  echo ""
  echo "  📡 Connected via localhost:$port (Broker $((port - 9092)))"
  echo ""
  
  # List all topics
  echo "📝 Topics in Cluster:"
  echo ""
  if command -v gtimeout > /dev/null 2>&1; then
    TOPICS=$(gtimeout 3 ~/kafka-learning-lab/kafka/bin/kafka-topics.sh --list \
      --bootstrap-server "localhost:$port" \
      --command-config <(echo "request.timeout.ms=2000") 2>/dev/null)
  else
    TOPICS=$(timeout_command 3 ~/kafka-learning-lab/kafka/bin/kafka-topics.sh --list \
      --bootstrap-server "localhost:$port" \
      --command-config <(echo "request.timeout.ms=2000") 2>/dev/null)
  fi
  
  if [ -n "$TOPICS" ]; then
    TOPIC_COUNT=$(echo "$TOPICS" | wc -l | tr -d ' ')
    echo "  Total Topics: $TOPIC_COUNT"
    echo ""
    echo "$TOPICS" | head -20 | while read -r topic_name; do
      echo "    • $topic_name"
    done
    
    if [ "$TOPIC_COUNT" -gt 20 ]; then
      echo "    ... and $((TOPIC_COUNT - 20)) more"
    fi
  else
    echo "  ⚠️  No topics found or unable to fetch"
  fi
  
  echo ""
  
  # Check for under-replicated partitions
  echo "⚠️  Under-Replicated Partitions:"
  echo ""
  if command -v gtimeout > /dev/null 2>&1; then
    UNDER_REP=$(gtimeout 3 ~/kafka-learning-lab/kafka/bin/kafka-topics.sh --describe \
      --under-replicated-partitions \
      --bootstrap-server "localhost:$port" \
      --command-config <(echo "request.timeout.ms=2000") 2>/dev/null)
  else
    UNDER_REP=$(timeout_command 3 ~/kafka-learning-lab/kafka/bin/kafka-topics.sh --describe \
      --under-replicated-partitions \
      --bootstrap-server "localhost:$port" \
      --command-config <(echo "request.timeout.ms=2000") 2>/dev/null)
  fi
  
  if [ -z "$UNDER_REP" ]; then
    echo "  ✅ None - All partitions are healthy!"
  else
    echo "$UNDER_REP" | while read -r line; do
      echo "  🔴 $line"
    done
  fi
}

# Fallback timeout function
timeout_command() {
  local timeout=$1
  shift
  "$@" &
  local pid=$!
  local count=0
  while [ $count -lt $timeout ]; do
    if ! kill -0 $pid 2>/dev/null; then
      wait $pid
      return $?
    fi
    sleep 1
    count=$((count + 1))
  done
  kill -9 $pid 2>/dev/null
  wait $pid 2>/dev/null
  return 124
}

# Main monitoring loop
while true; do
  
  echo "========================================== ** =========================================="
  if [ "$MODE" = "cluster" ]; then
    echo "  Kafka Cluster Health Monitor"
  else
    echo "  Topic Monitor: $TOPIC"
  fi
  echo "  Time: $(date '+%H:%M:%S')"
  echo "=========================================="
  echo ""
  
  # Show appropriate information based on mode
  if [ "$MODE" = "cluster" ]; then
    get_cluster_info
  else
    echo "📊 Topic Information:"
    get_topic_info "$TOPIC"
  fi
  
  echo ""
  echo "=========================================="
  echo "🖥️  Broker Process Status:"
  echo ""
  
  for i in {0..2}; do
    PORT=$((9092 + i))
    
    if pgrep -f "server-$i.properties" > /dev/null; then
      PID=$(pgrep -f "server-$i.properties")
      
      # Get process state (remove trailing +)
      STATE=$(ps -o state= -p $PID 2>/dev/null | tr -d ' ' | sed 's/+$//')
      
      # Check port connectivity
      if nc -z -w 1 localhost $PORT 2>/dev/null; then
        PORT_STATUS="✅ Port responding"
      else
        PORT_STATUS="❌ Port not responding"
      fi
      
      # Display status based on process state
      case "$STATE" in
        T)
          echo "  ❄️  Broker $i - PID: $PID - Port: $PORT - FROZEN (SIGSTOP) - $PORT_STATUS"
          ;;
        S|I)
          echo "  ✅ Broker $i - PID: $PID - Port: $PORT - RUNNING - $PORT_STATUS"
          ;;
        R)
          echo "  ✅ Broker $i - PID: $PID - Port: $PORT - RUNNING (active) - $PORT_STATUS"
          ;;
        D)
          echo "  ⏳ Broker $i - PID: $PID - Port: $PORT - I/O WAIT (disk bottleneck) - $PORT_STATUS"
          ;;
        Z)
          echo "  💀 Broker $i - PID: $PID - Port: $PORT - ZOMBIE (defunct) - $PORT_STATUS"
          ;;
        *)
          echo "  ⚠️  Broker $i - PID: $PID - Port: $PORT - STATE: $STATE - $PORT_STATUS"
          ;;
      esac
    else
      echo "  ❌ Broker $i - Port: $PORT - NOT RUNNING (no process found)"
    fi
  done
  
  echo ""
  echo "=========================================="
  echo "🐘 ZooKeeper Status:"
  echo ""
  
  # Check ZooKeeper process
  if pgrep -f "org.apache.zookeeper" > /dev/null; then
    ZK_PID=$(pgrep -f "org.apache.zookeeper")
    echo "  ✅ ZooKeeper - PID: $ZK_PID - RUNNING"
    
    # Check ZooKeeper connectivity
    if nc -z -w 1 localhost 2181 2>/dev/null; then
      echo "  ✅ Port 2181 - Responding"
      
      # Try to get ZooKeeper status
      ZK_STATUS=$(echo "stat" | nc localhost 2181 2>/dev/null | grep -E "Mode:|Clients:" | head -2)
      if [ -n "$ZK_STATUS" ]; then
        echo "$ZK_STATUS" | while read -r line; do
          echo "    $line"
        done
      fi
    else
      echo "  ❌ Port 2181 - Not responding"
    fi
  else
    echo "  ❌ ZooKeeper - NOT RUNNING"
  fi
  
  echo ""
  echo "=========================================="
  echo "💾 Disk Usage (Kafka Logs):"
  echo ""
  
  if ls /tmp/kafka-logs-* >/dev/null 2>&1; then
    df -h /tmp/kafka-logs-* 2>/dev/null | tail -n +2 | awk '{
      usage = substr($5, 1, length($5)-1);
      icon = (usage >= 80) ? "🔴" : (usage >= 60) ? "🟡" : "🟢";
      print "  " icon "  " $9 ": " $5 " used (" $4 " free)"
    }' | sort -u
  else
    echo "  ⚠️  No Kafka log directories found in /tmp"
  fi
  
  echo ""
  echo "=========================================="
  if [ "$ONE_TIME" = "true" ]; then
    exit 0
  else
    echo "Next refresh in 3 seconds... (Ctrl+C to stop)"
  fi
  
  sleep 3
done