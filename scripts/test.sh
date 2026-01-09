#!/bin/bash
OUTPUT=$(~/kafka-learning-lab/test-scripts/consume-and-count.sh \
  "fault-test" "3")

printf "%s\n" "$OUTPUT"

# Extract only the return value
FINAL=$(echo "$OUTPUT" | sed -n '/===RETURN_VALUE===/,$ p' | tail -n 1)

echo "Captured return value: $FINAL"

# ~/kafka-learning-lab/test-scripts/consume-and-count.sh "fault-test" "3"