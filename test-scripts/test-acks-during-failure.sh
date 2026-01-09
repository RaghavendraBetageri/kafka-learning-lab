#!/bin/bash
# =============================================================================
# Acks Failure Test - Test producer behavior when broker fails
# =============================================================================
# Usage: ./test-acks-during-failure.sh <acks-level> [topic] [message-count] [broker-to-kill]
#
# Parameters:
#   acks-level       - Acknowledgment level: 0, 1, or all (required)
#   topic            - Kafka topic name (default: fault-test)
#   message-count    - Number of messages to send (default: 20)
#   broker-to-kill   - Broker ID to kill during test: 0, 1, or 2 (default: 1)
#
# Examples:
#   ./test-acks-during-failure.sh all
#   ./test-acks-during-failure.sh 1 fault-test 30 2
#   ./test-acks-during-failure.sh 0 my-topic 50 0
#
# Output: Creates detailed test report in ~/kafka-learning-lab/test-results/
# =============================================================================

# Validate required parameter
if [ -z "$1" ]; then
  echo "❌ Error: acks level is required"
  echo "Usage: $0 <acks-level> [topic] [message-count] [broker-to-kill]"
  echo "Example: $0 all fault-test 20 1"
  exit 1
fi

# Parse command line arguments with defaults
ACKS=${1}
TOPIC=${2:-fault-test}
COUNT=${3:-20}
BROKER_TO_KILL=${4:-1}

# Validate acks level
if [[ ! "$ACKS" =~ ^(0|1|all)$ ]]; then
  echo "❌ Error: Invalid acks level '$ACKS'. Must be 0, 1, or all"
  exit 1
fi

# Validate broker ID
if [[ ! "$BROKER_TO_KILL" =~ ^[0-2]$ ]]; then
  echo "❌ Error: Invalid broker ID '$BROKER_TO_KILL'. Must be 0, 1, or 2"
  exit 1
fi

# Create results directory if it doesn't exist
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RESULTS_DIR=~/kafka-learning-lab/test-results
mkdir -p "$RESULTS_DIR"
# RESULT_FILE="$RESULTS_DIR/acks-${ACKS}-test-${TIMESTAMP}.txt"

# Display test header
echo "=========================================="
echo "  Acks Failure Test - acks=$ACKS"
echo "=========================================="
echo "Topic: $TOPIC"
echo "Message Count: $COUNT"
echo "Broker to Kill: $BROKER_TO_KILL"
# echo "Results: $RESULT_FILE"
echo ""

~/kafka-learning-lab/scripts/monitor-cluster.sh $TOPIC "true"


# Log test configuration to file
# {
echo "===== Test Configuration ====="
echo "Test Time: $(date)"
echo "Acks Level: $ACKS"
echo "Topic: $TOPIC"
echo "Message Count: $COUNT"
echo "Broker to Kill: $BROKER_TO_KILL"
echo ""
# } > "$RESULT_FILE"

# Step 1: Check broker status
echo "🔧 Checking broker status..."
RUNNING_COUNT=0

for i in {0..2}; do
  if pgrep -f "server-$i.properties" > /dev/null; then
    echo "  ✅ Broker $i is running"
    RUNNING_COUNT=$((RUNNING_COUNT + 1))
  else
    echo "  ❌ Broker $i is NOT running"
  fi
done

echo ""

# Validate that we have enough brokers to run the test
if [ $RUNNING_COUNT -lt 2 ]; then
  echo "⚠️  Warning: Only $RUNNING_COUNT broker(s) running"
  echo "   Recommendation: Start brokers manually before running test"
  echo ""
  read -p "Continue anyway? (y/n): " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Test cancelled"
    exit 1
  fi
elif [ $RUNNING_COUNT -eq 3 ]; then
  echo "✅ All 3 brokers are running - ready for test"
else
  echo "✅ $RUNNING_COUNT brokers running - test can proceed"
fi
echo ""



# Step 2: Get current message count (baseline - before test)
echo "📊 Getting baseline message count..."
BASELINE=$(~/kafka-learning-lab/test-scripts/consume-and-count.sh \
  "$TOPIC" "3")
BASELINE=$(echo "$BASELINE" | sed -n '/===RETURN_VALUE===/,$ p' | tail -n 1)

echo "BASELINE" $BASELINE

if ! [[ "$BASELINE" =~ ^[0-9]+$ ]]; then
  BASELINE=0
fi
echo "  Current 'acks=$ACKS' messages in topic: $BASELINE"
echo ""

# Step 3: Start producer in background
echo "🚀 Starting producer (acks=$ACKS) in background..."
(~/kafka-learning-lab/test-scripts/produce-messages.sh \
  "$TOPIC" "$COUNT" "$ACKS" "acks=$ACKS" > /tmp/producer-$$.log 2>&1) &
PRODUCER_PID=$!

# Check if producer started successfully
sleep 2
if ! kill -0 $PRODUCER_PID 2>/dev/null; then
  echo "❌ Error: Producer failed to start"
  echo "Check logs: /tmp/producer-$$.log"
  exit 1
fi
echo "✅ Producer started (PID: $PRODUCER_PID)"
echo ""

# Step 4: Wait before killing broker
KILL_AFTER=5
echo "⏱️  Waiting ${KILL_AFTER}s to send some messages before failure..."
sleep $KILL_AFTER

# Step 5: Kill the broker
echo "⚡ Killing broker $BROKER_TO_KILL..."
pkill -9 -f "server-${BROKER_TO_KILL}.properties"
KILL_TIME=$(date +%H:%M:%S)

# Log failure event
# {
echo "===== Failure Event ====="
echo "Time: $KILL_TIME"
echo "Action: Killed broker $BROKER_TO_KILL"
echo ""
# } >> "$RESULT_FILE"

echo "✅ Broker $BROKER_TO_KILL killed at $KILL_TIME"
echo ""

# Step 6: Wait for producer to finish
echo "⏱️  Waiting for producer to complete..."
wait $PRODUCER_PID
PRODUCER_EXIT_CODE=$?

# Show producer logs
cat /tmp/producer-$$.log
echo ""

if [ $PRODUCER_EXIT_CODE -ne 0 ]; then
  echo "⚠️  Producer encountered errors (exit code: $PRODUCER_EXIT_CODE)"
fi

# Step 7: Wait for message propagation
echo "⏱️  Waiting 5s for message propagation..."
sleep 5


# Step 8: Get final message count
echo "📥 Consuming messages from topic..."
OUTPUT=$(~/kafka-learning-lab/test-scripts/consume-and-count.sh \
  "$TOPIC" "3")

# printf "%s\n" "$OUTPUT"

# Extract only the return value
FINAL=$(echo "$OUTPUT" | sed -n '/===RETURN_VALUE===/,$ p' | tail -n 1)


# Validate final count
if ! [[ "$FINAL" =~ ^[0-9]+$ ]]; then
  echo "❌ Error: Could not count received messages"
  FINAL=0
  RECEIVED=0
elif [ "$FINAL" -eq 0 ]; then
  RECEIVED=0
else
  # Calculate messages received in THIS test
  RECEIVED=$(expr $FINAL - $BASELINE)
  RECEIVED=${RECEIVED#-}
fi

# Step 9: Calculate results
SENT=$COUNT
# LOST=$((SENT - RECEIVED))
LOST=$(expr $SENT - $RECEIVED)
LOST=${LOST#-}

# Calculate loss percentage (with bc or fallback to integer)
if command -v bc > /dev/null 2>&1 && [ "$SENT" -gt 0 ]; then
  LOSS_PERCENT=$(echo "scale=1; ($LOST * 100) / $SENT" | bc)
else
  LOSS_PERCENT=$(( (LOST * 100) / SENT ))
fi

# Step 10: Display results
echo ""
echo "=========================================="
echo "  Test Results - acks=$ACKS"
echo "=========================================="
echo "📤 Messages Sent: $SENT"
echo "📥 Messages Received: $RECEIVED"
echo "❌ Messages Lost: $LOST"
echo "📊 Loss Percentage: ${LOSS_PERCENT}%"
echo ""

# Determine test result
if [ "$LOST" -eq 0 ]; then
  RESULT="✅ NO DATA LOSS"
  echo "$RESULT"
elif [ "$LOST" -lt 0 ]; then
  RESULT="⚠️  UNEXPECTED: Received more than sent (check timing)"
  echo "$RESULT"
else
  RESULT="❌ DATA LOSS DETECTED"
  echo "$RESULT"
fi
echo ""

# Step 11: Save results to file
# {
echo "===== Test Results ====="
echo "Baseline Messages: $BASELINE"
echo "Messages Sent: $SENT"
echo "Final Count: $FINAL"
echo "Messages Received (this test): $RECEIVED"
echo "Messages Lost: $LOST"
echo "Loss Percentage: ${LOSS_PERCENT}%"
echo ""
echo "$RESULT"
echo ""
# } >> "$RESULT_FILE"

# Step 12: Restart broker reminder
echo "⚠️  Reminder: Manually restart broker $BROKER_TO_KILL if needed"
echo "   Command: ./scripts/start-broker-${BROKER_TO_KILL}.sh"
echo ""

# Step 13: Summary
# echo "=========================================="
# echo "📄 Full results saved to:"
# echo "   $RESULT_FILE"
# echo "=========================================="
# echo ""

# Cleanup temp files
rm -f /tmp/producer-$$.log

# Exit with appropriate code
if [ "$LOST" -gt 0 ]; then
  exit 1  # Data loss detected
else
  exit 0  # No data loss
fi