#!/bin/bash
# =============================================================================
# Consumer Script - Consume messages with dynamic idle timeout
# =============================================================================
# Usage: ./consume-and-count.sh <topic> [idle-timeout-sec] [bootstrap-server]
#
# Parameters:
#   topic            - Kafka topic name (default: fault-test)
#   idle-timeout-sec - Seconds of inactivity before exit (default: 5)
#   bootstrap-server - Kafka broker address (default: localhost:9092,9093,9094)
#
# Examples:
#   ./consume-and-count.sh fault-test
#   ./consume-and-count.sh my-topic 10
#   ./consume-and-count.sh my-topic 5 localhost:9092
#
# Behavior:
#   - Consumes from beginning
#   - Exits after N seconds of no new messages
#   - Timer resets each time a message arrives
#   - Returns total message count to stdout
#
# Returns: Number of consumed messages (for scripting)
# =============================================================================

TOPIC=${1:-fault-test}
IDLE_TIMEOUT=${2:-5}
BOOTSTRAP=${3:-localhost:9092,localhost:9093,localhost:9094}

# -----------------------------
# Display cluster status
# -----------------------------
~/kafka-learning-lab/scripts/monitor-cluster.sh $TOPIC "true"


RESULTS_DIR=~/kafka-learning-lab/test-results
mkdir -p "$RESULTS_DIR"

RUN_ID=$(date +%s)-$$
OUTPUT_FILE="$RESULTS_DIR/kafka-consume-$RUN_ID.out"
RAW_OUTPUT="/tmp/kafka-raw-$RUN_ID.out"

# Cleanup on exit
cleanup() {
  # Kill all child processes
  pkill -P $$ 2>/dev/null
  rm -f "$RAW_OUTPUT"
}
trap cleanup EXIT

echo "📥 Starting consumer with dynamic idle timeout..." >&2
echo "  Topic        : $TOPIC" >&2
echo "  Idle Timeout : ${IDLE_TIMEOUT}s" >&2
echo "  Bootstrap    : $BOOTSTRAP" >&2
echo "" >&2
echo "⏳ Consuming messages..." >&2

# -----------------------------
# Start Kafka consumer in background
# -----------------------------
~/kafka-learning-lab/kafka/bin/kafka-console-consumer.sh \
  --topic "$TOPIC" \
  --bootstrap-server "$BOOTSTRAP" \
  --from-beginning \
  > "$RAW_OUTPUT" 2>&1 &

CONSUMER_PID=$!

# Give consumer a moment to start
sleep 1

# -----------------------------
# Monitor output with idle detection
# -----------------------------
MESSAGE_COUNT=0
LAST_MESSAGE_TIME=$(date +%s)
LAST_LINE=0
CONSUMER_STARTED=false
ERROR_SHOWN=false

while kill -0 $CONSUMER_PID 2>/dev/null; do
  # Get current line count
  if [ -f "$RAW_OUTPUT" ]; then
    CURRENT_LINES=$(wc -l < "$RAW_OUTPUT" 2>/dev/null | tr -d ' ')
    
    # Process new lines
    if [ "$CURRENT_LINES" -gt "$LAST_LINE" ]; then
      # Extract new lines
      NEW_CONTENT=$(tail -n +$((LAST_LINE + 1)) "$RAW_OUTPUT")
      
      # Process each new line
      while IFS= read -r line; do
        # Check if it's an error/warning or actual message
        if echo "$line" | grep -qiE "ERROR|Exception|NotEnoughReplicas|TimeoutException|UnknownTopicOrPartition|LEADER_NOT_AVAILABLE"; then
          # Print errors (only first few to avoid spam)
          if [ "$ERROR_SHOWN" = false ]; then
            echo "❌ ERROR: $line" >&2
            ERROR_SHOWN=true
          fi
        elif echo "$line" | grep -qiE "WARN|Connection refused|Disconnected|could not be established|node -[0-9]"; then
          # Print warnings (only first few to avoid spam)
          if [ "$ERROR_SHOWN" = false ]; then
            echo "⚠️  WARN: $line" >&2
          fi
        elif echo "$line" | grep -qiE "Processed a total of"; then
          # Ignore summary line
          :
        elif [ -n "$line" ]; then
          # It's a message - save it
          echo "$line" >> "$OUTPUT_FILE"
          ((MESSAGE_COUNT++))
          CONSUMER_STARTED=true
          LAST_MESSAGE_TIME=$(date +%s)
          ERROR_SHOWN=false  # Reset for next batch
          
          # Show progress
          if (( MESSAGE_COUNT % 100 == 0 )); then
            echo "  📊 Messages consumed: $MESSAGE_COUNT" >&2
          fi
        fi
      done <<< "$NEW_CONTENT"
      
      LAST_LINE=$CURRENT_LINES
    fi
  fi
  
  # Check idle timeout
  CURRENT_TIME=$(date +%s)
  IDLE_DURATION=$((CURRENT_TIME - LAST_MESSAGE_TIME))
  
  if [ "$CONSUMER_STARTED" = true ] && [ $IDLE_DURATION -ge $IDLE_TIMEOUT ]; then
    echo "" >&2
    echo "⏱️  No messages for ${IDLE_TIMEOUT}s - stopping consumer" >&2
    kill -9 $CONSUMER_PID 2>/dev/null
    break
  fi
  
  # If consumer hasn't started and we've waited too long, exit
  if [ "$CONSUMER_STARTED" = false ] && [ $IDLE_DURATION -ge $((IDLE_TIMEOUT * 2)) ]; then
    echo "" >&2
    echo "⏱️  No messages received within $((IDLE_TIMEOUT * 2))s - stopping" >&2
    kill -9 $CONSUMER_PID 2>/dev/null
    break
  fi
  
  # Sleep briefly before next check
  sleep 0.5
done

# Force kill if still running
kill -9 $CONSUMER_PID 2>/dev/null
wait $CONSUMER_PID 2>/dev/null

# -----------------------------
# Final count validation
# -----------------------------
if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
  ACTUAL_COUNT=$(wc -l < "$OUTPUT_FILE" | tr -d ' ')
  MESSAGE_COUNT=$ACTUAL_COUNT
fi

# -----------------------------
# Summary
# -----------------------------
echo "" >&2
echo "===== Consumer Summary =====" >&2
echo "📊 Total messages : $MESSAGE_COUNT" >&2
echo "💾 Output file    : $OUTPUT_FILE" >&2

if [ $MESSAGE_COUNT -eq 0 ]; then
  echo "⚠️  No messages found in topic" >&2
fi

echo "" >&2

# Return count for scripting
echo "===RETURN_VALUE==="
echo "$MESSAGE_COUNT"
# exit 0