#!/bin/bash
# =============================================================================
# Producer Script - Kafka robust producer with separate SUCCESS / WARN / FAILED
# =============================================================================

TOPIC=${1:-fault-test}
COUNT=${2:-20}
ACKS=${3:-all}
BOOTSTRAP=localhost:9092,localhost:9093,localhost:9094

# -----------------------------
# Display cluster status
# -----------------------------
~/kafka-learning-lab/scripts/monitor-cluster.sh $TOPIC "true"

# -----------------------------
# Display configuration
# -----------------------------
echo "🚀 Starting producer..."
echo "  Topic      : $TOPIC"
echo "  Count      : $COUNT"
echo "  Acks       : $ACKS"
echo "  Bootstrap  : $BOOTSTRAP"
echo ""

# -----------------------------
# Initialize counters
# -----------------------------
SUCCESS=0
FAILED=0
WARN=0

# -----------------------------
# Produce messages
# -----------------------------
for i in $(seq 1 "$COUNT"); do
  MSG="Message $i at $(date +%H:%M:%S)"

  # Run producer and capture output
  PRODUCER_OUTPUT=$(echo "$MSG" | ~/kafka-learning-lab/kafka/bin/kafka-console-producer.sh \
      --topic "$TOPIC" \
      --bootstrap-server "$BOOTSTRAP" \
      --producer-property acks="$ACKS" \
      --producer-property request.timeout.ms=5000 2>&1)

  # Check output for errors vs warnings
  if echo "$PRODUCER_OUTPUT" | grep -qE "NotEnoughReplicas|TimeoutException|UnknownTopicOrPartition|LeaderNotAvailable|ERROR|Exception"; then
    # True failure
    FAILED=$((FAILED + 1))
    echo "❌ FAILED ($FAILED/$COUNT): $MSG"
    echo "   └─ Kafka error:"
    echo "      $(echo "$PRODUCER_OUTPUT" | tail -n 3)"
    echo ""
  elif echo "$PRODUCER_OUTPUT" | grep -qE "WARN|Connection refused|Disconnected|could not be established"; then
    # Warning but message may still succeed
    WARN=$((WARN + 1))
    echo "⚠️ WARN ($WARN/$COUNT): $MSG"
    echo "   └─ Kafka warning:"
    echo "      $(echo "$PRODUCER_OUTPUT" | tail -n 3)"
    echo ""
  else
    SUCCESS=$((SUCCESS + 1))
    echo "✅ SUCCESS ($SUCCESS/$COUNT): $MSG"
  fi

  sleep 0.5
done

# -----------------------------
# Success rate calculation
# -----------------------------
if command -v bc > /dev/null 2>&1; then
  SUCCESS_RATE=$(echo "scale=1; ($SUCCESS * 100) / $COUNT" | bc)
else
  SUCCESS_RATE=$(( (SUCCESS * 100) / COUNT ))
fi

# -----------------------------
# Summary
# -----------------------------
echo ""
echo "===== Producer Summary ====="
echo "✅ SUCCESS   : $SUCCESS"
echo "⚠️ WARNINGS : $WARN"
echo "❌ FAILED    : $FAILED"
echo "📊 Success Rate: ${SUCCESS_RATE}%"
echo ""

# -----------------------------
# Exit code for caller scripts
# -----------------------------
exit 0
# if [ "$FAILED" -gt 0 ]; then
#   exit 1
# else
#   exit 0
# fi
