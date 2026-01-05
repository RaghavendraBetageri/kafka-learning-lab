# Kafka Fault Tolerance Testing - Complete Hands-On Guide
## Optimized for macOS M1

***

## 📚 Table of Contents

1. [Learning Objectives](#learning-objectives)
2. [Prerequisites & Environment Setup](#prerequisites--environment-setup)
3. [Core Concepts Deep Dive](#core-concepts-deep-dive)
4. [Lab 1: Leader Broker Failure & Recovery](#lab-1-leader-broker-failure--recovery)
5. [Lab 2: Understanding ISR Behavior](#lab-2-understanding-isr-behavior)
6. [Lab 3: Testing min.insync.replicas](#lab-3-testing-mininsync-replicas)
7. [Lab 4: Multiple Broker Failures](#lab-4-multiple-broker-failures)
8. [Lab 5: Producer Behavior During Failures](#lab-5-producer-behavior-during-failures)
9. [Lab 6: Consumer Behavior During Failures](#lab-6-consumer-behavior-during-failures)
10. [Lab 7: Network Partition Simulation](#lab-7-network-partition-simulation)
11. [Lab 8: Data Durability Testing](#lab-8-data-durability-testing)
12. [Lab 9: Recovery Time Measurement](#lab-9-recovery-time-measurement)
13. [Best Practices & Production Recommendations](#best-practices--production-recommendations)
14. [Troubleshooting Common Issues](#troubleshooting-common-issues)
15. [Quick Reference Commands](#quick-reference-commands)

***

## Learning Objectives

By the end of this guide, you will:

- ✅ Understand how Kafka handles broker failures gracefully
- ✅ Observe leader election in real-time
- ✅ Master ISR (In-Sync Replicas) mechanics and monitoring
- ✅ Configure `min.insync.replicas` for data durability
- ✅ Test producer/consumer resilience during outages
- ✅ Measure and optimize recovery times
- ✅ Make informed decisions about replication factors for production

**Platform:** macOS M1

***

## Prerequisites & Environment Setup

### macOS System Preparation

```bash
# 1. Check file descriptor limits (macOS default is too low)
ulimit -n
# Usually shows: 256 (too low for Kafka!)

# 2. Increase temporarily (for current session)
ulimit -n 10000

# 3. Make permanent (add to ~/.zshrc)
echo "ulimit -n 10000" >> ~/.zshrc
source ~/.zshrc

# 4. Verify Java is available
java -version
# Should show Java 11 or higher
```
### Start zookeeper and all 3 Brokers in different terminals
```bash
cd ~/kafka-learning-lab

./scripts/start-zookeeper.sh # Terminal 1
./scripts/start-broker-0.sh  # Terminal 2
./scripts/start-broker-1.sh  # Terminal 3
./scripts/start-broker-2.sh  # Terminal 4
```

### Verify Broker Status

```bash
cd ~/kafka-learning-lab

# Check all brokers are running (macOS command)
for i in {0..2}; do
  if pgrep -f "server-$i.properties" > /dev/null; then
    PID=$(pgrep -f "server-$i.properties")
    PORT=$((9092 + i))
    echo "✅ Broker $i - PID: $PID - Port: $PORT"
  else
    echo "❌ Broker $i - NOT RUNNING"
  fi
done
```



**Expected Output:**
```
✅ Broker 0 - PID: 12345 - Port: 9092
✅ Broker 1 - PID: 12346 - Port: 9093
✅ Broker 2 - PID: 12347 - Port: 9094
```



### Create Fault Testing Topic

```bash
# List all the topics
kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092

# Delete if exists (clean slate)
kafka/bin/kafka-topics.sh --delete \
  --topic fault-test \
  --bootstrap-server localhost:9092 2>/dev/null

sleep 3

# Create with RF=3 (maximum durability for 3-broker cluster)
kafka/bin/kafka-topics.sh --create \
  --topic fault-test \
  --bootstrap-server localhost:9092 \
  --partitions 3 \
  --replication-factor 3 \
  --config min.insync.replicas=2
```

**Why these settings?**
- `partitions=3`: One partition leader per broker (even distribution)
- `replication-factor=3`: Every partition has 3 copies (maximum safety)
- `min.insync.replicas=2`: Need 2 replicas to acknowledge writes (balance safety/availability)

**Verify Creation:**
```bash
kafka/bin/kafka-topics.sh --describe \
  --topic fault-test \
  --bootstrap-server localhost:9092
```

**Expected Output:**
```
Topic: fault-test   TopicId: xyz123   PartitionCount: 3   ReplicationFactor: 3   Configs: min.insync.replicas=2
    Topic: fault-test   Partition: 0    Leader: 1    Replicas: 1,2,0    Isr: 1,2,0
    Topic: fault-test   Partition: 1    Leader: 2    Replicas: 2,0,1    Isr: 2,0,1
    Topic: fault-test   Partition: 2    Leader: 0    Replicas: 0,1,2    Isr: 0,1,2
```

**Understanding This Output:**

```
Partition 0:
  Leader: Broker 1 (handles all reads/writes)
  Replicas: 1,2,0 (data exists on all 3 brokers)
  ISR: 1,2,0 (all 3 replicas are in-sync ✅)

Visual:
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Broker 0   │────▶│  Broker 1   │◀────│  Broker 2   │
│  (Follower) │     │  (LEADER)   │     │  (Follower) │
│  Replica    │     │  Partition 0│     │  Replica    │
└─────────────┘     └─────────────┘     └─────────────┘
```

### Setup Monitoring Helper Script

```bash
cat > ~/kafka-learning-lab/scripts/monitor-cluster.sh << 'EOF'
#!/bin/bash
# Real-time cluster monitoring (macOS compatible)

TOPIC=${1:-fault-test}
BOOTSTRAP_SERVER=${2:-localhost:9092}

echo "===== Monitoring Topic: $TOPIC ====="
echo "Running on: $(uname -s) $(uname -m)"
echo "Press Ctrl+C to stop"
echo ""

while true; do
  clear
  echo "=========================================="
  echo "  Kafka Cluster Health Monitor"
  echo "  Time: $(date '+%H:%M:%S')"
  echo "=========================================="
  echo ""
  
  # Topic description
  ~/kafka-learning-lab/kafka/bin/kafka-topics.sh --describe \
    --topic $TOPIC \
    --bootstrap-server $BOOTSTRAP_SERVER 2>/dev/null || echo "⚠️  Topic not found or broker unreachable"
  
  echo ""
  echo "=========================================="
  echo "Running Brokers:"
  
  for i in {0..2}; do
    if pgrep -f "server-$i.properties" > /dev/null; then
      PID=$(pgrep -f "server-$i.properties")
      PORT=$((9092 + i))
      echo "  ✅ Broker $i - PID: $PID - Port: $PORT"
    else
      echo "  ❌ Broker $i - NOT RUNNING"
    fi
  done
  
  echo ""
  echo "Disk Usage (Kafka Logs):"
  df -h /tmp/kafka-logs-* 2>/dev/null | tail -n +2 | awk '{print "  " $9 ": " $5 " used"}'
  
  echo ""
  echo "Next refresh in 2 seconds..."
  sleep 2
done
EOF

chmod +x ~/kafka-learning-lab/scripts/monitor-cluster.sh
```

**Test the monitor:**
```bash
# This will run in the foreground
./scripts/monitor-cluster.sh fault-test

# Press Ctrl+C to stop
```

***

## Core Concepts Deep Dive

Before breaking things, let's understand the theory!

### 1. Replication Architecture

**The Leader-Follower Model:**

```
Producer                          Consumers
    │                                 │
    │ Write Request                   │ Read Request
    ▼                                 ▼
┌─────────────────────────────────────────┐
│           Partition 0                   │
│  ┌──────────────┐                       │
│  │ Broker 1     │ ◀─── LEADER           │
│  │ (Leader)     │      Handles all I/O  │
│  └──────────────┘                       │
│         │                               │
│         │ Replication                   │
│         ├──────────────┬─────────────┐  │
│         ▼              ▼             ▼  │
│  ┌──────────┐   ┌──────────┐  ┌──────────┐
│  │Broker 0  │   │Broker 1  │  │Broker 2  │
│  │(Follower)│   │(Leader)  │  │(Follower)│
│  │ Replica  │   │          │  │ Replica  │
│  └──────────┘   └──────────┘  └──────────┘
└─────────────────────────────────────────┘
```

**Key Points:**
- **One Leader** per partition (handles all reads/writes)
- **N-1 Followers** replicate from leader (passive replication)
- **Producer writes** only to leader
- **Consumer reads** from leader (followers can serve reads in newer Kafka versions)

### 2. In-Sync Replicas (ISR)

**Definition:** ISR is the subset of replicas that are "caught up" with the leader.

**How a Replica Stays In-Sync:**

```
Follower Behavior:
1. Send fetch request to leader
2. Leader sends new messages
3. Follower writes to disk
4. Follower sends next fetch request
5. Repeat

Timing:
├─ Fetch Request ─┤ 10ms ├─ Fetch Request ─┤ 10ms ├─ Fetch Request ─┤
                   ▲                          ▲
                Leader sees: "Follower is alive and caught up!" ✅
```

**When a Replica Falls Out of ISR:**

Configuration: `replica.lag.time.max.ms` (default: 30 seconds)

```
Scenario 1: Network Issue
├─ Fetch ─┤ 10ms ├─ Fetch ─┤ 10ms ├─────────────── 35 seconds ────────────────┤
                                    ▲
                                 Network partition!
                                 Leader thinks: "Follower is dead" ❌
                                 Action: Remove from ISR

Scenario 2: Slow Disk
├─ Fetch ─┤ 10ms ├─ Fetch ─┤ 25ms ├─ Fetch ─┤ 40ms (disk bottleneck)
                                               ▲
                                            Too slow!
                                            Action: Remove from ISR
```

**ISR Health States:**

| ISR Count | Replication Factor | Health Status | Risk Level |
|-----------|-------------------|---------------|------------|
| 3 | 3 | ✅ Healthy | None - All replicas in sync |
| 2 | 3 | ⚠️ Degraded | Medium - 1 broker can fail |
| 1 | 3 | 🔴 Critical | High - No redundancy! |
| 0 | 3 | 💀 Offline | Catastrophic - Partition unavailable |

### 3. min.insync.replicas Configuration

**What It Does:**
Specifies minimum ISR count for a write to succeed.

**Configuration Combinations:**

```bash
# Scenario 1: Maximum Durability (Slow writes)
replication.factor=3
min.insync.replicas=3

Write flow:
Producer → Leader → Follower 1 → Follower 2
              ✓         ✓            ✓
         All 3 must ACK before success
         
Risk: If ANY broker fails, writes fail!
Use case: Financial transactions, audit logs

# Scenario 2: Balanced (Recommended) ✅
replication.factor=3
min.insync.replicas=2

Write flow:
Producer → Leader + 1 Follower must ACK
              ✓           ✓
         2/3 ACK = Success
         
Risk: Can tolerate 1 broker failure
Use case: Most production workloads

# Scenario 3: High Availability (Risk of data loss)
replication.factor=3
min.insync.replicas=1

Write flow:
Producer → Leader ACKs alone
              ✓
         1/3 ACK = Success
         
Risk: Leader failure before replication = data loss
Use case: Non-critical logs, metrics
```

**Invalid Combinations (Will Fail):**

```bash
# ❌ BAD: min.insync.replicas > replication.factor
replication.factor=2
min.insync.replicas=3
# Error: Cannot require 3 ACKs when only 2 replicas exist!

# ❌ BAD: min.insync.replicas = replication.factor (no fault tolerance)
replication.factor=3
min.insync.replicas=3
# Problem: ANY broker failure = writes blocked
```

**Best Practice Formula:**
```
min.insync.replicas = (replication.factor / 2) + 1

Examples:
RF=3 → min.insync.replicas=2  ✅
RF=5 → min.insync.replicas=3  ✅
RF=1 → min.insync.replicas=1  ✅ (no replication)
```

### 4. Leader Election Process

**Trigger Events:**
1. Leader broker crashes
2. Leader broker loses network connectivity
3. Manual leader rebalance (admin operation)
4. Controlled shutdown (graceful restart)

**Election Algorithm (Simplified):**

```
Step 1: Detect Leader Failure
  - ZooKeeper heartbeat timeout (or KRaft in Kafka 3.3+)
  - Controller receives notification

Step 2: Find Eligible Candidates
  - Check ISR list for partition
  - Candidates = All replicas currently in ISR

Step 3: Select New Leader
  - Pick first replica in ISR list (order matters!)
  - Prefer replicas that are "preferred leader" (original assignment)

Step 4: Update Metadata
  - Controller updates ZooKeeper/KRaft
  - Brokers fetch new metadata
  - Clients refresh metadata on next request

Step 5: Resume Operations
  - New leader starts accepting writes
  - Old followers now replicate from new leader
```

**Visual Timeline:**

```
T=0s:  Broker 1 (Leader) is healthy
       ISR: [1, 2, 0]
       
T=1s:  ⚡ Broker 1 crashes! (kill -9)
       Producers blocked (waiting for leader)
       
T=1.5s: Controller detects failure
       Starts election process
       
T=2s:  Broker 2 elected as new leader (first in ISR)
       ISR updated: [2, 0] (removed dead broker)
       
T=2.1s: Metadata propagated to all brokers
       
T=2.2s: Producers resume (connect to Broker 2)
       ✅ Total downtime: ~1-2 seconds
```

**Configuration Impact:**

| Parameter | Default | Impact on Election |
|-----------|---------|-------------------|
| `unclean.leader.election.enable` | false | If true, elect non-ISR replica (risk data loss) |
| `leader.imbalance.check.interval.seconds` | 300 | How often to rebalance leaders |
| `replica.lag.time.max.ms` | 30000 | How long before removing from ISR |

### 5. Producer Acknowledgment Modes

**`acks` Configuration:**

```bash
# acks=0: Fire and forget (no confirmation)
acks=0
Producer → [sends message] → continues immediately
          ↓
       Never knows if message arrived!
       
Performance: ⚡ Fastest
Durability:  💀 Worst (can lose messages)
Use case:    Metrics, logs (lossy okay)

# acks=1: Leader confirms (default)
acks=1
Producer → Leader writes to disk → ACK
          ↓
       Knows leader got it
       
Performance: 🚀 Fast
Durability:  ⚠️  Medium (if leader fails before replication)
Use case:    Most applications

# acks=all (or -1): All ISR confirms
acks=all, min.insync.replicas=2
Producer → Leader + 1 Follower write → ACK
          ↓
       Knows message replicated
       
Performance: 🐢 Slowest
Durability:  ✅ Best (no data loss if configured correctly)
Use case:    Financial, critical data
```

***

## Lab 1: Leader Broker Failure & Recovery

**Goal:** Experience leader election firsthand by killing the leader broker.

**Time:** 20 minutes

### Step 1: Baseline State

```bash
# Check current partition leaders
kafka/bin/kafka-topics.sh --describe \
  --topic fault-test \
  --bootstrap-server localhost:9092
```

**Sample Output:**
```
Topic: fault-test   Partition: 0    Leader: 1    Replicas: 1,2,0    Isr: 1,2,0
Topic: fault-test   Partition: 1    Leader: 2    Replicas: 2,0,1    Isr: 2,0,1
Topic: fault-test   Partition: 2    Leader: 0    Replicas: 0,1,2    Isr: 0,1,2
```

**Record This Information:**
```
Partition 0: Leader = Broker 1
Partition 1: Leader = Broker 2
Partition 2: Leader = Broker 0
```

### Step 2: Open Multiple Terminal Windows

**You'll need 4 terminal windows/tabs:**

**Terminal 1: Cluster Monitor**
```bash
cd ~/kafka-learning-lab
./scripts/monitor-cluster.sh fault-test
```

**Terminal 2: Continuous Producer**
```bash
cd ~/kafka-learning-lab

# Start continuous producer (1 message per second)
while true; do
  echo "Message at $(date +%H:%M:%S)" | \
  kafka/bin/kafka-console-producer.sh \
    --topic fault-test \
    --bootstrap-server localhost:9092 \
    --producer-property acks=all
  sleep 1
done
```

**Terminal 3: Continuous Consumer**
```bash
cd ~/kafka-learning-lab

kafka/bin/kafka-console-consumer.sh \
  --topic fault-test \
  --bootstrap-server localhost:9092 \
  --property print.timestamp=true
```

**Terminal 4: Commands (this is where you'll execute kill commands)**

### Step 3: Kill Leader Broker

**In Terminal 4:**

```bash
cd ~/kafka-learning-lab

# Find broker 1 process (leader of partition 0)
pgrep -f "server-1.properties"

# Sample output: 12346

# Kill it (simulate crash) - macOS command
pkill -9 -f "server-1.properties"

# Confirm it's dead
pgrep -f "server-1.properties"
# Should return nothing
```

### Step 4: Observe Recovery

**Watch Terminal 1 (Monitor):**

You should see ISR change within 1-2 seconds:

```
Before:
Topic: fault-test   Partition: 0    Leader: 1    Replicas: 1,2,0    Isr: 1,2,0

After (~2 seconds):
Topic: fault-test   Partition: 0    Leader: 2    Replicas: 1,2,0    Isr: 2,0
                                      ▲ Changed!                        ▲ Broker 1 removed!
```

**Watch Terminal 2 (Producer):**

You might see a brief pause (1-2 seconds), then resumes:

```
Message at 10:15:30
Message at 10:15:31
[WARN] Connection to broker 1 failed (org.apache.kafka.clients.NetworkClient)
[INFO] Cluster metadata updated, partition 0 leader is now broker 2
Message at 10:15:33  ← Brief gap (1-2 seconds)
Message at 10:15:34  ← Resumed!
```

**Watch Terminal 3 (Consumer):**

Should continue receiving messages (might have 1-2 second gap):

```
Message at 10:15:30
Message at 10:15:31
[gap 1-2 seconds]
Message at 10:15:33
Message at 10:15:34
```

### Step 5: Analyze What Happened

**Timeline Breakdown:**

```
10:15:31.000 - Broker 1 killed (pkill -9)
10:15:31.100 - Producer's next write attempt fails
10:15:31.200 - Controller detects broker 1 is dead (heartbeat timeout)
10:15:31.500 - Controller initiates leader election
10:15:31.700 - Broker 2 elected as new leader for partition 0
10:15:31.900 - Metadata propagated to all clients
10:15:32.000 - Producer discovers new leader (Broker 2)
10:15:32.100 - Writes resume successfully
```

**Total Downtime: ~1-2 seconds** ✅

**Check ISR Status in Terminal 4:**
```bash
kafka/bin/kafka-topics.sh --describe \
  --topic fault-test \
  --bootstrap-server localhost:9092 | grep "Partition: 0"
```

**Expected:**
```
Partition: 0    Leader: 2    Replicas: 1,2,0    Isr: 2,0
                                                      ▲
                                        Only 2/3 replicas in sync now!
```

### Step 6: Restart Dead Broker

**In Terminal 4:**

```bash
# Restart broker 1
./scripts/start-broker-1.sh

# Wait 10 seconds for it to catch up
sleep 10

# Check ISR again
kafka/bin/kafka-topics.sh --describe \
  --topic fault-test \
  --bootstrap-server localhost:9092 | grep "Partition: 0"
```

**Expected:**
```
Partition: 0    Leader: 2    Replicas: 1,2,0    Isr: 2,0,1
                                                      ▲
                                        Broker 1 rejoined ISR! ✅
```

**What Happened:**
1. Broker 1 restarted
2. Loaded partition logs from disk
3. Started replicating from new leader (Broker 2)
4. Caught up within 10 seconds
5. Controller added it back to ISR

**Note:** Broker 1 is now a FOLLOWER (not leader anymore). Leadership doesn't automatically return.

### Step 7: Verify No Data Loss

```bash
# Stop producer in Terminal 2 (Ctrl+C)

# Count messages in topic
kafka/bin/kafka-run-class.sh org.apache.kafka.tools.GetOffsetShell \
  --bootstrap-server localhost:9092 \
  --topic fault-test | \
  awk -F: '{sum += $3} END {print "Total messages:", sum}'
```

**Expected:** Message count matches what you produced (no loss!) ✅

### Step 8: Stop Continuous Consumer

```bash
# In Terminal 3, press Ctrl+C to stop consumer
```

### Lab 1 Takeaways

✅ **Leader election happens automatically** (1-2 seconds)  
✅ **Producers/consumers automatically reconnect**  
✅ **No data loss** with `acks=all` and `min.insync.replicas=2`  
✅ **Recovered broker rejoins as follower** (not leader)  
✅ **ISR shrinks during failure, expands after recovery**

***

## Lab 2: Understanding ISR Behavior

**Goal:** Deep dive into ISR mechanics by simulating slow replicas.

**Time:** 15 minutes

### Experiment 2.1: Replica Lag Simulation

We'll make a follower fall out of ISR by freezing it.

**Step 1: Check Current ISR**

```bash
kafka/bin/kafka-topics.sh --describe \
  --topic fault-test \
  --bootstrap-server localhost:9092
```

**All should show ISR with 3 replicas:** `Isr: 0,1,2` or similar.

**Step 2: Pause a Follower Broker**

```bash
# Find broker 0 PID
pgrep -f "server-0.properties"

# Pause the process (simulate extreme slowness) - macOS command
pkill -STOP -f "server-0.properties"

# Verify it's paused (should still show in process list)
ps aux | grep "server-0.properties" | grep -v grep
```

**What `pkill -STOP` does:**
- Pauses the process (doesn't kill it)
- Process stops processing any requests
- Simulates a "frozen" broker

**Step 3: Start a Monitoring Loop**

**Terminal 2:**
```bash
# Watch ISR changes every 2 seconds
while true; do
  clear
  echo "=== ISR Status at $(date +%H:%M:%S) ==="
  kafka/bin/kafka-topics.sh --describe \
    --topic fault-test \
    --bootstrap-server localhost:9092
  sleep 2
done
```

**Step 4: Produce Messages**

**Terminal 3:**
```bash
# Produce 50 messages quickly
for i in {1..50}; do
  echo "Message $i - ISR test"
done | kafka/bin/kafka-console-producer.sh \
  --topic fault-test \
  --bootstrap-server localhost:9092
```

**Step 5: Observe ISR Change**

**Watch Terminal 2:**

**Timeline:**

```
T=0s:  Isr: 0,1,2  ← All healthy
T=5s:  Isr: 0,1,2  ← Broker 0 paused, but within threshold
T=10s: Isr: 0,1,2  ← Still within threshold
T=15s: Isr: 0,1,2  ← Still hanging in there...
T=30s: Isr: 1,2    ← Broker 0 removed! (replica.lag.time.max.ms hit)
                      ▲
                   Broker 0 missing!
```

**The 30-second threshold is `replica.lag.time.max.ms` (default: 30000ms)**

**Step 6: Resume Broker**

**Terminal 4:**
```bash
# Resume the paused process - macOS command
pkill -CONT -f "server-0.properties"

# Verify it's running again
pgrep -f "server-0.properties"
```

**Step 7: Watch ISR Rejoin**

**Continue watching Terminal 2:**

```
T=35s: Isr: 1,2      ← Broker 0 still out
T=40s: Isr: 1,2      ← Catching up (reading from leader)...
T=45s: Isr: 0,1,2    ← Rejoined! ✅
```

**Stop the monitoring loop (Ctrl+C in Terminal 2)**

### Experiment 2.2: Under-Replicated Partitions

**Check Cluster-Wide ISR Health:**

```bash
# Show all under-replicated partitions
kafka/bin/kafka-topics.sh --describe \
  --under-replicated-partitions \
  --bootstrap-server localhost:9092
```

**If you run this during the pause, you'll see:**
```
Topic: fault-test   Partition: 2    Leader: 0    Replicas: 0,1,2    Isr: 1,2
                                                                      ▲
                                                          Only 2/3 in sync!
```

**After broker resumes, run again:**
```bash
kafka/bin/kafka-topics.sh --describe \
  --under-replicated-partitions \
  --bootstrap-server localhost:9092
```

**Should show nothing (empty output) = All healthy!** ✅

### Lab 2 Takeaways

✅ **Replicas removed from ISR after** `replica.lag.time.max.ms` (default 30s)  
✅ **Replicas automatically rejoin ISR** when caught up  
✅ **Under-replicated partitions** = health warning (monitor in production!)  
✅ **Producers still work** as long as `min.insync.replicas` met  
✅ **`pkill -STOP` is great for testing** without killing the process

***

## Lab 3: Testing min.insync.replicas

**Goal:** See what happens when ISR falls below `min.insync.replicas`.

**Time:** 20 minutes

### Setup

```bash
# Create topic with strict durability
kafka/bin/kafka-topics.sh --create \
  --topic strict-durability \
  --bootstrap-server localhost:9092 \
  --partitions 1 \
  --replication-factor 3 \
  --config min.insync.replicas=3
```

**Configuration:**
- RF=3 (3 copies)
- min.insync.replicas=3 (ALL must ACK)
- Partitions=1 (easier to track)

**Verify:**
```bash
kafka/bin/kafka-topics.sh --describe \
  --topic strict-durability \
  --bootstrap-server localhost:9092
```

### Scenario 1: All Replicas Healthy (Should Work)

```bash
# Check ISR
kafka/bin/kafka-topics.sh --describe \
  --topic strict-durability \
  --bootstrap-server localhost:9092

# Should show: Isr: 0,1,2 (all 3) or similar order
```

**Produce a test message:**
```bash
echo "Test message 1 - All replicas healthy" | \
kafka/bin/kafka-console-producer.sh \
  --topic strict-durability \
  --bootstrap-server localhost:9092 \
  --producer-property acks=all
```

**Expected:** ✅ **Success!** Message accepted.

### Scenario 2: Kill One Broker (Should Fail!)

```bash
# Identify which broker is NOT the leader
kafka/bin/kafka-topics.sh --describe \
  --topic strict-durability \
  --bootstrap-server localhost:9092 | grep "Partition: 0"

# Example output:
# Partition: 0  Leader: 1  Replicas: 1,0,2  Isr: 1,0,2

# Kill a follower (e.g., broker 2)
pkill -9 -f "server-2.properties"

# Wait for ISR to update (30+ seconds)
echo "Waiting 35 seconds for ISR to shrink..."
sleep 35

# Check ISR now
kafka/bin/kafka-topics.sh --describe \
  --topic strict-durability \
  --bootstrap-server localhost:9092 | grep "Partition: 0"
```

**Expected:**
```
Partition: 0    Leader: 1    Replicas: 1,0,2    Isr: 1,0
                                                      ▲
                                          Only 2/3 now! ⚠️
```

**Try to produce:**
```bash
echo "Test message 2 - One broker down" | \
kafka/bin/kafka-console-producer.sh \
  --topic strict-durability \
  --bootstrap-server localhost:9092 \
  --producer-property acks=all
```

**Expected:** ❌ **ERROR!**

**Error You'll See:**
```
org.apache.kafka.common.errors.NotEnoughReplicasException: 
Messages are rejected since there are fewer in-sync replicas than required.
```

**Why This Happened:**
```
Required: min.insync.replicas=3
Available: ISR=2 (Brokers 1, 0)
Result: 2 < 3 → REJECT writes! ❌
```

**This is GOOD!** Kafka protects data integrity by refusing writes.

### Scenario 3: Relax Configuration (Works Again)

```bash
# Lower min.insync.replicas to 2
kafka/bin/kafka-configs.sh --alter \
  --entity-type topics \
  --entity-name strict-durability \
  --add-config min.insync.replicas=2 \
  --bootstrap-server localhost:9092

# Verify the change
kafka/bin/kafka-configs.sh --describe \
  --entity-type topics \
  --entity-name strict-durability \
  --bootstrap-server localhost:9092
```

**Try producing again:**
```bash
echo "Test message 3 - Relaxed config" | \
kafka/bin/kafka-console-producer.sh \
  --topic strict-durability \
  --bootstrap-server localhost:9092 \
  --producer-property acks=all
```

**Expected:** ✅ **Works now!** (2 replicas meet requirement)

### Scenario 4: Restart Broker (Back to Full Health)

```bash
# Restart broker 2
./scripts/start-broker-2.sh

# Wait for catch-up
echo "Waiting 15 seconds for broker to catch up..."
sleep 15

# Verify ISR
kafka/bin/kafka-topics.sh --describe \
  --topic strict-durability \
  --bootstrap-server localhost:9092
```

**Expected:**
```
Partition: 0    Leader: 1    Replicas: 1,0,2    Isr: 1,0,2
                                                      ▲
                                          All 3 back! ✅
```

### Lab 3 Takeaways

✅ **`min.insync.replicas` enforces durability** guarantees  
✅ **Writes fail if ISR < min.insync.replicas** (protects data)  
✅ **Always set: `replication.factor > min.insync.replicas`** (allows failures)  
✅ **Trade-off:** Higher min.insync.replicas = safer but less available  
✅ **Can adjust config dynamically** without recreating topic

**Production Recommendation:**
```
replication.factor=3
min.insync.replicas=2  ← Sweet spot!
```

***

## Lab 4: Multiple Broker Failures

**Goal:** Test the limits - what happens when 2/3 brokers fail?

**Time:** 15 minutes

### Setup: Ensure All Brokers Running

```bash
# Verify all 3 brokers are up
for i in {0..2}; do
  if pgreg -f "server-$i.properties" > /dev/null; then
    echo "✅ Broker $i running"
  else
    echo "❌ Broker $i down - starting..."
    ./scripts/start-broker-$i.sh
    sleep 5
  fi
done
```

### Scenario: Quorum Loss

```bash
# Check baseline
kafka/bin/kafka-topics.sh --describe \
  --topic fault-test \
  --bootstrap-server localhost:9092
```

**Kill 2 brokers simultaneously:**
```bash
# Kill brokers 1 and 2 at the same time
pkill -9 -f "server-1.properties"
pkill -9 -f "server-2.properties"

# Confirm they're dead
for i in {1..2}; do
  if pgrep -f "server-$i.properties" > /dev/null; then
    echo "❌ Broker $i still running"
  else
    echo "✅ Broker $i killed"
  fi
done

# Wait for ISR update
echo "Waiting 35 seconds for ISR to stabilize..."
sleep 35
```

### Check Partition Status

```bash
# Use remaining broker (broker 0 on port 9092)
kafka/bin/kafka-topics.sh --describe \
  --topic fault-test \
  --bootstrap-server localhost:9092
```

**Expected Output:**
```
Partition: 0    Leader: 0    Replicas: 1,2,0    Isr: 0
Partition: 1    Leader: -1   Replicas: 2,0,1    Isr: 
Partition: 2    Leader: 0    Replicas: 0,2,1    Isr: 0
                ▲ No leader!
```

**Analysis:**
- **Partition 0:** Still has leader (Broker 0), but ISR=1
- **Partition 1:** OFFLINE (leader was on Broker 2, no ISR replicas available) ❌
- **Partition 2:** Still has leader (Broker 0), but ISR=1

### Try Producing

```bash
# Try to produce
echo "Test during 2/3 broker failure" | \
kafka/bin/kafka-console-producer.sh \
  --topic fault-test \
  --bootstrap-server localhost:9092 \
  --producer-property acks=all
```

**Result:** ❌ **Fails!**

**Why:**
```
Partitions 0 & 2: ISR=1, need min.insync.replicas=2 ❌
Partition 1: No leader at all ❌

Conclusion: Topic is UNAVAILABLE for writes!
```

### Try with acks=1 (Relaxed)

```bash
echo "Test with acks=1" | \
kafka/bin/kafka-console-producer.sh \
  --topic fault-test \
  --bootstrap-server localhost:9092 \
  --producer-property acks=1
```

**Result:** ⚠️ **Might work for partitions 0 & 2** (still fails for partition 1)

### Recovery

```bash
# Restart both brokers
./scripts/start-broker-1.sh
./scripts/start-broker-2.sh

# Wait for full recovery
echo "Waiting 30 seconds for full recovery..."
sleep 30

# Verify all healthy
kafka/bin/kafka-topics.sh --describe \
  --topic fault-test \
  --bootstrap-server localhost:9092
```

**Expected:** All partitions back to `Isr: 0,1,2` ✅

### Lab 4 Takeaways

✅ **Kafka tolerates** `(RF - min.insync.replicas)` **broker failures** while accepting writes  
✅ **With RF=3, min.insync.replicas=2:** Can lose 1 broker safely  
✅ **Losing 2+ brokers:** Topic becomes unavailable for writes  
✅ **Critical:** Need > 50% of replicas online for availability  
✅ **Some partitions may survive** depending on replica distribution

***

## Lab 5: Producer Behavior During Failures

**Goal:** Test how different `acks` configurations behave during failures.

**Time:** 20 minutes

### Setup Test Scripts

```bash
# Create test scripts directory
mkdir -p ~/kafka-learning-lab/test-scripts

# Producer with acks=0
cat > ~/kafka-learning-lab/test-scripts/producer-acks-0.sh << 'EOF'
#!/bin/bash
cd ~/kafka-learning-lab
for i in {1..20}; do
  echo "acks=0 message $i" | kafka/bin/kafka-console-producer.sh \
    --topic fault-test \
    --bootstrap-server localhost:9092 \
    --producer-property acks=0 2>/dev/null
  sleep 0.5
done
echo "✅ Producer acks=0 finished"
EOF

# Producer with acks=1
cat > ~/kafka-learning-lab/test-scripts/producer-acks-1.sh << 'EOF'
#!/bin/bash
cd ~/kafka-learning-lab
for i in {1..20}; do
  echo "acks=1 message $i" | kafka/bin/kafka-console-producer.sh \
    --topic fault-test \
    --bootstrap-server localhost:9092 \
    --producer-property acks=1 2>/dev/null
  sleep 0.5
done
echo "✅ Producer acks=1 finished"
EOF

# Producer with acks=all
cat > ~/kafka-learning-lab/test-scripts/producer-acks-all.sh << 'EOF'
#!/bin/bash
cd ~/kafka-learning-lab
for i in {1..20}; do
  echo "acks=all message $i" | kafka/bin/kafka-console-producer.sh \
    --topic fault-test \
    --bootstrap-server localhost:9092 \
    --producer-property acks=all 2>/dev/null
  sleep 0.5
done
echo "✅ Producer acks=all finished"
EOF

chmod +x ~/kafka-learning-lab/test-scripts/producer-acks-*.sh
```

### Test 1: acks=0 During Leader Failure

```bash
# Start consumer in background to count messages
kafka/bin/kafka-console-consumer.sh \
  --topic fault-test \
  --from-beginning \
  --bootstrap-server localhost:9092 \
  --timeout-ms 3000 2>/dev/null | grep "acks=0" > /tmp/acks-0-messages.txt &

# Start producer
~/kafka-learning-lab/test-scripts/producer-acks-0.sh &
PRODUCER_PID=$!

# Wait 5 seconds, then kill a leader
sleep 5
pkill -9 -f "server-1.properties"
echo "⚡ Killed broker 1 during acks=0 test"

# Wait for producer to finish
wait $PRODUCER_PID

# Wait a bit for messages to be consumed
sleep 3

# Count messages received
RECEIVED=$(wc -l < /tmp/acks-0-messages.txt)
echo ""
echo "===== acks=0 Results ====="
echo "Messages sent: 20"
echo "Messages received: $RECEIVED"
echo "Data loss: $((20 - RECEIVED)) messages"

# Restart broker
./scripts/start-broker-1.sh
sleep 10
```

**Expected Result:** **Fewer than 20 messages!** (Data loss occurred) ❌

**Why:** Producer didn't wait for confirmation, sent to dead/dying leader.

### Test 2: acks=1 During Leader Failure

```bash
# Clear previous messages
> /tmp/acks-1-messages.txt

# Ensure all brokers running
for i in {0..2}; do
  if ! pgrep -f "server-$i.properties" > /dev/null; then
    ./scripts/start-broker-$i.sh
    sleep 5
  fi
done

# Start consumer
kafka/bin/kafka-console-consumer.sh \
  --topic fault-test \
  --from-beginning \
  --bootstrap-server localhost:9092 \
  --timeout-ms 3000 2>/dev/null | grep "acks=1" > /tmp/acks-1-messages.txt &

# Start producer
~/kafka-learning-lab/test-scripts/producer-acks-1.sh &
PRODUCER_PID=$!

# Wait 5 seconds, kill leader
sleep 5
pkill -9 -f "server-1.properties"
echo "⚡ Killed broker 1 during acks=1 test"

# Wait for producer
wait $PRODUCER_PID

# Wait for messages
sleep 3

# Count messages
RECEIVED=$(wc -l < /tmp/acks-1-messages.txt)
echo ""
echo "===== acks=1 Results ====="
echo "Messages sent: 20"
echo "Messages received: $RECEIVED"
echo "Data loss: $((20 - RECEIVED)) messages"

# Restart broker
./scripts/start-broker-1.sh
sleep 10
```

**Expected Result:** **Might lose 1-2 messages** during leader transition. ⚠️

**Why:** Leader ACKed before fully replicating to followers.

### Test 3: acks=all During Leader Failure

```bash
# Clear previous messages
> /tmp/acks-all-messages.txt

# Ensure all brokers running
for i in {0..2}; do
  if ! pgrep -f "server-$i.properties" > /dev/null; then
    ./scripts/start-broker-$i.sh
    sleep 5
  fi
done

# Start consumer
kafka/bin/kafka-console-consumer.sh \
  --topic fault-test \
  --from-beginning \
  --bootstrap-server localhost:9092 \
  --timeout-ms 3000 2>/dev/null | grep "acks=all" > /tmp/acks-all-messages.txt &

# Start producer
~/kafka-learning-lab/test-scripts/producer-acks-all.sh &
PRODUCER_PID=$!

# Wait 5 seconds, kill leader
sleep 5
pkill -9 -f "server-1.properties"
echo "⚡ Killed broker 1 during acks=all test"

# Wait for producer
wait $PRODUCER_PID

# Wait for messages
sleep 3

# Count messages
RECEIVED=$(wc -l < /tmp/acks-all-messages.txt)
echo ""
echo "===== acks=all Results ====="
echo "Messages sent: 20"
echo "Messages received: $RECEIVED"
echo "Data loss: $((20 - RECEIVED)) messages"

# Restart broker
./scripts/start-broker-1.sh
sleep 10
```

**Expected Result:** **All 20 messages!** No data loss. ✅

**Why:** Producer waited for replication to ISR before considering message sent.

### Comparison Table

Create a summary:

```bash
cat > ~/kafka-learning-lab/acks-comparison.txt << EOF
===== Producer acks Comparison During Leader Failure =====

Configuration    Sent    Received    Loss    Latency
---------------------------------------------------------
acks=0           20      ~15         ~25%    ⚡ Fastest
acks=1           20      ~19         ~5%     🚀 Fast
acks=all         20      20          0%      🐢 Slower

Conclusion:
- acks=0: Fast but UNSAFE (can lose messages)
- acks=1: Balanced but RISKY (can lose unsynced data)
- acks=all: SAFEST (no loss with proper min.insync.replicas)

Production Recommendation: Use acks=all for critical data
EOF

cat ~/kafka-learning-lab/acks-comparison.txt
```

### Lab 5 Takeaways

✅ **acks=0:** Fast but unsafe (can lose messages)  
✅ **acks=1:** Balanced but risk losing unsynced data  
✅ **acks=all:** Safest (no loss if min.insync.replicas configured)  
✅ **Production:** Use `acks=all` for critical data  
✅ **Trade-off:** Safety vs. latency

***

## Lab 6: Consumer Behavior During Failures

**Goal:** Understand how consumers handle broker failures.

**Time:** 15 minutes

### Setup Consumer Group

```bash
# Create fresh topic for this test
kafka/bin/kafka-topics.sh --delete --topic consumer-test --bootstrap-server localhost:9092 2>/dev/null
sleep 3

kafka/bin/kafka-topics.sh --create \
  --topic consumer-test \
  --bootstrap-server localhost:9092 \
  --partitions 3 \
  --replication-factor 3 \
  --config min.insync.replicas=2
```

### Start 3 Consumers in Same Group

**Terminal 1:**
```bash
kafka/bin/kafka-console-consumer.sh \
  --topic consumer-test \
  --bootstrap-server localhost:9092 \
  --group test-consumer-group \
  --property print.partition=true
```

**Terminal 2:**
```bash
kafka/bin/kafka-console-consumer.sh \
  --topic consumer-test \
  --bootstrap-server localhost:9092 \
  --group test-consumer-group \
  --property print.partition=true
```

**Terminal 3:**
```bash
kafka/bin/kafka-console-consumer.sh \
  --topic consumer-test \
  --bootstrap-server localhost:9092 \
  --group test-consumer-group \
  --property print.partition=true
```

### Check Partition Assignment

**Terminal 4:**
```bash
kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group test-consumer-group \
  --describe
```

**Sample Output:**
```
TOPIC          PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG  CONSUMER-ID     HOST
consumer-test  0          0               0               0    consumer-1-...  /127.0.0.1
consumer-test  1          0               0               0    consumer-2-...  /127.0.0.1
consumer-test  2          0               0               0    consumer-3-...  /127.0.0.1
```

Each consumer owns 1 partition. ✅

### Produce Test Messages

**Terminal 5:**
```bash
# Produce messages
for i in {1..30}; do
  echo "Message $i from terminal"
done | kafka/bin/kafka-console-producer.sh \
  --topic consumer-test \
  --bootstrap-server localhost:9092
```

**Watch all 3 consumer terminals** - each should receive ~10 messages.

### Identify Leader of Partition 0

```bash
kafka/bin/kafka-topics.sh --describe \
  --topic consumer-test \
  --bootstrap-server localhost:9092 | grep "Partition: 0"

# Example output:
# Partition: 0  Leader: 1  ...
```

### Kill Leader Broker

```bash
# Kill the leader (e.g., broker 1)
pkill -9 -f "server-1.properties"
```

### Observe Consumer Behavior

**What you'll see:**

1. **Consumer reading partition 0:** Brief pause (1-2 seconds), then resumes
2. **Other consumers:** Continue normally (unaffected)
3. **No rebalancing** triggered (partitions stay assigned)

**Verify no rebalancing:**
```bash
kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group test-consumer-group \
  --describe
```

**Expected:** Same assignment, consumers still active.

### Produce More Messages

```bash
# Restart broker first
./scripts/start-broker-1.sh
sleep 10

# Produce more messages
for i in {31..60}; do
  echo "Message $i after recovery"
done | kafka/bin/kafka-console-producer.sh \
  --topic consumer-test \
  --bootstrap-server localhost:9092
```

**All consumers continue receiving messages.** ✅

### Stop Consumers

```bash
# In each consumer terminal (Terminals 1, 2, 3), press Ctrl+C
```

### Lab 6 Takeaways

✅ **Consumers automatically reconnect** to new leader  
✅ **Broker failure does NOT trigger rebalancing** (partitions stay assigned)  
✅ **Only affected partition consumers pause briefly** (1-2 seconds)  
✅ **Offset commits preserved** (no reprocessing)  
✅ **Consumer groups are resilient** to broker failures

***

## Lab 7: Network Partition Simulation

**Goal:** Simulate network split (broker isolated but alive).

**Time:** 15 minutes

### Using Process Pause (Simpler on macOS)

On macOS, firewall rules (`iptables`) don't exist. We'll use process pausing to simulate network isolation.

**Step 1: Verify Baseline**

```bash
kafka/bin/kafka-topics.sh --describe \
  --topic fault-test \
  --bootstrap-server localhost:9092
```

**All ISR should show 3 replicas:** `Isr: 0,1,2`

**Step 2: "Isolate" Broker 2**

```bash
# Pause broker 2 (simulates network partition)
pkill -STOP -f "server-2.properties"

echo "Broker 2 paused (simulating network partition)"
echo "Waiting 35 seconds for cluster to react..."
sleep 35
```

**What this simulates:**
- Broker 2 is alive (process exists)
- But cannot communicate (frozen)
- Similar to network partition

**Step 3: Observe Cluster Behavior**

```bash
kafka/bin/kafka-topics.sh --describe \
  --topic fault-test \
  --bootstrap-server localhost:9092
```

**Expected:**
```
Partition: 0    Leader: 1    Replicas: 1,2,0    Isr: 1,0     ← Broker 2 removed
Partition: 1    Leader: 0    Replicas: 2,0,1    Isr: 0,1     ← Broker 2 removed  
Partition: 2    Leader: 1    Replicas: 0,1,2    Isr: 0,1     ← Broker 2 removed
```

**For partitions where Broker 2 was leader:**
- New leader elected automatically
- Broker 2 removed from all ISRs
- No "split-brain" (Kafka prevents dual leaders) ✅

**Step 4: Produce Messages (Should Work)**

```bash
echo "Test during network partition" | \
kafka/bin/kafka-console-producer.sh \
  --topic fault-test \
  --bootstrap-server localhost:9092 \
  --producer-property acks=all
```

**Expected:** ✅ **Works!** (ISR still has 2 replicas, meets min.insync.replicas=2)

**Step 5: Restore "Network"**

```bash
# Resume broker 2
pkill -CONT -f "server-2.properties"

echo "Broker 2 resumed"
echo "Waiting 15 seconds for rejoin..."
sleep 15
```

**Step 6: Verify Recovery**

```bash
kafka/bin/kafka-topics.sh --describe \
  --topic fault-test \
  --bootstrap-server localhost:9092
```

**Expected:**
```
Partition: 0    Leader: 1    Replicas: 1,2,0    Isr: 1,0,2   ← Broker 2 back!
Partition: 1    Leader: 0    Replicas: 2,0,1    Isr: 0,1,2   ← Broker 2 back!
Partition: 2    Leader: 1    Replicas: 0,1,2    Isr: 0,1,2   ← Broker 2 back!
```

All partitions back to full ISR! ✅

### Lab 7 Takeaways

✅ **Kafka handles network partitions gracefully**  
✅ **Prevents split-brain** (only one leader per partition)  
✅ **Isolated broker removed from ISR** automatically  
✅ **Automatic rejoin when connectivity restored**  
✅ **`pkill -STOP` is excellent for testing** on macOS

***

## Lab 8: Data Durability Testing

**Goal:** Prove that Kafka doesn't lose data with correct configuration.

**Time:** 15 minutes

### Setup Durable Topic

```bash
# Create durable topic
kafka/bin/kafka-topics.sh --create \
  --topic durability-test \
  --bootstrap-server localhost:9092 \
  --partitions 1 \
  --replication-factor 3 \
  --config min.insync.replicas=2 \
  --config unclean.leader.election.enable=false
```

**Configuration:**
- `min.insync.replicas=2`: Need 2 ACKs
- `unclean.leader.election.enable=false`: Never elect out-of-sync replica as leader

### Produce Test Data with Sequence Numbers

```bash
# Produce 100 messages with sequence numbers
for i in {1..100}; do
  echo "Message-$i-Timestamp-$(date +%s)"
done | kafka/bin/kafka-console-producer.sh \
  --topic durability-test \
  --bootstrap-server localhost:9092 \
  --producer-property acks=all
```

### Chaos Testing Script

```bash
cat > ~/kafka-learning-lab/test-scripts/chaos-test.sh << 'EOF'
#!/bin/bash
echo "===== Starting Chaos Test ====="
echo "Will randomly kill and restart brokers for 2 minutes"
echo ""

END_TIME=$(($(date +%s) + 120))  # Run for 2 minutes

while [ $(date +%s) -lt $END_TIME ]; do
  # Random broker (0, 1, or 2) - macOS uses jot instead of shuf
  BROKER=$(jot -r 1 0 2)
  
  echo "[$(date +%H:%M:%S)] ⚡ Killing broker $BROKER"
  pkill -9 -f "server-$BROKER.properties"
  
  sleep 10
  
  echo "[$(date +%H:%M:%S)] ✅ Restarting broker $BROKER"
  ~/kafka-learning-lab/scripts/start-broker-$BROKER.sh
  
  sleep 20
done

echo ""
echo "===== Chaos Test Complete ====="
EOF

chmod +x ~/kafka-learning-lab/test-scripts/chaos-test.sh
```

### Run Chaos Test with Continuous Production

**Terminal 1: Chaos Test**
```bash
~/kafka-learning-lab/test-scripts/chaos-test.sh
```

**Terminal 2: Continuous Producer (simultaneously)**
```bash
for i in {101..200}; do
  echo "Message-$i-Timestamp-$(date +%s)" | \
  kafka/bin/kafka-console-producer.sh \
    --topic durability-test \
    --bootstrap-server localhost:9092 \
    --producer-property acks=all 2>/dev/null
  sleep 0.5
done

echo "✅ Producer finished"
```

**Let both run for 2 minutes.**

### Verify Data Integrity

```bash
# Wait for chaos test to complete
sleep 10

# Ensure all brokers are up
for i in {0..2}; do
  if ! pgrep -f "server-$i.properties" > /dev/null; then
    ./scripts/start-broker-$i.sh
    sleep 5
  fi
done

# Consume all messages
kafka/bin/kafka-console-consumer.sh \
  --topic durability-test \
  --from-beginning \
  --bootstrap-server localhost:9092 \
  --timeout-ms 10000 2>/dev/null > /tmp/consumed-messages.txt

# Count total messages
TOTAL=$(wc -l < /tmp/consumed-messages.txt)
echo ""
echo "===== Data Integrity Check ====="
echo "Total messages received: $TOTAL"
echo "Expected: 200 (100 initial + 100 during chaos)"

# Check for duplicates
UNIQUE=$(sort /tmp/consumed-messages.txt | uniq | wc -l)
echo "Unique messages: $UNIQUE"

if [ "$TOTAL" -eq "$UNIQUE" ]; then
  echo "✅ No duplicates found"
else
  echo "⚠️  Found $((TOTAL - UNIQUE)) duplicate(s)"
fi

# Check sequence completeness
grep -oP 'Message-\K\d+' /tmp/consumed-messages.txt | sort -n > /tmp/sequences.txt
EXPECTED_SEQ=$(seq 1 200)
MISSING=$(comm -13 <(sort /tmp/sequences.txt) <(echo "$EXPECTED_SEQ") | wc -l)

if [ "$MISSING" -eq 0 ]; then
  echo "✅ All sequence numbers present (1-200)"
else
  echo "❌ Missing $MISSING sequence number(s)"
  echo "Missing sequences:"
  comm -13 <(sort /tmp/sequences.txt) <(echo "$EXPECTED_SEQ")
fi
```

**Expected Results:**
- **Total messages:** 200 ✅
- **No duplicates** ✅
- **No missing sequences** ✅

### Lab 8 Takeaways

✅ **With `acks=all` + `min.insync.replicas=2`:** Zero data loss  
✅ **Chaos testing validates configuration** in practice  
✅ **Kafka guarantees durability** when configured correctly  
✅ **Even with random broker failures:** Messages are safe  
✅ **No duplicates, no gaps** in properly configured setup

***

## Lab 9: Recovery Time Measurement

**Goal:** Measure how fast Kafka recovers from failures.

**Time:** 20 minutes (bonus lab)

### Create Measurement Script

```bash
cat > ~/kafka-learning-lab/scripts/measure-recovery.sh << 'EOF'
#!/bin/bash

TOPIC=${1:-fault-test}
BOOTSTRAP=${2:-localhost:9092}

echo "===== Recovery Time Measurement (macOS) ====="
echo "Topic: $TOPIC"
echo ""

# Start timestamp (macOS uses seconds by default)
START=$(date +%s)

# Kill random broker (macOS uses jot instead of shuf)
BROKER=$(jot -r 1 0 2)
echo "[T+0.0s] ⚡ Killing broker $BROKER"
pkill -9 -f "server-$BROKER.properties"

# Wait for leader election
echo "Waiting for leader election..."
ELECTION_DONE=0
while [ $ELECTION_DONE -eq 0 ]; do
  LEADERS=$(~/kafka-learning-lab/kafka/bin/kafka-topics.sh --describe \
    --topic $TOPIC \
    --bootstrap-server $BOOTSTRAP 2>/dev/null | grep -c "Leader: [0-9]")
  
  if [ "$LEADERS" -ge 2 ]; then  # At least 2 partitions have leaders
    END=$(date +%s)
    ELAPSED=$((END - START))
    echo "[T+${ELAPSED}.0s] ✅ Leader election completed"
    ELECTION_DONE=1
  fi
  sleep 0.5
done

# Measure time to first successful write
echo "Testing producer availability..."
WRITE_START=$(date +%s)

echo "test message" | ~/kafka-learning-lab/kafka/bin/kafka-console-producer.sh \
  --topic $TOPIC \
  --bootstrap-server $BOOTSTRAP \
  --producer-property acks=all 2>/dev/null

WRITE_END=$(date +%s)
WRITE_TIME=$((WRITE_END - WRITE_START))

echo "[T+${WRITE_TIME}.0s] ✅ First write succeeded"

echo ""
echo "===== Results ====="
echo "Leader Election Time: ${ELAPSED}s"
echo "Total Recovery Time:  ${WRITE_TIME}s"
echo ""

# Restart the killed broker for next test
echo "Restarting broker $BROKER for next test..."
~/kafka-learning-lab/scripts/start-broker-$BROKER.sh > /dev/null 2>&1
sleep 10
EOF

chmod +x ~/kafka-learning-lab/scripts/measure-recovery.sh
```

### Run Multiple Recovery Tests

```bash
# Ensure all brokers are running
for i in {0..2}; do
  if ! pgrep -f "server-$i.properties" > /dev/null; then
    ./scripts/start-broker-$i.sh
    sleep 5
  fi
done

# Run 10 recovery tests
echo "Running 10 recovery time tests..."
echo ""

for i in {1..10}; do
  echo "=========================================="
  echo "Test $i/10"
  echo "=========================================="
  ./scripts/measure-recovery.sh fault-test
  echo ""
  sleep 5
done
```

### Analyze Results

**Typical Results (on macOS M1):**

```
Test 1: Leader Election: 2s, Total Recovery: 3s
Test 2: Leader Election: 1s, Total Recovery: 2s
Test 3: Leader Election: 2s, Total Recovery: 3s
Test 4: Leader Election: 1s, Total Recovery: 2s
Test 5: Leader Election: 2s, Total Recovery: 3s
Test 6: Leader Election: 1s, Total Recovery: 2s
Test 7: Leader Election: 2s, Total Recovery: 3s
Test 8: Leader Election: 1s, Total Recovery: 2s
Test 9: Leader Election: 2s, Total Recovery: 3s
Test 10: Leader Election: 1s, Total Recovery: 2s

Average Leader Election Time: ~1.6s
Average Total Recovery Time: ~2.5s
```

### Calculate Averages (Optional)

```bash
# If you want exact averages, install bc:
# brew install bc

# Then use this script to calculate
cat > ~/kafka-learning-lab/calculate-avg-recovery.sh << 'EOF'
#!/bin/bash
echo "Paste recovery times (Ctrl+D when done):"
SUM=0
COUNT=0
while read -r TIME; do
  SUM=$(echo "$SUM + $TIME" | bc)
  COUNT=$((COUNT + 1))
done
AVG=$(echo "scale=2; $SUM / $COUNT" | bc)
echo "Average: ${AVG}s"
EOF

chmod +x ~/kafka-learning-lab/calculate-avg-recovery.sh
```

### Lab 9 Takeaways

✅ **Typical recovery: 1-3 seconds** (very fast!)  
✅ **Consistent across multiple tests** (predictable)  
✅ **Leader election:** 1-2 seconds  
✅ **Full recovery (first write):** 2-3 seconds  
✅ **macOS M1 performance:** Excellent for Kafka testing

***

## Best Practices & Production Recommendations

### 1. Replication Factor Guidelines

| Environment | Replication Factor | Reason |
|-------------|-------------------|--------|
| Development | 1 | Speed, no durability needed |
| Staging | 2 | Test failure scenarios |
| **Production** | **3** | **Industry standard** ✅ |
| Mission-Critical | 5 | Finance, healthcare |

### 2. min.insync.replicas Configuration

```bash
# Recommended for most production workloads
replication.factor=3
min.insync.replicas=2  ✅

# Can tolerate 1 broker failure while accepting writes
```

**Formula:** `min.insync.replicas = ceil(RF / 2)`

**Examples:**
- RF=3 → min.insync.replicas=2
- RF=5 → min.insync.replicas=3
- RF=2 → min.insync.replicas=2 (but RF=2 not recommended for prod)

### 3. Producer Configuration

```bash
# Critical data (orders, payments, transactions)
acks=all
retries=2147483647  # Max retries
max.in.flight.requests.per.connection=1  # Preserve ordering
enable.idempotence=true  # Exactly-once semantics
compression.type=lz4  # Fast compression

# Non-critical data (logs, metrics)
acks=1
retries=3
compression.type=lz4
```

### 4. Consumer Configuration

```bash
# Manual offset management (recommended)
enable.auto.commit=false
auto.offset.reset=earliest  # Or latest based on use case

# For transactional data
isolation.level=read_committed

# Session timeouts
session.timeout.ms=30000  # 30 seconds
heartbeat.interval.ms=3000  # 3 seconds
```

### 5. Topic Configuration

```bash
# Standard topic creation template
kafka/bin/kafka-topics.sh --create \
  --topic <topic-name> \
  --bootstrap-server localhost:9092 \
  --partitions <num-partitions> \
  --replication-factor 3 \
  --config min.insync.replicas=2 \
  --config unclean.leader.election.enable=false \
  --config compression.type=lz4 \
  --config retention.ms=604800000  # 7 days
```

### 6. Monitoring Must-Haves

**Broker Metrics:**
- `UnderReplicatedPartitions` → **Alert if > 0 for 5 minutes**
- `OfflinePartitionsCount` → **Alert if > 0 immediately**
- `ActiveControllerCount` → Must be exactly 1

**Topic Metrics:**
- ISR shrink rate (frequent shrinks = unstable cluster)
- Leader election rate (should be rare)
- Consumer lag per group

**Alert Thresholds:**
```
Critical: UnderReplicatedPartitions > 0 for 5 minutes
Critical: OfflinePartitionsCount > 0
Warning: ISR shrink events > 10/hour
Critical: Consumer lag > 100,000 messages
```

### 7. Capacity Planning

**Calculate Broker Capacity:**
```
Broker Capacity = (Disk Size × 0.7) / Replication Factor

Example:
1TB disk, RF=3
Capacity = (1000GB × 0.7) / 3 = 233GB usable per broker
```

**Partition Count Limits:**
- Max partitions per broker: ~4,000 (practical limit)
- Max partitions per cluster: 200,000 (Kafka 2.8+)

**Rule of Thumb:**
```
Partitions per topic = Desired throughput ÷ Consumer throughput

Example:
Need 600 MB/s, consumer does 100 MB/s
Partitions = 600 ÷ 100 = 6 partitions
```

### 8. Operational Checklist

**Before Production:**
- [ ] `replication.factor ≥ 3`
- [ ] `min.insync.replicas = RF - 1`
- [ ] `unclean.leader.election.enable = false`
- [ ] Monitoring setup (Prometheus + Grafana)
- [ ] Backup and disaster recovery plan
- [ ] Tested broker failure scenarios (these labs!)
- [ ] Load testing completed
- [ ] Security configured (SSL/SASL)

**Daily Operations:**
- [ ] Check under-replicated partitions
- [ ] Review consumer lag
- [ ] Monitor disk usage (alert at 70%)
- [ ] Check broker logs for errors
- [ ] Verify all brokers are in cluster

***

## Troubleshooting Common Issues

### Issue 1: NotEnoughReplicasException

**Symptom:**
```
org.apache.kafka.common.errors.NotEnoughReplicasException
```

**Diagnosis:**
```bash
kafka/bin/kafka-topics.sh --describe \
  --under-replicated-partitions \
  --bootstrap-server localhost:9092
```

**Common Causes:**
1. Broker down (ISR < min.insync.replicas)
2. Network partition
3. Disk full (follower can't replicate)

**Solution:**
```bash
# Check broker health
for i in {0..2}; do
  if pgrep -f "server-$i.properties" > /dev/null; then
    echo "✅ Broker $i running"
  else
    echo "❌ Broker $i down - restarting..."
    ./scripts/start-broker-$i.sh
  fi
done

# Check disk space
df -h /tmp/kafka-logs-*

# If disk full, clean up old logs or increase retention
```

### Issue 2: Leader Not Available

**Symptom:**
```
org.apache.kafka.common.errors.LeaderNotAvailableException
```

**Diagnosis:**
```bash
kafka/bin/kafka-topics.sh --describe \
  --topic <topic> \
  --bootstrap-server localhost:9092
```

**Common Causes:**
1. All brokers in ISR are down
2. Topic just created (metadata propagating)
3. Network issues

**Solution:**
```bash
# Wait 30 seconds for metadata sync
sleep 30

# Check if issue persists
kafka/bin/kafka-topics.sh --describe --topic <topic> --bootstrap-server localhost:9092

# If no leader shown, restart all brokers
for i in {0..2}; do
  pkill -15 -f "server-$i.properties"  # Graceful shutdown
done
sleep 5
for i in {0..2}; do
  ./scripts/start-broker-$i.sh
done
```

### Issue 3: Consumer Lag Growing

**Symptom:**
```bash
kafka/bin/kafka-consumer-groups.sh --describe --group mygroup --bootstrap-server localhost:9092

# Shows:
# LAG: 50000 (and growing)
```

**Diagnosis:**
```bash
# Check if consumer is alive
kafka/bin/kafka-consumer-groups.sh --describe \
  --group mygroup \
  --bootstrap-server localhost:9092 \
  --state

# Check partition assignment
kafka/bin/kafka-consumer-groups.sh --describe \
  --group mygroup \
  --bootstrap-server localhost:9092 \
  --members
```

**Common Causes:**
1. Consumer too slow (processing bottleneck)
2. Not enough consumers (hot partition)
3. Network issues
4. Consumer crashed

**Solution:**
```bash
# Option 1: Add more consumers to group

# Option 2: Increase partitions (if single hot partition)
kafka/bin/kafka-topics.sh --alter \
  --topic <topic> \
  --partitions 6 \
  --bootstrap-server localhost:9092

# Option 3: Optimize consumer code (if processing is slow)
```

### Issue 4: "Too Many Open Files" (macOS)

**Symptom:**
```
java.io.IOException: Too many open files
```

**Diagnosis:**
```bash
# Check current limit
ulimit -n

# Check how many files Kafka is using
lsof -p $(pgrep -f "server-0.properties") | wc -l
```

**Solution:**
```bash
# Increase limit temporarily
ulimit -n 10000

# Make permanent (add to ~/.zshrc)
echo "ulimit -n 10000" >> ~/.zshrc
source ~/.zshrc

# Verify
ulimit -n
```

### Issue 5: Broker Won't Start

**Symptom:**
Broker process exits immediately after starting.

**Diagnosis:**
```bash
# Check broker logs
tail -f ~/kafka-learning-lab/kafka/logs/server.log

# Common errors:
# - "Address already in use" → Port conflict
# - "Disk full" → No space left
# - "Java

[1](https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/attachments/84622635/b4c2d0f0-f66b-4dc7-8087-0e8b2b046579/paste.txt)
[2](https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/attachments/84622635/c67a6178-b6c1-47b9-8694-55517cd53972/paste.txt)
[3](https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/attachments/images/84622635/324f2cde-9bfb-410f-9e98-3ee904b98915/Screenshot-2025-12-28-at-10.24.28-AM.jpg)
[4](https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/attachments/84622635/39a39357-32e4-46ac-bcd1-37be0a3eabe7/paste.txt)
```

```bash
# Common errors:
# - "Address already in use" → Port conflict
# - "Disk full" → No space left
# - "Java heap space" → Memory issue
# - "Lock file" → Previous instance didn't shut down cleanly
```

**Solutions:**

```bash
# Port conflict - kill process using the port
lsof -ti:9092 | xargs kill -9  # For broker 0
lsof -ti:9093 | xargs kill -9  # For broker 1
lsof -ti:9094 | xargs kill -9  # For broker 2

# Disk full - clean up old logs
df -h /tmp
rm -rf /tmp/kafka-logs-*/cleaner-offset-checkpoint.tmp

# Lock file issue - remove stale lock
rm -f /tmp/kafka-logs-*/.lock

# Memory issue - increase Java heap in start script
# Edit scripts/start-broker-X.sh and add:
# export KAFKA_HEAP_OPTS="-Xmx2G -Xms2G"

# Then restart
./scripts/start-broker-0.sh
```

### Issue 6: ZooKeeper Connection Lost

**Symptom:**
```
WARN Session 0x0 for server null, unexpected error, closing socket connection
```

**Diagnosis:**
```bash
# Check if ZooKeeper is running
ps aux | grep zookeeper | grep -v grep

# Test ZooKeeper connectivity
echo stat | nc localhost 2181
```

**Solution:**
```bash
# Restart ZooKeeper
pkill -9 -f zookeeper
./scripts/start-zookeeper.sh

# Wait for ZooKeeper to be ready
sleep 5

# Restart all Kafka brokers
for i in {0..2}; do
  pkill -9 -f "server-$i.properties"
  ./scripts/start-broker-$i.sh
  sleep 5
done
```

### Issue 7: Partition Offline

**Symptom:**
```bash
kafka/bin/kafka-topics.sh --describe --topic <topic> --bootstrap-server localhost:9092

# Shows:
# Partition: 1    Leader: -1    Replicas: 0,1,2    Isr:
```

**Diagnosis:**
```bash
# Check unavailable partitions
kafka/bin/kafka-topics.sh --describe \
  --unavailable-partitions \
  --bootstrap-server localhost:9092
```

**Common Causes:**
1. All replicas down
2. All replicas out of ISR
3. Unclean leader election disabled (and no in-sync replicas)

**Solution:**
```bash
# Option 1: Restart all brokers hosting replicas
for i in {0..2}; do
  if ! pgrep -f "server-$i.properties" > /dev/null; then
    ./scripts/start-broker-$i.sh
    sleep 10
  fi
done

# Option 2: If data loss acceptable, enable unclean leader election
kafka/bin/kafka-configs.sh --alter \
  --entity-type topics \
  --entity-name <topic> \
  --add-config unclean.leader.election.enable=true \
  --bootstrap-server localhost:9092

# Wait for leader election
sleep 5

# Disable again immediately
kafka/bin/kafka-configs.sh --alter \
  --entity-type topics \
  --entity-name <topic> \
  --delete-config unclean.leader.election.enable \
  --bootstrap-server localhost:9092
```

***

## Quick Reference Commands

### macOS Process Management

```bash
# ===== Finding Processes =====

# Find all Kafka brokers
pgrep -fl kafka.Kafka

# Find specific broker
pgrep -f "server-0.properties"

# Check if broker is running
if pgrep -f "server-0.properties" > /dev/null; then
  echo "Broker 0 is running"
else
  echo "Broker 0 is NOT running"
fi

# ===== Killing Processes =====

# Kill specific broker (forceful - simulate crash)
pkill -9 -f "server-1.properties"

# Kill specific broker (graceful shutdown)
pkill -15 -f "server-1.properties"

# Kill all Kafka brokers (emergency)
pkill -9 -f "kafka.Kafka"

# Pause broker (freeze simulation)
pkill -STOP -f "server-0.properties"

# Resume paused broker
pkill -CONT -f "server-0.properties"

# ===== Resource Monitoring =====

# Check open files per broker
lsof -p $(pgrep -f "server-0.properties") | wc -l

# Check memory usage by broker (in MB)
ps -o rss= -p $(pgrep -f "server-0.properties") | awk '{print $1/1024 " MB"}'

# Check CPU usage
ps -o %cpu= -p $(pgrep -f "server-0.properties")

# ===== Network =====

# Check if broker ports are listening
lsof -iTCP:9092 -sTCP:LISTEN
lsof -iTCP:9093 -sTCP:LISTEN
lsof -iTCP:9094 -sTCP:LISTEN

# Test broker connectivity
nc -zv localhost 9092
nc -zv localhost 9093
nc -zv localhost 9094

# Kill process using specific port
lsof -ti:9092 | xargs kill -9
```

### Kafka Health Checks

```bash
# ===== Cluster Health =====

# Check all topics
kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092

# Check under-replicated partitions (should be 0)
kafka/bin/kafka-topics.sh --describe \
  --under-replicated-partitions \
  --bootstrap-server localhost:9092

# Check offline partitions (should be 0)
kafka/bin/kafka-topics.sh --describe \
  --unavailable-partitions \
  --bootstrap-server localhost:9092

# Check specific topic health
kafka/bin/kafka-topics.sh --describe \
  --topic fault-test \
  --bootstrap-server localhost:9092

# ===== Consumer Groups =====

# List all consumer groups
kafka/bin/kafka-consumer-groups.sh --list \
  --bootstrap-server localhost:9092

# Check consumer group lag
kafka/bin/kafka-consumer-groups.sh --describe \
  --group <group-name> \
  --bootstrap-server localhost:9092

# Check consumer group state
kafka/bin/kafka-consumer-groups.sh --describe \
  --group <group-name> \
  --bootstrap-server localhost:9092 \
  --state

# ===== Broker Logs =====

# Tail broker logs
tail -f ~/kafka-learning-lab/kafka/logs/server.log

# Search for errors
grep ERROR ~/kafka-learning-lab/kafka/logs/server.log

# Search for warnings
grep WARN ~/kafka-learning-lab/kafka/logs/server.log

# ===== Disk Usage =====

# Check Kafka log directories
df -h /tmp/kafka-logs-*

# Check size of each partition directory
du -sh /tmp/kafka-logs-*/*
```

### Testing Commands

```bash
# ===== Random Selection (macOS) =====

# Random broker (0, 1, or 2) - use jot on macOS
BROKER=$(jot -r 1 0 2)
echo "Selected broker: $BROKER"

# Random port
PORT=$(jot -r 1 9092 9094)

# ===== Message Production =====

# Quick test message
echo "Test at $(date +%H:%M:%S)" | \
kafka/bin/kafka-console-producer.sh \
  --topic fault-test \
  --bootstrap-server localhost:9092 \
  --producer-property acks=all

# Bulk test messages
for i in {1..100}; do echo "Message $i"; done | \
kafka/bin/kafka-console-producer.sh \
  --topic fault-test \
  --bootstrap-server localhost:9092

# ===== Message Consumption =====

# Consume from beginning
kafka/bin/kafka-console-consumer.sh \
  --topic fault-test \
  --from-beginning \
  --bootstrap-server localhost:9092 \
  --timeout-ms 5000

# Count messages in topic
kafka/bin/kafka-run-class.sh org.apache.kafka.tools.GetOffsetShell \
  --bootstrap-server localhost:9092 \
  --topic fault-test | \
  awk -F: '{sum += $3} END {print sum}'

# ===== Configuration =====

# View topic configuration
kafka/bin/kafka-configs.sh --describe \
  --entity-type topics \
  --entity-name fault-test \
  --bootstrap-server localhost:9092

# Alter configuration
kafka/bin/kafka-configs.sh --alter \
  --entity-type topics \
  --entity-name fault-test \
  --add-config min.insync.replicas=2 \
  --bootstrap-server localhost:9092
```

### Emergency Recovery

```bash
# ===== Nuclear Option (Complete Reset) =====

# WARNING: This deletes ALL data!

# 1. Stop all Kafka brokers
pkill -9 -f "kafka.Kafka"

# 2. Stop ZooKeeper
pkill -9 -f "zookeeper"

# 3. Delete all data
rm -rf /tmp/kafka-logs-*
rm -rf /tmp/zookeeper

# 4. Restart ZooKeeper
./scripts/start-zookeeper.sh
sleep 5

# 5. Restart all brokers
for i in {0..2}; do
  ./scripts/start-broker-$i.sh
  sleep 5
done

# 6. Recreate topics
kafka/bin/kafka-topics.sh --create \
  --topic fault-test \
  --bootstrap-server localhost:9092 \
  --partitions 3 \
  --replication-factor 3 \
  --config min.insync.replicas=2
```

***

## Lab Session Checklist

**Print this checklist for your lab session:**

```bash
cat > ~/kafka-learning-lab/lab-session-checklist.txt << 'EOF'
╔══════════════════════════════════════════════════════════╗
║  Kafka Fault Tolerance Testing - Session Checklist      ║
╚══════════════════════════════════════════════════════════╝

Pre-Lab Setup (15 minutes)
───────────────────────────────────────────────────────────
[ ] Increase ulimit: ulimit -n 10000
[ ] Verify all 3 brokers running
[ ] Create fault-test topic (RF=3, min.insync=2)
[ ] Test monitoring script
[ ] Open 4-5 terminal windows

Core Labs (90 minutes)
───────────────────────────────────────────────────────────
Lab 1: Leader Broker Failure (20 min)
[ ] Record baseline partition leaders
[ ] Start continuous producer/consumer
[ ] Kill leader broker
[ ] Observe election (~1-2 seconds)
[ ] Restart broker, watch ISR rejoin
[ ] Verify no data loss
✅ Takeaway: Leader election is automatic and fast

Lab 2: ISR Behavior (15 min)
[ ] Pause broker with pkill -STOP
[ ] Watch ISR shrink after 30 seconds
[ ] Resume with pkill -CONT
[ ] Watch ISR expand back
[ ] Check under-replicated partitions
✅ Takeaway: ISR is dynamic and self-healing

Lab 3: min.insync.replicas (20 min)
[ ] Create strict-durability topic (RF=3, min.insync=3)
[ ] Produce with all replicas (works)
[ ] Kill 1 broker, wait 35 seconds
[ ] Try producing (fails - NotEnoughReplicasException)
[ ] Lower min.insync.replicas to 2
[ ] Produce again (works)
[ ] Restart broker
✅ Takeaway: min.insync.replicas enforces durability

Lab 4: Multiple Broker Failures (15 min)
[ ] Kill 2/3 brokers simultaneously
[ ] Observe partition availability
[ ] Check which partitions are offline
[ ] Try producing (fails)
[ ] Restart both brokers
[ ] Verify full recovery
✅ Takeaway: Need > 50% brokers for availability

Lab 5: Producer Behavior (20 min)
[ ] Test acks=0 during failure (data loss)
[ ] Test acks=1 during failure (possible loss)
[ ] Test acks=all during failure (no loss)
[ ] Compare results in table
✅ Takeaway: acks=all is safest for critical data

Advanced Labs (45 minutes)
───────────────────────────────────────────────────────────
Lab 6: Consumer Behavior (15 min)
[ ] Start 3 consumers in same group
[ ] Verify partition assignment
[ ] Kill leader of partition 0
[ ] Observe consumer reconnection
[ ] Verify no rebalancing triggered
✅ Takeaway: Consumers are resilient to broker failures

Lab 7: Network Partition (15 min)
[ ] Pause broker with pkill -STOP
[ ] Wait 35 seconds
[ ] Observe broker removed from ISR
[ ] Produce messages (still works)
[ ] Resume broker with pkill -CONT
[ ] Verify rejoin
✅ Takeaway: Kafka prevents split-brain

Lab 8: Data Durability (15 min)
[ ] Create durability-test topic
[ ] Produce 100 initial messages
[ ] Run chaos test (2 minutes)
[ ] Produce 100 more messages during chaos
[ ] Verify all 200 messages received
[ ] Check for duplicates (should be 0)
[ ] Check for gaps (should be 0)
✅ Takeaway: Zero data loss with correct config

Bonus Lab (20 minutes)
───────────────────────────────────────────────────────────
Lab 9: Recovery Time Measurement
[ ] Run measure-recovery.sh 10 times
[ ] Record leader election times
[ ] Record total recovery times
[ ] Calculate averages
✅ Takeaway: Typical recovery is 1-3 seconds

Wrap-up (15 minutes)
───────────────────────────────────────────────────────────
[ ] Review all takeaways
[ ] Document interesting observations
[ ] Clean up test topics (optional)
[ ] Stop all brokers gracefully
[ ] Plan next module (05-replication-partitioning.md)

╔══════════════════════════════════════════════════════════╗
║  Key Learnings to Remember                              ║
╚══════════════════════════════════════════════════════════╝

✅ Leader election: 1-2 seconds (automatic)
✅ ISR is dynamic (shrinks/expands automatically)
✅ min.insync.replicas enforces durability guarantees
✅ acks=all prevents data loss
✅ Kafka handles failures gracefully
✅ Proper config = zero data loss

Production Config Template:
──────────────────────────────────────────────────────────
replication.factor=3
min.insync.replicas=2
unclean.leader.election.enable=false
acks=all (producer)
enable.idempotence=true (producer)

EOF

cat ~/kafka-learning-lab/lab-session-checklist.txt
```

***

## Summary & Key Takeaways

### What You've Accomplished

🎓 **Completed 8-9 hands-on labs** covering all aspects of Kafka fault tolerance  
🎓 **Simulated real production failures** (broker crashes, network partitions, multiple failures)  
🎓 **Measured recovery times** (1-3 seconds typical)  
🎓 **Tested data durability** (zero loss with correct configuration)  
🎓 **Validated producer/consumer resilience** (automatic reconnection)  
🎓 **Mastered ISR mechanics** (dynamic shrink/expand)  
🎓 **Understood min.insync.replicas** (durability vs. availability trade-off)

### Critical Concepts Mastered

#### 1. Replication & ISR
```
✅ ISR = replicas caught up with leader
✅ Removed after 30 seconds lag (replica.lag.time.max.ms)
✅ Automatically rejoin when caught up
✅ Monitor under-replicated partitions in production
```

#### 2. Leader Election
```
✅ Happens automatically in 1-2 seconds
✅ Only ISR replicas are eligible
✅ Controller orchestrates election
✅ Prevents split-brain scenarios
```

#### 3. Producer Durability
```
✅ acks=0: Fast, unsafe (data loss possible)
✅ acks=1: Balanced, risky (loss if leader fails)
✅ acks=all: Safe, slower (no loss with min.insync.replicas)
```

#### 4. Fault Tolerance Limits
```
✅ RF=3, min.insync=2: Can lose 1 broker
✅ RF=3, min.insync=3: Cannot lose any broker (avoid!)
✅ Losing > 50% brokers: Unavailable for writes
```

### Production-Ready Configuration

```bash
# Topic Configuration (Standard)
replication.factor=3
min.insync.replicas=2
unclean.leader.election.enable=false
compression.type=lz4
retention.ms=604800000  # 7 days

# Producer Configuration (Critical Data)
acks=all
retries=2147483647  # Max int
max.in.flight.requests.per.connection=1  # Ordering
enable.idempotence=true  # Exactly-once
compression.type=lz4

# Consumer Configuration
enable.auto.commit=false  # Manual control
isolation.level=read_committed  # For transactions
session.timeout.ms=30000
heartbeat.interval.ms=3000
```

### Monitoring Checklist

**Must-Monitor Metrics:**
```
🔴 UnderReplicatedPartitions > 0 (alert immediately)
🔴 OfflinePartitionsCount > 0 (critical alert)
🟡 ISR shrink rate > 10/hour (investigate)
🟡 Consumer lag > threshold (scale consumers)
🟢 Leader election rate (should be rare)
```

### Common Gotchas & How to Avoid

| Gotcha | Impact | Prevention |
|--------|--------|-----------|
| `min.insync.replicas = RF` | No fault tolerance | Always set `min.insync = RF - 1` |
| `acks=1` in production | Data loss risk | Use `acks=all` for critical data |
| Too many partitions | Controller overhead | Plan capacity: ~4,000 per broker max |
| Not monitoring ISR | Delayed failure detection | Alert on under-replicated partitions |
| Single broker cluster | No redundancy | Always use RF ≥ 3 in production |

***

## Next Steps

### Immediate Actions

1. **Document Your Findings**
   ```bash
   # Create your observations file
   cat > ~/kafka-learning-lab/fault-tolerance-observations.md << 'EOF'
   # My Fault Tolerance Testing Observations
   
   ## Lab 1: Leader Failure
   - Observed recovery time: X seconds
   - Interesting finding: ...
   
   ## Lab 2: ISR Behavior
   - ISR shrink time: 30 seconds (as expected)
   - Note: ...
   
   ## Lab 3: min.insync.replicas
   - Key learning: ...
   
   [Continue with your notes...]
   EOF
   ```

2. **Save Your Test Scripts**
   ```bash
   # Your test scripts are in:
   ls -la ~/kafka-learning-lab/test-scripts/
   ls -la ~/kafka-learning-lab/scripts/
   
   # Keep these for future reference!
   ```

3. **Clean Up (Optional)**
   ```bash
   # If you want to clean up test topics
   kafka/bin/kafka-topics.sh --delete --topic fault-test --bootstrap-server localhost:9092
   kafka/bin/kafka-topics.sh --delete --topic strict-durability --bootstrap-server localhost:9092
   kafka/bin/kafka-topics.sh --delete --topic durability-test --bootstrap-server localhost:9092
   kafka/bin/kafka-topics.sh --delete --topic consumer-test --bootstrap-server localhost:9092
   
   # Or keep them for future experiments
   ```

### Move to Next Module: 05-replication-partitioning.md

**What You'll Learn Next:**
- Deep dive into replication mechanics (log segments, offsets)
- Partition leader election algorithms (detailed)
- High-water mark vs. log-end-offset
- Exactly-once semantics (transactions)
- Advanced replication configurations

**Why This Matters:**
Now that you've **seen** fault tolerance in action, you'll learn the **theory and internals** behind it. This completes your understanding from practice → theory.

### Continue Your Kafka Journey

**Recommended Learning Path:**
1. ✅ **04-fault-tolerance-testing.md** ← **YOU ARE HERE!**
2. ⏭️ **05-replication-partitioning.md** (Next - Deep dive)
3. 📝 **06-python-integration.md** (Build applications)
4. 📊 **07-monitoring-setup.md** (Observability)
5. 🚀 **08-spark-integration.md** (Stream processing)
6. 🔧 **09-troubleshooting.md** (War stories)

***

## Additional Resources

### Official Documentation
- [Kafka Replication Design](https://kafka.apache.org/documentation/#replication)
- [Kafka Configuration Reference](https://kafka.apache.org/documentation/#configuration)
- [Producer Configurations](https://kafka.apache.org/documentation/#producerconfigs)
- [Consumer Configurations](https://kafka.apache.org/documentation/#consumerconfigs)

### Recommended Reading
- "Kafka: The Definitive Guide" (Chapters 5-6: Replication & Reliability)
- Confluent Blog: "Hands-free Kafka Replication"
- Apache Kafka KIPs (Kafka Improvement Proposals)

### Community
- Apache Kafka Mailing Lists
- Confluent Community Forum
- Kafka Summit recordings

***

## Congratulations! 🎉

You've completed comprehensive fault tolerance testing for Apache Kafka!

**You now understand:**
- ✅ How Kafka handles failures gracefully
- ✅ When and why data loss can occur
- ✅ How to configure Kafka for zero data loss
- ✅ How to monitor Kafka health in production
- ✅ How to troubleshoot common issues

**You're now equipped to:**
- 🎯 Design resilient Kafka architectures
- 🎯 Configure production Kafka clusters correctly
- 🎯 Handle broker failures confidently
- 🎯 Make informed durability vs. availability trade-offs
- 🎯 Debug ISR and replication issues

***

## Final Notes

**Remember the Golden Rules:**

1. **Always use RF=3 in production**
2. **Always set min.insync.replicas=2 for RF=3**
3. **Always use acks=all for critical data**
4. **Always monitor under-replicated partitions**
5. **Always test failure scenarios before going live**

**macOS-Specific Reminders:**
- Use `pkill` instead of `kill` for process management
- Use `jot` instead of `shuf` for random numbers
- Increase `ulimit -n` to 10000 for Kafka
- `/tmp` is cleared on reboot - consider permanent storage

***

**Save this document:** `~/kafka-learning-lab/docs/04-fault-tolerance-testing.md`

**Ready for the next challenge?** Let me know when you want to start **05-replication-partitioning.md**! 🚀

***

*End of Document - Kafka Fault Tolerance Testing (Complete)*
