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
Topic: fault-test       TopicId: DTTOJR5AQcqUUpNxVPkauA PartitionCount: 3       ReplicationFactor: 3    Configs: min.insync.replicas=2,segment.bytes=1073741824
        Topic: fault-test       Partition: 0    Leader: 2       Replicas: 2,0,1 Isr: 2,0,1      Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 1    Leader: 1       Replicas: 1,2,0 Isr: 1,2,0      Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 2    Leader: 0       Replicas: 0,1,2 Isr: 0,1,2      Elr: N/A        LastKnownElr: N/A
```

**Understanding This Output:**

```
Partition 0:
  Leader: Broker 2 (handles all reads/writes)
  Replicas: 2,0,1 (data exists on all 3 brokers)
  ISR: 2,0,1 (all 3 replicas are in-sync ✅)

Visual:
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Broker 0   │────▶│  Broker 2   │◀────│  Broker 1   │
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
BOOTSTRAP_SERVER=${2:-localhost:9092,localhost:9093,localhost:9094}

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
│  │ Broker 2     │ ◀─── LEADER           │
│  │ (Leader)     │      Handles all I/O  │
│  └──────────────┘                       │
│         │                               │
│         │ Replication                   │
│         ├──────────────┬─────────────┐  │
│         ▼              ▼             ▼  │
│  ┌──────────┐   ┌──────────┐  ┌──────────┐
│  │Broker 0  │   │Broker 2  │  │Broker 1  │
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
Topic: fault-test       TopicId: DTTOJR5AQcqUUpNxVPkauA PartitionCount: 3       ReplicationFactor: 3    Configs: min.insync.replicas=2,segment.bytes=1073741824
        Topic: fault-test       Partition: 0    Leader: 2       Replicas: 2,0,1 Isr: 2,0,1      Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 1    Leader: 1       Replicas: 1,2,0 Isr: 1,2,0      Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 2    Leader: 0       Replicas: 0,1,2 Isr: 0,1,2      Elr: N/A        LastKnownElr: N/A
```

**Record This Information:**
```
Partition 0: Leader = Broker 2
Partition 1: Leader = Broker 1
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

press `Ctrl+C` on broker 2 terminal to kill it

### Step 4: Observe Recovery

**Watch Terminal 1 (Monitor):**

You should see ISR change within 1-2 seconds:

```
Before:
Topic: fault-test       Partition: 0    Leader: 2       Replicas: 2,0,1 Isr: 2,0,1      Elr: N/A        LastKnownElr: N/A

After (~2 seconds):
Topic: fault-test       Partition: 0    Leader: 0       Replicas: 2,0,1 Isr: 0,1        Elr: N/A        LastKnownElr: N/A
```

### Step 5: Restart Dead Broker

**In Terminal 4:**

```bash
# Restart broker 1
./scripts/start-broker-2.sh

# Wait 10 seconds for it to catch up
sleep 10

# Check ISR again
kafka/bin/kafka-topics.sh --describe \
  --topic fault-test \
  --bootstrap-server localhost:9092 | grep "Partition: 0"
```

**Expected:**
```
Topic: fault-test       Partition: 0    Leader: 0       Replicas: 2,0,1 Isr: 0,1,2      Elr: N/A        LastKnownElr: N/A
```

**What Happened:**
1. Broker 2 restarted
2. Loaded partition logs from disk
3. Started replicating from new leader (Broker 0)
4. Caught up within 10 seconds
5. Controller added it back to ISR

**Note:** Broker 2 is now a FOLLOWER (not leader anymore). Leadership doesn't automatically return.

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

### Step 8: Stop Continuous Consumer and Producer

```bash
# In Terminal, press Ctrl+C to stop
```

### Lab 1 Takeaways

✅ **Leader election happens automatically** (1-2 seconds)  
✅ **Producers/consumers automatically reconnect**  
✅ **No data loss** with `acks=all` and `min.insync.replicas=2`  
✅ **Recovered broker rejoins as follower** (not leader)  
✅ **ISR shrinks during failure, expands after recovery**

***

## Lab 2: Understanding ISR Behavior

**Goal:** Watch a broker fall out of sync and rejoin in real-time.

**Core Concept:** ISR = "In-Sync Replicas" = Brokers that are keeping up with the leader. If a broker is too slow or frozen for 30 seconds, Kafka kicks it out of ISR.

***

### Setup: One Terminal, Simple Commands

**Step 1: Check Your Starting Point**

```bash
# See current ISR for fault-test topic
kafka/bin/kafka-topics.sh --describe \
  --topic fault-test \
  --bootstrap-server localhost:9092
```

**Expected Output:**
```
Topic: fault-test       TopicId: DTTOJR5AQcqUUpNxVPkauA PartitionCount: 3       ReplicationFactor: 3    Configs: min.insync.replicas=2,segment.bytes=1073741824
        Topic: fault-test       Partition: 0    Leader: 2       Replicas: 2,0,1 Isr: 2,1,0      Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 1    Leader: 2       Replicas: 1,2,0 Isr: 2,0,1      Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 2    Leader: 2       Replicas: 0,1,2 Isr: 2,0,1      Elr: N/A        LastKnownElr: N/A
```

**What you see:** `Isr: 1,2,0` means brokers 1, 2, and 0 are all in-sync. ✅

***

### The Experiment: Freeze and Watch

**Step 2: Freeze Broker 0**

```bash
# Freeze broker 0 (like it hung/crashed but process still exists)
pkill -STOP -f "server-0.properties"

echo "✅ Broker 0 is now FROZEN"
echo "⏱️  Starting timer..."
date +%H:%M:%S
```

**What just happened?** Broker 0 can't respond to anything now. It's frozen in place.

***

**Step 3: Watch ISR Change (Live Monitoring)**

Open a **second terminal** and run this:

```bash
./scripts/monitor-cluster.sh fault-test
```

**What you'll see (timeline):**

```
⏰ Time: 20:15:00 (T=0 seconds)
Partition: 0    Isr: 1,2,0    ← Broker 0 still in ISR

⏰ Time: 20:15:10 (T=10 seconds)
Partition: 0    Isr: 1,2,0    ← Still there...

⏰ Time: 20:15:20 (T=20 seconds)
Partition: 0    Isr: 1,2,0    ← Still hanging in...

⏰ Time: 20:15:30 (T=30 seconds)
Partition: 0    Isr: 1,2,0    ← Almost at threshold...

⏰ Time: 20:15:40 (T=40 seconds)
Partition: 0    Isr: 1,2      ← GONE! Broker 0 kicked out! ❌
Partition: 2    Isr: 1,2      ← Also removed from partition 2!
```

**💡 What you're seeing:** After ~30-40 seconds, Kafka realizes broker 0 is dead/frozen and removes it from ISR.

***

**Step 4: Unfreeze Broker 0**

Go back to **first terminal**:

```bash
# Unfreeze broker 0
pkill -CONT -f "server-0.properties"

echo "✅ Broker 0 is now RUNNING again"
echo "⏱️  Watch it rejoin ISR..."
date +%H:%M:%S
```

**Watch the second terminal:**

```
⏰ Time: 20:16:00
Partition: 0    Isr: 1,2      ← Broker 0 still out

⏰ Time: 20:16:10
Partition: 0    Isr: 1,2      ← Catching up from leader...

⏰ Time: 20:16:20
Partition: 0    Isr: 1,2,0    ← BACK! Rejoined ISR! ✅
```

**💡 What you're seeing:** Broker 0 catches up by reading missing data from the leader, then rejoins ISR.

***

**Step 5: Stop Monitoring**

In the second terminal, press **Ctrl+C** to stop the loop.

***

### Visual Summary

```
==========================================
  Kafka Cluster Health Monitor
  Time: 10:13:56
==========================================

📊 Topic Information:
Topic: fault-test       TopicId: DTTOJR5AQcqUUpNxVPkauA PartitionCount: 3       ReplicationFactor: 3    Configs: min.insync.replicas=2,segment.bytes=1073741824
        Topic: fault-test       Partition: 0    Leader: 2       Replicas: 2,0,1 Isr: 2,1,0      Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 1    Leader: 1       Replicas: 1,2,0 Isr: 2,1,0      Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 2    Leader: 1       Replicas: 0,1,2 Isr: 2,1,0      Elr: N/A        LastKnownElr: N/A

  📡 Connected via localhost:9092 (Broker 0)

==========================================
🖥️  Broker Process Status:

  ✅ Broker 0 - PID: 92509 - Port: 9092 - RUNNING - ✅ Port responding
  ✅ Broker 1 - PID: 92986 - Port: 9093 - RUNNING - ✅ Port responding
  ✅ Broker 2 - PID: 93406 - Port: 9094 - RUNNING - ✅ Port responding

==========================================
💾 Disk Usage (Kafka Logs):

  🟡  /System/Volumes/Data: 74% used (55Gi free)

==========================================

  Kafka Cluster Health Monitor
  Time: 10:14:22
==========================================

📊 Topic Information:
Topic: fault-test       TopicId: DTTOJR5AQcqUUpNxVPkauA PartitionCount: 3       ReplicationFactor: 3    Configs: min.insync.replicas=2,segment.bytes=1073741824
        Topic: fault-test       Partition: 0    Leader: 2       Replicas: 2,0,1 Isr: 2,1        Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 1    Leader: 1       Replicas: 1,2,0 Isr: 2,1        Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 2    Leader: 1       Replicas: 0,1,2 Isr: 2,1        Elr: N/A        LastKnownElr: N/A

  📡 Connected via localhost:9093 (Broker 1)

==========================================
🖥️  Broker Process Status:

  ✅ Broker 0 - PID: 92509 - Port: 9092 - RUNNING - ✅ Port responding
  ✅ Broker 1 - PID: 92986 - Port: 9093 - RUNNING - ✅ Port responding
  ✅ Broker 2 - PID: 93406 - Port: 9094 - RUNNING - ✅ Port responding

==========================================
💾 Disk Usage (Kafka Logs):

  🟡  /System/Volumes/Data: 74% used (55Gi free)

==========================================
Next refresh in 3 seconds... (Ctrl+C to stop)

==========================================
  Kafka Cluster Health Monitor
  Time: 10:14:30
==========================================

📊 Topic Information:
Topic: fault-test       TopicId: DTTOJR5AQcqUUpNxVPkauA PartitionCount: 3       ReplicationFactor: 3    Configs: min.insync.replicas=2,segment.bytes=1073741824
        Topic: fault-test       Partition: 0    Leader: 2       Replicas: 2,0,1 Isr: 2,1,0      Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 1    Leader: 1       Replicas: 1,2,0 Isr: 2,1,0      Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 2    Leader: 1       Replicas: 0,1,2 Isr: 2,1,0      Elr: N/A        LastKnownElr: N/A

  📡 Connected via localhost:9092 (Broker 0)

==========================================
🖥️  Broker Process Status:

  ✅ Broker 0 - PID: 92509 - Port: 9092 - RUNNING - ✅ Port responding
  ✅ Broker 1 - PID: 92986 - Port: 9093 - RUNNING - ✅ Port responding
  ✅ Broker 2 - PID: 93406 - Port: 9094 - RUNNING - ✅ Port responding

==========================================
💾 Disk Usage (Kafka Logs):

  🟡  /System/Volumes/Data: 74% used (55Gi free)

==========================================
Next refresh in 3 seconds... (Ctrl+C to stop)


```

***

### Key Takeaways (Simple Version)

✅ **ISR = replicas that are "caught up" with the leader**  
✅ **Frozen/slow broker → kicked out after ~30 seconds**  
✅ **Recovered broker → automatically rejoins when caught up**  
✅ **Under-replicated partitions = warning sign** (check this in production!)  
✅ **Kafka keeps working** even with broker out of ISR (as long as min.insync.replicas is met)

***

## Lab 3: Testing min.insync.replicas

**Goal:** See what happens when ISR falls below `min.insync.replicas`.

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

# Should show: 
Topic: strict-durability        TopicId: BY03l_uKSHefOB9NoMHotQ PartitionCount: 1       ReplicationFactor: 3    Configs: min.insync.replicas=3,segment.bytes=1073741824
        Topic: strict-durability        Partition: 0    Leader: 0       Replicas: 0,2,1 Isr: 0,2,1      Elr: N/A        LastKnownElr: N/A
```

**Produce a test message:**
```bash
echo "Test message 1 - All replicas healthy" | \
kafka/bin/kafka-console-producer.sh \
  --topic strict-durability \
  --bootstrap-server localhost:9092 \
  --producer-property acks=all
```
```bash
kafka/bin/kafka-console-consumer.sh \
  --topic strict-durability \
  --from-beginning \
  --bootstrap-server localhost:9092 \
  --property print.timestamp=true

Output:
CreateTime:1767675291061        Test message 1 - All replicas healthy
```
**Expected:** ✅ **Success!** Message accepted.

### Scenario 2: Kill One Broker (Should Fail!)

```bash
# Identify which broker is NOT the leader
# Kill a follower (e.g., broker 2)
pkill -9 -f "server-2.properties"
# or Do Ctrl+C in respective terminal

# Wait for ISR to update (30+ seconds)

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
[2026-01-06 10:31:49,640] WARN [Producer clientId=console-producer] Got error produce response with correlation id 5 on topic-partition strict-durability-0, retrying (2 attempts left). Error: NOT_ENOUGH_REPLICAS (org.apache.kafka.clients.producer.internals.Sender)
.
.
org.apache.kafka.common.errors.NotEnoughReplicasException: Messages are rejected since there are fewer in-sync replicas than required.
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

# output:
Topic: strict-durability        TopicId: BY03l_uKSHefOB9NoMHotQ PartitionCount: 1       ReplicationFactor: 3    Configs: min.insync.replicas=2,segment.bytes=1073741824
        Topic: strict-durability        Partition: 0    Leader: 0       Replicas: 0,2,1 Isr: 0,1        Elr: N/A        LastKnownElr: N/A
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

# Verify ISR
kafka/bin/kafka-topics.sh --describe \
  --topic strict-durability \
  --bootstrap-server localhost:9092
```

**Expected:**
```
Topic: strict-durability        TopicId: BY03l_uKSHefOB9NoMHotQ PartitionCount: 1       ReplicationFactor: 3    Configs: min.insync.replicas=2,segment.bytes=1073741824
        Topic: strict-durability        Partition: 0    Leader: 0       Replicas: 0,2,1 Isr: 0,1,2      Elr: N/A        LastKnownElr: N/A
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

### Setup: Ensure All Brokers Running

```bash
# Verify all 3 brokers are up
./scripts/monitor-cluster.sh

Note:
# ./scripts/monitor-cluster.sh <topic name> by passing topic name at the end we can see topic health and stats
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

# Start the health monitor in terminal 
./scripts/monitor-cluster.sh fault-test

# Wait for ISR update
```

### Check Partition Status

```bash
# Use remaining broker (broker 0 on port 9092)
Look at topic health monitor
```

**Expected Output:**
```
Topic: fault-test       TopicId: DTTOJR5AQcqUUpNxVPkauA PartitionCount: 3       ReplicationFactor: 3    Configs: min.insync.replicas=2,segment.bytes=1073741824
        Topic: fault-test       Partition: 0    Leader: 2       Replicas: 2,0,1 Isr: 2  Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 1    Leader: 2       Replicas: 1,2,0 Isr: 2  Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 2    Leader: 2       Replicas: 0,1,2 Isr: 2  Elr: N/A        LastKnownElr: N/A
```

**Analysis:**
- ✅ All partitions have leader (Broker 2)
- ⚠️ But only 1 replica in ISR!
- ✅ Cluster is partially operational (can read)
- ❌ Writes fail with acks=all (ISR=1 < min.insync.replicas=2)
- ✅ Writes work with acks=1 (leader exists)

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
  --bootstrap-server localhost:9092,localhost:9093,localhost:9094 \
  --producer-property acks=1

Output:
org.apache.kafka.common.errors.NotEnoughReplicasException: Messages are rejected since there are fewer in-sync replicas than required.
```

**Result:** ⚠️ **Might work for partitions 0 & 2** (still fails for partition 1)

### Recovery

```bash
# Restart both brokers
./scripts/start-broker-1.sh
./scripts/start-broker-2.sh

# Wait for full recovery

# Look at health monitor
Topic: fault-test       TopicId: DTTOJR5AQcqUUpNxVPkauA PartitionCount: 3       ReplicationFactor: 3    Configs: min.insync.replicas=2,segment.bytes=1073741824
        Topic: fault-test       Partition: 0    Leader: 2       Replicas: 2,0,1 Isr: 2,0,1      Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 1    Leader: 2       Replicas: 1,2,0 Isr: 2,0,1      Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 2    Leader: 2       Replicas: 0,1,2 Isr: 2,0,1      Elr: N/A        LastKnownElr: N/A
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

**Goal:** Test how different `acks` configurations behave when brokers fail during message production.

---

### Understanding Producer Acknowledgments

When a producer sends messages to Kafka, it can wait for different levels of confirmation:

| Config | Behavior | Performance | Safety |
|--------|----------|-------------|--------|
| `acks=0` | Fire and forget (no confirmation) | ⚡ Fastest | ❌ Unsafe - data loss likely |
| `acks=1` | Leader confirms only | 🚀 Fast | ⚠️ Risky - can lose unsynced data |
| `acks=all` | Leader + ISR confirm | 🐢 Slower | ✅ Safe - no data loss |

---

### Test Overview

We'll use three reusable scripts to test producer behavior:

1. **`produce-messages.sh`** - Send messages with configurable acks level
2. **`consume-and-count.sh`** - Count messages matching a pattern
3. **`test-acks-during-failure.sh`** - Automated failure test

All scripts are in `~/kafka-learning-lab/test-scripts/` directory.

---

### Script 1: Manual Producer Test

**Purpose:** Send messages manually with any acks level.

**Usage:**
```bash
./test-scripts/produce-messages.sh <topic> <count> <acks> [bootstrap-server]
```

**Command:**
```bash
./test-scripts/produce-messages.sh fault-test 5 0
```

**Expected Output:**
```
 ~/kafka-learning-lab │ on main wip !3 ?2  ./test-scripts/produce-messages.sh fault-test 5 0                1 х │ took 47s │ at 05:12:16 PM 
🚀 Starting producer...
  Topic      : fault-test
  Count      : 5
  Acks       : 0
  Bootstrap  : localhost:9092,localhost:9093,localhost:9094

⚠️ WARN (1/5): Message 1 at 17:20:22
   └─ Kafka warning:
      [2026-01-09 17:20:22,985] WARN [Producer clientId=console-producer] Connection to node -1 (localhost/127.0.0.1:9092) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-09 17:20:22,985] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9092 (id: -1 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

✅ SUCCESS (1/5): Message 2 at 17:20:24
⚠️ WARN (2/5): Message 3 at 17:20:25
   └─ Kafka warning:
      [2026-01-09 17:20:26,559] WARN [Producer clientId=console-producer] Connection to node -1 (localhost/127.0.0.1:9092) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)

⚠️ WARN (3/5): Message 4 at 17:20:27
   └─ Kafka warning:
      [2026-01-09 17:20:28,307] WARN [Producer clientId=console-producer] Connection to node -1 (localhost/127.0.0.1:9092) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-09 17:20:28,307] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9092 (id: -1 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

✅ SUCCESS (2/5): Message 5 at 17:20:29

===== Producer Summary =====
✅ SUCCESS   : 2
⚠️ WARNINGS : 3
❌ FAILED    : 0
📊 Success Rate: 40.0%

```

**💡 Tip:** Look at the script to understand the parameters before running it.

---

### Script 2: Manual Consumer Test

**Purpose:** Consume and count messages from a topic.

**Usage:**
```bash
./test-scripts/consume-and-count.sh <topic> [IDLE_TIMEOUT] [bootstrap-server]
```

**Command:**
```bash
./test-scripts/consume-and-count.sh fault-test 1  
```

**Expected Output:**
```
===== Monitoring Topic: fault-test =====
Running on: Darwin arm64
Press Ctrl+C to stop

========================================== ** ==========================================
  Topic Monitor: fault-test
  Time: 17:18:27
==========================================

📊 Topic Information:
Topic: fault-test       TopicId: DTTOJR5AQcqUUpNxVPkauA PartitionCount: 3       ReplicationFactor: 3    Configs: min.insync.replicas=3,segment.bytes=1073741824
        Topic: fault-test       Partition: 0    Leader: 2       Replicas: 2,0,1 Isr: 2,1        Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 1    Leader: 1       Replicas: 1,2,0 Isr: 2,1        Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 2    Leader: 1       Replicas: 0,1,2 Isr: 2,1        Elr: N/A        LastKnownElr: N/A

  📡 Connected via localhost:9093 (Broker 1)

==========================================
🖥️  Broker Process Status:

  ❌ Broker 0 - Port: 9092 - NOT RUNNING (no process found)
  ✅ Broker 1 - PID: 9878 - Port: 9093 - RUNNING - ✅ Port responding
  ✅ Broker 2 - PID: 73333 - Port: 9094 - RUNNING - ✅ Port responding

==========================================
🐘 ZooKeeper Status:

  ✅ ZooKeeper - PID: 72933 - RUNNING
  ✅ Port 2181 - Responding

==========================================
💾 Disk Usage (Kafka Logs):

  🟡  /System/Volumes/Data: 77% used (49Gi free)

==========================================
📥 Starting consumer with dynamic idle timeout...
  Topic        : fault-test
  Idle Timeout : 1s
  Bootstrap    : localhost:9092,localhost:9093,localhost:9094

⏳ Consuming messages...
⚠️  WARN: [2026-01-09 17:18:30,554] WARN [Consumer clientId=console-consumer, groupId=console-consumer-56519] Connection to node -1 (localhost/127.0.0.1:9092) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
⚠️  WARN: [2026-01-09 17:18:30,555] WARN [Consumer clientId=console-consumer, groupId=console-consumer-56519] Bootstrap broker localhost:9092 (id: -1 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)
  📊 Messages consumed: 100
  📊 Messages consumed: 200
  📊 Messages consumed: 300
  📊 Messages consumed: 400
  📊 Messages consumed: 500
  📊 Messages consumed: 600
  📊 Messages consumed: 700
  📊 Messages consumed: 800
  📊 Messages consumed: 900
  📊 Messages consumed: 1000
  📊 Messages consumed: 1100

⏱️  No messages for 1s - stopping consumer

===== Consumer Summary =====
📊 Total messages : 1186
💾 Output file    : /Users/nc25593_shivanand/kafka-learning-lab/test-results/kafka-consume-1767959309-80409.out

===RETURN_VALUE===
1186
```

**💡 Tip:** The output file is saved in `test-results/` for later inspection.

---

### Script 3: Automated Failure Test

**Purpose:** Automatically test producer behavior when a broker fails mid-test.

**Usage:**
```bash
./test-scripts/test-acks-during-failure.sh <acks-level> [topic] [message-count] [broker-to-kill]
```

**What it does:**
1. ✅ Checks broker status
2. 📊 Gets baseline message count
3. 🚀 Starts producer in background
4. ⏱️ Waits 5 seconds (sends ~5 messages)
5. ⚡ Kills specified broker
6. ⏱️ Waits for producer to finish
7. 📥 Counts received messages
8. 📊 Calculates data loss

---

### Test 1: acks=0 Broker 1 is down (Fire and Forget)

**Hypothesis:** Should lose messages because producer doesn't wait for confirmation.

**Steps:**
```bash
./test-scripts/test-acks-during-failure.sh 0 fault-test 5 1
```

<details>
<summary><strong>Expected Result</strong></summary>

```bash
 ~/kafka-learning-lab │ on main wip !3 ?2  ./test-scripts/test-acks-during-failure.sh 0 fault-test 5 1            ✔ │ at 04:32:30 PM 
==========================================
  Acks Failure Test - acks=0
==========================================
Topic: fault-test
Message Count: 5
Broker to Kill: 1

===== Monitoring Topic: fault-test =====
Running on: Darwin arm64
Press Ctrl+C to stop

========================================== ** ==========================================
  Topic Monitor: fault-test
  Time: 16:32:33
==========================================

📊 Topic Information:
Topic: fault-test       TopicId: DTTOJR5AQcqUUpNxVPkauA PartitionCount: 3       ReplicationFactor: 3    Configs: min.insync.replicas=2,segment.bytes=1073741824
        Topic: fault-test       Partition: 0    Leader: 2       Replicas: 2,0,1 Isr: 0,2,1      Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 1    Leader: 2       Replicas: 1,2,0 Isr: 0,2,1      Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 2    Leader: 0       Replicas: 0,1,2 Isr: 0,2,1      Elr: N/A        LastKnownElr: N/A

  📡 Connected via localhost:9092 (Broker 0)

==========================================
🖥️  Broker Process Status:

  ✅ Broker 0 - PID: 73877 - Port: 9092 - RUNNING - ✅ Port responding
  ✅ Broker 1 - PID: 88416 - Port: 9093 - RUNNING - ✅ Port responding
  ✅ Broker 2 - PID: 73333 - Port: 9094 - RUNNING - ✅ Port responding

==========================================
🐘 ZooKeeper Status:

  ✅ ZooKeeper - PID: 72933 - RUNNING
  ✅ Port 2181 - Responding

==========================================
💾 Disk Usage (Kafka Logs):

  🟡  /System/Volumes/Data: 76% used (49Gi free)

==========================================
===== Test Configuration =====
Test Time: Fri Jan  9 16:32:35 IST 2026
Acks Level: 0
Topic: fault-test
Message Count: 5
Broker to Kill: 1

🔧 Checking broker status...
  ✅ Broker 0 is running
  ✅ Broker 1 is running
  ✅ Broker 2 is running

✅ All 3 brokers are running - ready for test

📊 Getting baseline message count...
📥 Starting consumer with dynamic idle timeout...
  Topic        : fault-test
  Idle Timeout : 3s
  Bootstrap    : localhost:9092,localhost:9093,localhost:9094

⏳ Consuming messages...
  📊 Messages consumed: 100
  📊 Messages consumed: 200
  📊 Messages consumed: 300
  📊 Messages consumed: 400
  📊 Messages consumed: 500
  📊 Messages consumed: 600
  📊 Messages consumed: 700
  📊 Messages consumed: 800
  📊 Messages consumed: 900
  📊 Messages consumed: 1000
  📊 Messages consumed: 1100

⏱️  No messages for 3s - stopping consumer

===== Consumer Summary =====
📊 Total messages : 1149
💾 Output file    : /Users/nc25593_shivanand/kafka-learning-lab/test-results/kafka-consume-1767956557-89278.out

BASELINE 1149
  Current 'acks=0' messages in topic: 1149

🚀 Starting producer (acks=0) in background...
✅ Producer started (PID: 98255)

⏱️  Waiting 5s to send some messages before failure...
⚡ Killing broker 1...
===== Failure Event =====
Time: 16:32:58
Action: Killed broker 1

✅ Broker 1 killed at 16:32:58

⏱️  Waiting for producer to complete...
🚀 Starting producer...
  Topic      : fault-test
  Count      : 5
  Acks       : 0
  Bootstrap  : localhost:9092,localhost:9093,localhost:9094

✅ SUCCESS (1/5): Message 1 at 16:32:51
✅ SUCCESS (2/5): Message 2 at 16:32:52
✅ SUCCESS (3/5): Message 3 at 16:32:54
✅ SUCCESS (4/5): Message 4 at 16:32:56
✅ SUCCESS (5/5): Message 5 at 16:32:58

===== Producer Summary =====
✅ SUCCESS   : 5
⚠️ WARNINGS : 0
❌ FAILED    : 0
📊 Success Rate: 100.0%


⏱️  Waiting 5s for message propagation...
📥 Consuming messages from topic...
📥 Starting consumer with dynamic idle timeout...
  Topic        : fault-test
  Idle Timeout : 3s
  Bootstrap    : localhost:9092,localhost:9093,localhost:9094

⏳ Consuming messages...
⚠️  WARN: [2026-01-09 16:33:07,839] WARN [Consumer clientId=console-consumer, groupId=console-consumer-97491] Connection to node -2 (localhost/127.0.0.1:9093) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
⚠️  WARN: [2026-01-09 16:33:07,839] WARN [Consumer clientId=console-consumer, groupId=console-consumer-97491] Bootstrap broker localhost:9093 (id: -2 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)
  📊 Messages consumed: 100
  📊 Messages consumed: 200
  📊 Messages consumed: 300
  📊 Messages consumed: 400
  📊 Messages consumed: 500
  📊 Messages consumed: 600
  📊 Messages consumed: 700
  📊 Messages consumed: 800
  📊 Messages consumed: 900
  📊 Messages consumed: 1000
  📊 Messages consumed: 1100

⏱️  No messages for 3s - stopping consumer

===== Consumer Summary =====
📊 Total messages : 1154
💾 Output file    : /Users/nc25593_shivanand/kafka-learning-lab/test-results/kafka-consume-1767956587-446.out


==========================================
  Test Results - acks=0
==========================================
📤 Messages Sent: 5
📥 Messages Received: 5
❌ Messages Lost: 0
📊 Loss Percentage: 0%

✅ NO DATA LOSS

===== Test Results =====
Baseline Messages: 1149
Messages Sent: 5
Final Count: 1154
Messages Received (this test): 5
Messages Lost: 0
Loss Percentage: 0%

✅ NO DATA LOSS

⚠️  Reminder: Manually restart broker 1 if needed
   Command: ./scripts/start-broker-1.sh
```
</details>


**💡 Restart broker after test:**
```bash
./scripts/start-broker-1.sh
```

---

### Test 2: acks=1 (Leader Only) for ReplicationFactor: 3    Configs: min.insync.replicas=2

**Hypothesis:** Should lose 0-2 messages if leader dies before replicating.

**Steps:**
```bash
./test-scripts/test-acks-during-failure.sh 1 fault-test 5 0
```

<details>
<summary><strong>Expected Result</strong></summary>

```bash
 ~/kafka-learning-lab │ on main wip !3 ?2  ./test-scripts/test-acks-during-failure.sh 1 fault-test 5 0        ✔ │ took 58s │ at 04:48:11 PM 
==========================================
  Acks Failure Test - acks=1
==========================================
Topic: fault-test
Message Count: 5
Broker to Kill: 0

===== Monitoring Topic: fault-test =====
Running on: Darwin arm64
Press Ctrl+C to stop

========================================== ** ==========================================
  Topic Monitor: fault-test
  Time: 16:49:46
==========================================

📊 Topic Information:
Topic: fault-test       TopicId: DTTOJR5AQcqUUpNxVPkauA PartitionCount: 3       ReplicationFactor: 3    Configs: min.insync.replicas=2,segment.bytes=1073741824
        Topic: fault-test       Partition: 0    Leader: 2       Replicas: 2,0,1 Isr: 2,1,0      Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 1    Leader: 1       Replicas: 1,2,0 Isr: 2,1,0      Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 2    Leader: 1       Replicas: 0,1,2 Isr: 2,1,0      Elr: N/A        LastKnownElr: N/A

  📡 Connected via localhost:9092 (Broker 0)

==========================================
🖥️  Broker Process Status:

  ✅ Broker 0 - PID: 35114 - Port: 9092 - RUNNING - ✅ Port responding
  ✅ Broker 1 - PID: 9878 - Port: 9093 - RUNNING - ✅ Port responding
  ✅ Broker 2 - PID: 73333 - Port: 9094 - RUNNING - ✅ Port responding

==========================================
🐘 ZooKeeper Status:

  ✅ ZooKeeper - PID: 72933 - RUNNING
  ✅ Port 2181 - Responding

==========================================
💾 Disk Usage (Kafka Logs):

  🟡  /System/Volumes/Data: 76% used (49Gi free)

==========================================
===== Test Configuration =====
Test Time: Fri Jan  9 16:49:48 IST 2026
Acks Level: 1
Topic: fault-test
Message Count: 5
Broker to Kill: 0

🔧 Checking broker status...
  ✅ Broker 0 is running
  ✅ Broker 1 is running
  ✅ Broker 2 is running

✅ All 3 brokers are running - ready for test

📊 Getting baseline message count...
📥 Starting consumer with dynamic idle timeout...
  Topic        : fault-test
  Idle Timeout : 3s
  Bootstrap    : localhost:9092,localhost:9093,localhost:9094

⏳ Consuming messages...
  📊 Messages consumed: 100
  📊 Messages consumed: 200
  📊 Messages consumed: 300
  📊 Messages consumed: 400
  📊 Messages consumed: 500
  📊 Messages consumed: 600
  📊 Messages consumed: 700
  📊 Messages consumed: 800
  📊 Messages consumed: 900
  📊 Messages consumed: 1000
  📊 Messages consumed: 1100

⏱️  No messages for 3s - stopping consumer

===== Consumer Summary =====
📊 Total messages : 1159
💾 Output file    : /Users/nc25593_shivanand/kafka-learning-lab/test-results/kafka-consume-1767957590-35971.out

BASELINE 1159
  Current 'acks=1' messages in topic: 1159

🚀 Starting producer (acks=1) in background...
✅ Producer started (PID: 45025)

⏱️  Waiting 5s to send some messages before failure...
⚡ Killing broker 0...
===== Failure Event =====
Time: 16:50:11
Action: Killed broker 0

✅ Broker 0 killed at 16:50:11

⏱️  Waiting for producer to complete...
🚀 Starting producer...
  Topic      : fault-test
  Count      : 5
  Acks       : 1
  Bootstrap  : localhost:9092,localhost:9093,localhost:9094

✅ SUCCESS (1/5): Message 1 at 16:50:04
✅ SUCCESS (2/5): Message 2 at 16:50:06
✅ SUCCESS (3/5): Message 3 at 16:50:07
✅ SUCCESS (4/5): Message 4 at 16:50:09
⚠️ WARN (1/5): Message 5 at 16:50:11
   └─ Kafka warning:
      [2026-01-09 16:50:12,096] WARN [Producer clientId=console-producer] Connection to node -1 (localhost/127.0.0.1:9092) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-09 16:50:12,096] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9092 (id: -1 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)


===== Producer Summary =====
✅ SUCCESS   : 4
⚠️ WARNINGS : 1
❌ FAILED    : 0
📊 Success Rate: 80.0%


⏱️  Waiting 5s for message propagation...
📥 Consuming messages from topic...
📥 Starting consumer with dynamic idle timeout...
  Topic        : fault-test
  Idle Timeout : 3s
  Bootstrap    : localhost:9092,localhost:9093,localhost:9094

⏳ Consuming messages...
  📊 Messages consumed: 100
  📊 Messages consumed: 200
  📊 Messages consumed: 300
  📊 Messages consumed: 400
  📊 Messages consumed: 500
  📊 Messages consumed: 600
  📊 Messages consumed: 700
  📊 Messages consumed: 800
  📊 Messages consumed: 900
  📊 Messages consumed: 1000
  📊 Messages consumed: 1100

⏱️  No messages for 3s - stopping consumer

===== Consumer Summary =====
📊 Total messages : 1164
💾 Output file    : /Users/nc25593_shivanand/kafka-learning-lab/test-results/kafka-consume-1767957620-47023.out


==========================================
  Test Results - acks=1
==========================================
📤 Messages Sent: 5
📥 Messages Received: 5
❌ Messages Lost: 0
📊 Loss Percentage: 0%

✅ NO DATA LOSS

===== Test Results =====
Baseline Messages: 1159
Messages Sent: 5
Final Count: 1164
Messages Received (this test): 5
Messages Lost: 0
Loss Percentage: 0%

✅ NO DATA LOSS

⚠️  Reminder: Manually restart broker 0 if needed
   Command: ./scripts/start-broker-0.sh
```
</details>


**💡 Restart broker:**
```bash
./scripts/start-broker-0.sh
```

---

### Test 2: acks=1 (Leader Only) for ReplicationFactor: 3    Configs: min.insync.replicas=3


<details>
<summary><strong>Expected Result</strong></summary>

```bash

 ~/kafka-learning-lab │ on main wip !3 ?2  ./test-scripts/test-acks-during-failure.sh 1 fault-test 5 0      1 х │ took 49s │ at 05:10:26 PM 
==========================================
  Acks Failure Test - acks=1
==========================================
Topic: fault-test
Message Count: 5
Broker to Kill: 0

===== Monitoring Topic: fault-test =====
Running on: Darwin arm64
Press Ctrl+C to stop

========================================== ** ==========================================
  Topic Monitor: fault-test
  Time: 17:11:29
==========================================

📊 Topic Information:
Topic: fault-test       TopicId: DTTOJR5AQcqUUpNxVPkauA PartitionCount: 3       ReplicationFactor: 3    Configs: min.insync.replicas=3,segment.bytes=1073741824
        Topic: fault-test       Partition: 0    Leader: 2       Replicas: 2,0,1 Isr: 2,1,0      Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 1    Leader: 1       Replicas: 1,2,0 Isr: 2,1,0      Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 2    Leader: 1       Replicas: 0,1,2 Isr: 2,1,0      Elr: N/A        LastKnownElr: N/A

  📡 Connected via localhost:9092 (Broker 0)

==========================================
🖥️  Broker Process Status:

  ✅ Broker 0 - PID: 57128 - Port: 9092 - RUNNING - ✅ Port responding
  ✅ Broker 1 - PID: 9878 - Port: 9093 - RUNNING - ✅ Port responding
  ✅ Broker 2 - PID: 73333 - Port: 9094 - RUNNING - ✅ Port responding

==========================================
🐘 ZooKeeper Status:

  ✅ ZooKeeper - PID: 72933 - RUNNING
  ✅ Port 2181 - Responding

==========================================
💾 Disk Usage (Kafka Logs):

  🟡  /System/Volumes/Data: 77% used (49Gi free)

==========================================
===== Test Configuration =====
Test Time: Fri Jan  9 17:11:31 IST 2026
Acks Level: 1
Topic: fault-test
Message Count: 5
Broker to Kill: 0

🔧 Checking broker status...
  ✅ Broker 0 is running
  ✅ Broker 1 is running
  ✅ Broker 2 is running

✅ All 3 brokers are running - ready for test

📊 Getting baseline message count...
📥 Starting consumer with dynamic idle timeout...
  Topic        : fault-test
  Idle Timeout : 3s
  Bootstrap    : localhost:9092,localhost:9093,localhost:9094

⏳ Consuming messages...
  📊 Messages consumed: 100
  📊 Messages consumed: 200
  📊 Messages consumed: 300
  📊 Messages consumed: 400
  📊 Messages consumed: 500
  📊 Messages consumed: 600
  📊 Messages consumed: 700
  📊 Messages consumed: 800
  📊 Messages consumed: 900
  📊 Messages consumed: 1000
  📊 Messages consumed: 1100

⏱️  No messages for 3s - stopping consumer

===== Consumer Summary =====
📊 Total messages : 1182
💾 Output file    : /Users/nc25593_shivanand/kafka-learning-lab/test-results/kafka-consume-1767958894-58029.out

BASELINE 1182
  Current 'acks=1' messages in topic: 1182

🚀 Starting producer (acks=1) in background...
✅ Producer started (PID: 67225)

⏱️  Waiting 5s to send some messages before failure...
⚡ Killing broker 0...
===== Failure Event =====
Time: 17:11:54
Action: Killed broker 0

✅ Broker 0 killed at 17:11:54

⏱️  Waiting for producer to complete...
🚀 Starting producer...
  Topic      : fault-test
  Count      : 5
  Acks       : 1
  Bootstrap  : localhost:9092,localhost:9093,localhost:9094

✅ SUCCESS (1/5): Message 1 at 17:11:47
✅ SUCCESS (2/5): Message 2 at 17:11:48
✅ SUCCESS (3/5): Message 3 at 17:11:50
✅ SUCCESS (4/5): Message 4 at 17:11:52
⚠️ WARN (1/5): Message 5 at 17:11:54
   └─ Kafka warning:
      [2026-01-09 17:11:54,957] WARN [Producer clientId=console-producer] Connection to node -1 (localhost/127.0.0.1:9092) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-09 17:11:54,957] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9092 (id: -1 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)


===== Producer Summary =====
✅ SUCCESS   : 4
⚠️ WARNINGS : 1
❌ FAILED    : 0
📊 Success Rate: 80.0%


⏱️  Waiting 5s for message propagation...
📥 Consuming messages from topic...
📥 Starting consumer with dynamic idle timeout...
  Topic        : fault-test
  Idle Timeout : 3s
  Bootstrap    : localhost:9092,localhost:9093,localhost:9094

⏳ Consuming messages...
  📊 Messages consumed: 100
  📊 Messages consumed: 200
  📊 Messages consumed: 300
  📊 Messages consumed: 400
  📊 Messages consumed: 500
  📊 Messages consumed: 600
  📊 Messages consumed: 700
  📊 Messages consumed: 800
  📊 Messages consumed: 900
  📊 Messages consumed: 1000
  📊 Messages consumed: 1100

⏱️  No messages for 3s - stopping consumer

===== Consumer Summary =====
📊 Total messages : 1186
💾 Output file    : /Users/nc25593_shivanand/kafka-learning-lab/test-results/kafka-consume-1767958923-69220.out


==========================================
  Test Results - acks=1
==========================================
📤 Messages Sent: 5
📥 Messages Received: 4
❌ Messages Lost: 1
📊 Loss Percentage: 20.0%

❌ DATA LOSS DETECTED

===== Test Results =====
Baseline Messages: 1182
Messages Sent: 5
Final Count: 1186
Messages Received (this test): 4
Messages Lost: 1
Loss Percentage: 20.0%

❌ DATA LOSS DETECTED

⚠️  Reminder: Manually restart broker 0 if needed
   Command: ./scripts/start-broker-0.sh

```
</details>


**💡 Restart broker:**

---

### Test 3: acks=all (Full ISR) for ReplicationFactor: 3    Configs: min.insync.replicas=2

**Steps:**
```bash
./test-scripts/test-acks-during-failure.sh all fault-test 10 2
```


<details>
<summary><strong>Expected Result</strong></summary>

```bash
 ~/kafka-learning-lab │ on main wip !3 ?2  ./test-scripts/test-acks-during-failure.sh all fault-test 5 0                 ✔ │ at 04:54:29 PM 
==========================================
  Acks Failure Test - acks=all
==========================================
Topic: fault-test
Message Count: 5
Broker to Kill: 0

===== Monitoring Topic: fault-test =====
Running on: Darwin arm64
Press Ctrl+C to stop

========================================== ** ==========================================
  Topic Monitor: fault-test
  Time: 16:54:34
==========================================

📊 Topic Information:
Topic: fault-test       TopicId: DTTOJR5AQcqUUpNxVPkauA PartitionCount: 3       ReplicationFactor: 3    Configs: min.insync.replicas=2,segment.bytes=1073741824
        Topic: fault-test       Partition: 0    Leader: 2       Replicas: 2,0,1 Isr: 2,1,0      Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 1    Leader: 1       Replicas: 1,2,0 Isr: 2,1,0      Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 2    Leader: 1       Replicas: 0,1,2 Isr: 2,1,0      Elr: N/A        LastKnownElr: N/A

  📡 Connected via localhost:9092 (Broker 0)

==========================================
🖥️  Broker Process Status:

  ✅ Broker 0 - PID: 66540 - Port: 9092 - RUNNING - ✅ Port responding
  ✅ Broker 1 - PID: 9878 - Port: 9093 - RUNNING - ✅ Port responding
  ✅ Broker 2 - PID: 73333 - Port: 9094 - RUNNING - ✅ Port responding

==========================================
🐘 ZooKeeper Status:

  ✅ ZooKeeper - PID: 72933 - RUNNING
  ✅ Port 2181 - Responding

==========================================
💾 Disk Usage (Kafka Logs):

  🟡  /System/Volumes/Data: 76% used (49Gi free)

==========================================
===== Test Configuration =====
Test Time: Fri Jan  9 16:54:36 IST 2026
Acks Level: all
Topic: fault-test
Message Count: 5
Broker to Kill: 0

🔧 Checking broker status...
  ✅ Broker 0 is running
  ✅ Broker 1 is running
  ✅ Broker 2 is running

✅ All 3 brokers are running - ready for test

📊 Getting baseline message count...
📥 Starting consumer with dynamic idle timeout...
  Topic        : fault-test
  Idle Timeout : 3s
  Bootstrap    : localhost:9092,localhost:9093,localhost:9094

⏳ Consuming messages...
  📊 Messages consumed: 100
  📊 Messages consumed: 200
  📊 Messages consumed: 300
  📊 Messages consumed: 400
  📊 Messages consumed: 500
  📊 Messages consumed: 600
  📊 Messages consumed: 700
  📊 Messages consumed: 800
  📊 Messages consumed: 900
  📊 Messages consumed: 1000
  📊 Messages consumed: 1100

⏱️  No messages for 3s - stopping consumer

===== Consumer Summary =====
📊 Total messages : 1164
💾 Output file    : /Users/nc25593_shivanand/kafka-learning-lab/test-results/kafka-consume-1767957878-67574.out

BASELINE 1164
  Current 'acks=all' messages in topic: 1164

🚀 Starting producer (acks=all) in background...
✅ Producer started (PID: 76841)

⏱️  Waiting 5s to send some messages before failure...
⚡ Killing broker 0...
===== Failure Event =====
Time: 16:54:59
Action: Killed broker 0

✅ Broker 0 killed at 16:54:59

⏱️  Waiting for producer to complete...
🚀 Starting producer...
  Topic      : fault-test
  Count      : 5
  Acks       : all
  Bootstrap  : localhost:9092,localhost:9093,localhost:9094

✅ SUCCESS (1/5): Message 1 at 16:54:52
✅ SUCCESS (2/5): Message 2 at 16:54:54
✅ SUCCESS (3/5): Message 3 at 16:54:56
✅ SUCCESS (4/5): Message 4 at 16:54:57
⚠️ WARN (1/5): Message 5 at 16:54:59
   └─ Kafka warning:
      [2026-01-09 16:55:05,918] WARN [Producer clientId=console-producer] Connection to node 0 (localhost/127.0.0.1:9092) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-09 16:55:11,030] WARN [Producer clientId=console-producer] Got error produce response with correlation id 9 on topic-partition fault-test-2, retrying (1 attempts left). Error: REQUEST_TIMED_OUT. Error Message: Disconnected from node 1 due to timeout (org.apache.kafka.clients.producer.internals.Sender)
[2026-01-09 16:55:16,268] WARN [Producer clientId=console-producer] Got error produce response with correlation id 13 on topic-partition fault-test-2, retrying (0 attempts left). Error: REQUEST_TIMED_OUT. Error Message: Disconnected from node 1 due to timeout (org.apache.kafka.clients.producer.internals.Sender)


===== Producer Summary =====
✅ SUCCESS   : 4
⚠️ WARNINGS : 1
❌ FAILED    : 0
📊 Success Rate: 80.0%


⏱️  Waiting 5s for message propagation...
📥 Consuming messages from topic...
📥 Starting consumer with dynamic idle timeout...
  Topic        : fault-test
  Idle Timeout : 3s
  Bootstrap    : localhost:9092,localhost:9093,localhost:9094

⏳ Consuming messages...
⚠️  WARN: [2026-01-09 16:55:26,235] WARN [Consumer clientId=console-consumer, groupId=console-consumer-14641] Connection to node -1 (localhost/127.0.0.1:9092) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
⚠️  WARN: [2026-01-09 16:55:26,235] WARN [Consumer clientId=console-consumer, groupId=console-consumer-14641] Bootstrap broker localhost:9092 (id: -1 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)
  📊 Messages consumed: 100
  📊 Messages consumed: 200
  📊 Messages consumed: 300
  📊 Messages consumed: 400
  📊 Messages consumed: 500
  📊 Messages consumed: 600
  📊 Messages consumed: 700
  📊 Messages consumed: 800
  📊 Messages consumed: 900
  📊 Messages consumed: 1000
  📊 Messages consumed: 1100

⏱️  No messages for 3s - stopping consumer

===== Consumer Summary =====
📊 Total messages : 1169
💾 Output file    : /Users/nc25593_shivanand/kafka-learning-lab/test-results/kafka-consume-1767957925-78933.out


==========================================
  Test Results - acks=all
==========================================
📤 Messages Sent: 5
📥 Messages Received: 5
❌ Messages Lost: 0
📊 Loss Percentage: 0%

✅ NO DATA LOSS

===== Test Results =====
Baseline Messages: 1164
Messages Sent: 5
Final Count: 1169
Messages Received (this test): 5
Messages Lost: 0
Loss Percentage: 0%

✅ NO DATA LOSS

⚠️  Reminder: Manually restart broker 0 if needed
   Command: ./scripts/start-broker-0.sh
```
</details>

**💡 Restart broker:**
```bash
./scripts/start-broker-0.sh
```


### Test 4: acks=all (Full ISR) for ReplicationFactor: 3    Configs: min.insync.replicas=3



<details>
<summary><strong>Expected Result</strong></summary>

```bash
 ~/kafka-learning-lab │ on main wip !3 ?2  ./test-scripts/test-acks-during-failure.sh all fault-test 5 0                 ✔ │ at 05:05:46 PM 
==========================================
  Acks Failure Test - acks=all
==========================================
Topic: fault-test
Message Count: 5
Broker to Kill: 0

===== Monitoring Topic: fault-test =====
Running on: Darwin arm64
Press Ctrl+C to stop

========================================== ** ==========================================
  Topic Monitor: fault-test
  Time: 17:06:00
==========================================

📊 Topic Information:
Topic: fault-test       TopicId: DTTOJR5AQcqUUpNxVPkauA PartitionCount: 3       ReplicationFactor: 3    Configs: min.insync.replicas=3,segment.bytes=1073741824
        Topic: fault-test       Partition: 0    Leader: 2       Replicas: 2,0,1 Isr: 2,1,0      Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 1    Leader: 1       Replicas: 1,2,0 Isr: 2,1,0      Elr: N/A        LastKnownElr: N/A
        Topic: fault-test       Partition: 2    Leader: 0       Replicas: 0,1,2 Isr: 2,1,0      Elr: N/A        LastKnownElr: N/A

  📡 Connected via localhost:9092 (Broker 0)

==========================================
🖥️  Broker Process Status:

  ✅ Broker 0 - PID: 90033 - Port: 9092 - RUNNING - ✅ Port responding
  ✅ Broker 1 - PID: 9878 - Port: 9093 - RUNNING - ✅ Port responding
  ✅ Broker 2 - PID: 73333 - Port: 9094 - RUNNING - ✅ Port responding

==========================================
🐘 ZooKeeper Status:

  ✅ ZooKeeper - PID: 72933 - RUNNING
  ✅ Port 2181 - Responding

==========================================
💾 Disk Usage (Kafka Logs):

  🟡  /System/Volumes/Data: 77% used (49Gi free)

==========================================
===== Test Configuration =====
Test Time: Fri Jan  9 17:06:02 IST 2026
Acks Level: all
Topic: fault-test
Message Count: 5
Broker to Kill: 0

🔧 Checking broker status...
  ✅ Broker 0 is running
  ✅ Broker 1 is running
  ✅ Broker 2 is running

✅ All 3 brokers are running - ready for test

📊 Getting baseline message count...
📥 Starting consumer with dynamic idle timeout...
  Topic        : fault-test
  Idle Timeout : 3s
  Bootstrap    : localhost:9092,localhost:9093,localhost:9094

⏳ Consuming messages...
  📊 Messages consumed: 100
  📊 Messages consumed: 200
  📊 Messages consumed: 300
  📊 Messages consumed: 400
  📊 Messages consumed: 500
  📊 Messages consumed: 600
  📊 Messages consumed: 700
  📊 Messages consumed: 800
  📊 Messages consumed: 900
  📊 Messages consumed: 1000
  📊 Messages consumed: 1100

⏱️  No messages for 3s - stopping consumer

===== Consumer Summary =====
📊 Total messages : 1169
💾 Output file    : /Users/nc25593_shivanand/kafka-learning-lab/test-results/kafka-consume-1767958565-93263.out

BASELINE 1169
  Current 'acks=all' messages in topic: 1169

🚀 Starting producer (acks=all) in background...
✅ Producer started (PID: 2708)

⏱️  Waiting 5s to send some messages before failure...
⚡ Killing broker 0...
===== Failure Event =====
Time: 17:06:26
Action: Killed broker 0

✅ Broker 0 killed at 17:06:26

⏱️  Waiting for producer to complete...
🚀 Starting producer...
  Topic      : fault-test
  Count      : 5
  Acks       : all
  Bootstrap  : localhost:9092,localhost:9093,localhost:9094

✅ SUCCESS (1/5): Message 1 at 17:06:19
✅ SUCCESS (2/5): Message 2 at 17:06:21
✅ SUCCESS (3/5): Message 3 at 17:06:23
✅ SUCCESS (4/5): Message 4 at 17:06:24
❌ FAILED (1/5): Message 5 at 17:06:26
   └─ Kafka error:
      [2026-01-09 17:06:46,382] WARN [Producer clientId=console-producer] Got error produce response with correlation id 31 on topic-partition fault-test-2, retrying (0 attempts left). Error: NOT_ENOUGH_REPLICAS (org.apache.kafka.clients.producer.internals.Sender)
[2026-01-09 17:06:46,824] ERROR Error when sending message to topic fault-test with key: null, value: 21 bytes with error: (org.apache.kafka.clients.producer.internals.ErrorLoggingCallback)
org.apache.kafka.common.errors.NotEnoughReplicasException: Messages are rejected since there are fewer in-sync replicas than required.


===== Producer Summary =====
✅ SUCCESS   : 4
⚠️ WARNINGS : 0
❌ FAILED    : 1
📊 Success Rate: 80.0%


⏱️  Waiting 5s for message propagation...
📥 Consuming messages from topic...
📥 Starting consumer with dynamic idle timeout...
  Topic        : fault-test
  Idle Timeout : 3s
  Bootstrap    : localhost:9092,localhost:9093,localhost:9094

⏳ Consuming messages...
⚠️  WARN: [2026-01-09 17:06:55,725] WARN [Consumer clientId=console-consumer, groupId=console-consumer-39522] Connection to node -1 (localhost/127.0.0.1:9092) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
⚠️  WARN: [2026-01-09 17:06:55,726] WARN [Consumer clientId=console-consumer, groupId=console-consumer-39522] Bootstrap broker localhost:9092 (id: -1 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)
  📊 Messages consumed: 100
  📊 Messages consumed: 200
  📊 Messages consumed: 300
  📊 Messages consumed: 400
  📊 Messages consumed: 500
  📊 Messages consumed: 600
  📊 Messages consumed: 700
  📊 Messages consumed: 800
  📊 Messages consumed: 900
  📊 Messages consumed: 1000
  📊 Messages consumed: 1100

⏱️  No messages for 3s - stopping consumer

===== Consumer Summary =====
📊 Total messages : 1173
💾 Output file    : /Users/nc25593_shivanand/kafka-learning-lab/test-results/kafka-consume-1767958615-4818.out


==========================================
  Test Results - acks=all
==========================================
📤 Messages Sent: 5
📥 Messages Received: 4
❌ Messages Lost: 1
📊 Loss Percentage: 20.0%

❌ DATA LOSS DETECTED

===== Test Results =====
Baseline Messages: 1169
Messages Sent: 5
Final Count: 1173
Messages Received (this test): 4
Messages Lost: 1
Loss Percentage: 20.0%

❌ DATA LOSS DETECTED

⚠️  Reminder: Manually restart broker 0 if needed
   Command: ./scripts/start-broker-0.sh
```
</details>


**💡 Restart broker:**

---



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
