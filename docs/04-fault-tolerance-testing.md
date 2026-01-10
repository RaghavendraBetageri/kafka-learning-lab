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

### Setup Consumer Group

```bash
# Create fresh topic for this test
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
GROUP               TOPIC           PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG             CONSUMER-ID                                           HOST            CLIENT-ID
test-consumer-group consumer-test   2          0               0               0               console-consumer-533dc8e2-9ba6-486d-a839-d6377025f816 /127.0.0.1      console-consumer
test-consumer-group consumer-test   0          0               0               0               console-consumer-06902be3-34dd-4cc1-8aed-3e77a4f9ad2e /127.0.0.1      console-consumer
test-consumer-group consumer-test   1          0               0               0               console-consumer-10f94a84-a386-4345-ab81-8ed87a6da4e7 /127.0.0.1      console-consumer%       
```

Each consumer owns 1 partition. ✅

### Produce Test Messages

**Terminal 5:**
```bash
# Produce messages
./test-scripts/produce-messages.sh consumer-test 30 all
```

<details>
<summary><strong>Output</strong></summary>

```bash

🚀 Starting producer...
  Topic      : consumer-test
  Count      : 30
  Acks       : all
  Bootstrap  : localhost:9092,localhost:9093,localhost:9094

✅ SUCCESS (1/30): Message 1 at 15:07:46
✅ SUCCESS (2/30): Message 2 at 15:07:48
✅ SUCCESS (3/30): Message 3 at 15:07:50
✅ SUCCESS (4/30): Message 4 at 15:07:52
✅ SUCCESS (5/30): Message 5 at 15:07:53
✅ SUCCESS (6/30): Message 6 at 15:07:56
✅ SUCCESS (7/30): Message 7 at 15:07:57
✅ SUCCESS (8/30): Message 8 at 15:07:59
✅ SUCCESS (9/30): Message 9 at 15:08:01
✅ SUCCESS (10/30): Message 10 at 15:08:03
✅ SUCCESS (11/30): Message 11 at 15:08:04
✅ SUCCESS (12/30): Message 12 at 15:08:06
✅ SUCCESS (13/30): Message 13 at 15:08:08
✅ SUCCESS (14/30): Message 14 at 15:08:09
✅ SUCCESS (15/30): Message 15 at 15:08:11
✅ SUCCESS (16/30): Message 16 at 15:08:13
✅ SUCCESS (17/30): Message 17 at 15:08:15
✅ SUCCESS (18/30): Message 18 at 15:08:16
✅ SUCCESS (19/30): Message 19 at 15:08:18
✅ SUCCESS (20/30): Message 20 at 15:08:20
✅ SUCCESS (21/30): Message 21 at 15:08:22
✅ SUCCESS (22/30): Message 22 at 15:08:23
✅ SUCCESS (23/30): Message 23 at 15:08:25
✅ SUCCESS (24/30): Message 24 at 15:08:27
✅ SUCCESS (25/30): Message 25 at 15:08:29
✅ SUCCESS (26/30): Message 26 at 15:08:30
✅ SUCCESS (27/30): Message 27 at 15:08:32
✅ SUCCESS (28/30): Message 28 at 15:08:34
✅ SUCCESS (29/30): Message 29 at 15:08:36
✅ SUCCESS (30/30): Message 30 at 15:08:37

===== Producer Summary =====
✅ SUCCESS   : 30
⚠️ WARNINGS : 0
❌ FAILED    : 0
📊 Success Rate: 100.0%

```
</details>

**Watch all 3 consumer terminals** - each should receive ~10 messages.

Outputs:
<details>
<summary><strong>Terminal 1</strong></summary>

```bash
 ~/kafka-learning-lab │ on main wip  kafka/bin/kafka-console-consumer.sh \                                               ✔ │ at 03:02:52 PM 
  --topic consumer-test \
  --bootstrap-server localhost:9092 \
  --group test-consumer-group \
  --property print.partition=true

Partition:2     Message 1 at 15:07:46
Partition:2     Message 2 at 15:07:48
Partition:2     Message 3 at 15:07:50
Partition:2     Message 8 at 15:07:59
Partition:2     Message 16 at 15:08:13
Partition:2     Message 17 at 15:08:15
Partition:2     Message 28 at 15:08:34
```
</details>
<details>
<summary><strong>Terminal 2</strong></summary>

```bash
 ~/kafka-learning-lab │ on main wip !3 ?2  kafka/bin/kafka-console-consumer.sh \
  --topic consumer-test \
  --bootstrap-server localhost:9092 \
  --group test-consumer-group \
  --property print.partition=true

Partition:1     Message 4 at 15:07:52
Partition:1     Message 5 at 15:07:53
Partition:1     Message 7 at 15:07:57
Partition:1     Message 15 at 15:08:11
Partition:1     Message 18 at 15:08:16
Partition:1     Message 20 at 15:08:20
Partition:1     Message 21 at 15:08:22
Partition:1     Message 22 at 15:08:23
Partition:1     Message 23 at 15:08:25
Partition:1     Message 24 at 15:08:27
Partition:1     Message 26 at 15:08:30
```
</details>
<details>
<summary><strong>Terminal 3</strong></summary>

```bash
 ~/kafka-learning-lab │ on main wip  kafka/bin/kafka-console-consumer.sh \                                               ✔ │ at 03:04:48 PM 
  --topic consumer-test \
  --bootstrap-server localhost:9092 \
  --group test-consumer-group \
  --property print.partition=true

Partition:0     Message 6 at 15:07:56
Partition:0     Message 9 at 15:08:01
Partition:0     Message 10 at 15:08:03
Partition:0     Message 11 at 15:08:04
Partition:0     Message 12 at 15:08:06
Partition:0     Message 13 at 15:08:08
Partition:0     Message 14 at 15:08:09
Partition:0     Message 19 at 15:08:18
Partition:0     Message 25 at 15:08:29
Partition:0     Message 27 at 15:08:32
Partition:0     Message 29 at 15:08:36
Partition:0     Message 30 at 15:08:37
```
</details>



### Identify Leader of Partition 0

```bash
kafka/bin/kafka-topics.sh --describe \
  --topic consumer-test \
  --bootstrap-server localhost:9092 | grep "Partition: 0"

# Example output:
Topic: consumer-test    Partition: 0    Leader: 2       Replicas: 2,1,0 Isr: 2,1,0      Elr: N/A        LastKnownElr: N/A
```

### Kill Leader Broker

```bash
# Kill the leader (e.g., broker 2)
pkill -9 -f "server-2.properties"

# Or Ctrl+C in respective Terminal
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

### Produce More Messages When Broker 2 is Inactive

```bash
./test-scripts/produce-messages.sh consumer-test 30 all
```
<details>
<summary><strong>Output</strong></summary>

```bash
 ~/kafka-learning-lab │ on main wip  ./test-scripts/produce-messages.sh consumer-test 30 all                                                                  ✔ │ took 53s │ at 03:08:39 PM 
🚀 Starting producer...
  Topic      : consumer-test
  Count      : 30
  Acks       : all
  Bootstrap  : localhost:9092,localhost:9093,localhost:9094

⚠️ WARN (1/30): Message 1 at 15:24:45
   └─ Kafka warning:
      [2026-01-10 15:24:46,022] WARN [Producer clientId=console-producer] Connection to node -3 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-10 15:24:46,022] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9094 (id: -3 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

⚠️ WARN (2/30): Message 2 at 15:24:47
   └─ Kafka warning:
      [2026-01-10 15:24:47,881] WARN [Producer clientId=console-producer] Connection to node -3 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-10 15:24:47,881] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9094 (id: -3 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

⚠️ WARN (3/30): Message 3 at 15:24:49
   └─ Kafka warning:
      [2026-01-10 15:24:49,892] WARN [Producer clientId=console-producer] Connection to node -3 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-10 15:24:49,893] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9094 (id: -3 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

⚠️ WARN (4/30): Message 4 at 15:24:51
   └─ Kafka warning:
      [2026-01-10 15:24:51,873] WARN [Producer clientId=console-producer] Connection to node -3 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-10 15:24:51,874] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9094 (id: -3 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

⚠️ WARN (5/30): Message 5 at 15:24:52
   └─ Kafka warning:
      [2026-01-10 15:24:53,752] WARN [Producer clientId=console-producer] Connection to node -3 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-10 15:24:53,753] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9094 (id: -3 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

✅ SUCCESS (1/30): Message 6 at 15:24:54
⚠️ WARN (6/30): Message 7 at 15:24:56
   └─ Kafka warning:
      [2026-01-10 15:24:57,206] WARN [Producer clientId=console-producer] Connection to node -3 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-10 15:24:57,207] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9094 (id: -3 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

⚠️ WARN (7/30): Message 8 at 15:24:58
   └─ Kafka warning:
      [2026-01-10 15:24:59,200] WARN [Producer clientId=console-producer] Connection to node -3 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-10 15:24:59,200] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9094 (id: -3 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

⚠️ WARN (8/30): Message 9 at 15:25:00
   └─ Kafka warning:
      [2026-01-10 15:25:01,201] WARN [Producer clientId=console-producer] Connection to node -3 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-10 15:25:01,201] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9094 (id: -3 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

⚠️ WARN (9/30): Message 10 at 15:25:02
   └─ Kafka warning:
      [2026-01-10 15:25:02,943] WARN [Producer clientId=console-producer] Connection to node -3 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-10 15:25:02,944] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9094 (id: -3 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

⚠️ WARN (10/30): Message 11 at 15:25:04
   └─ Kafka warning:
      [2026-01-10 15:25:04,918] WARN [Producer clientId=console-producer] Connection to node -3 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-10 15:25:04,918] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9094 (id: -3 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

⚠️ WARN (11/30): Message 12 at 15:25:06
   └─ Kafka warning:
      [2026-01-10 15:25:06,894] WARN [Producer clientId=console-producer] Connection to node -3 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-10 15:25:06,894] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9094 (id: -3 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

⚠️ WARN (12/30): Message 13 at 15:25:07
   └─ Kafka warning:
      [2026-01-10 15:25:08,732] WARN [Producer clientId=console-producer] Connection to node -3 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-10 15:25:08,732] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9094 (id: -3 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

✅ SUCCESS (2/30): Message 14 at 15:25:09
⚠️ WARN (13/30): Message 15 at 15:25:11
   └─ Kafka warning:
      [2026-01-10 15:25:12,213] WARN [Producer clientId=console-producer] Connection to node -3 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-10 15:25:12,213] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9094 (id: -3 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

✅ SUCCESS (3/30): Message 16 at 15:25:13
⚠️ WARN (14/30): Message 17 at 15:25:15
   └─ Kafka warning:
      [2026-01-10 15:25:15,983] WARN [Producer clientId=console-producer] Connection to node -3 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-10 15:25:15,983] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9094 (id: -3 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

✅ SUCCESS (4/30): Message 18 at 15:25:17
✅ SUCCESS (5/30): Message 19 at 15:25:18
⚠️ WARN (15/30): Message 20 at 15:25:20
   └─ Kafka warning:
      [2026-01-10 15:25:21,479] WARN [Producer clientId=console-producer] Connection to node -3 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-10 15:25:21,479] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9094 (id: -3 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

⚠️ WARN (16/30): Message 21 at 15:25:22
   └─ Kafka warning:
      [2026-01-10 15:25:23,220] WARN [Producer clientId=console-producer] Connection to node -3 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-10 15:25:23,220] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9094 (id: -3 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

⚠️ WARN (17/30): Message 22 at 15:25:24
   └─ Kafka warning:
      [2026-01-10 15:25:24,941] WARN [Producer clientId=console-producer] Connection to node -3 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-10 15:25:24,941] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9094 (id: -3 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

⚠️ WARN (18/30): Message 23 at 15:25:25
   └─ Kafka warning:
      [2026-01-10 15:25:26,757] WARN [Producer clientId=console-producer] Connection to node -3 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-10 15:25:26,757] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9094 (id: -3 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

⚠️ WARN (19/30): Message 24 at 15:25:27
   └─ Kafka warning:
      [2026-01-10 15:25:28,732] WARN [Producer clientId=console-producer] Connection to node -3 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-10 15:25:28,732] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9094 (id: -3 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

⚠️ WARN (20/30): Message 25 at 15:25:29
   └─ Kafka warning:
      [2026-01-10 15:25:30,711] WARN [Producer clientId=console-producer] Connection to node -3 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-10 15:25:30,711] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9094 (id: -3 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

⚠️ WARN (21/30): Message 26 at 15:25:31
   └─ Kafka warning:
      [2026-01-10 15:25:32,583] WARN [Producer clientId=console-producer] Connection to node -3 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-10 15:25:32,583] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9094 (id: -3 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

⚠️ WARN (22/30): Message 27 at 15:25:33
   └─ Kafka warning:
      [2026-01-10 15:25:34,301] WARN [Producer clientId=console-producer] Connection to node -3 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-10 15:25:34,301] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9094 (id: -3 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

⚠️ WARN (23/30): Message 28 at 15:25:35
   └─ Kafka warning:
      [2026-01-10 15:25:36,155] WARN [Producer clientId=console-producer] Connection to node -3 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-10 15:25:36,155] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9094 (id: -3 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

⚠️ WARN (24/30): Message 29 at 15:25:37
   └─ Kafka warning:
      [2026-01-10 15:25:38,161] WARN [Producer clientId=console-producer] Connection to node -3 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-10 15:25:38,161] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9094 (id: -3 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)

⚠️ WARN (25/30): Message 30 at 15:25:39
   └─ Kafka warning:
      [2026-01-10 15:25:40,178] WARN [Producer clientId=console-producer] Connection to node -3 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-01-10 15:25:40,179] WARN [Producer clientId=console-producer] Bootstrap broker localhost:9094 (id: -3 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)


===== Producer Summary =====
✅ SUCCESS   : 5
⚠️ WARNINGS : 25
❌ FAILED    : 0
📊 Success Rate: 16.6%
```
</details>

**All consumers continue receiving messages.** ✅

Outputs:
<details>
<summary><strong>Terminal 1</strong></summary>

```bash
 ~/kafka-learning-lab │ on main wip  kafka/bin/kafka-console-consumer.sh \                                               ✔ │ at 03:02:52 PM 
  --topic consumer-test \
  --bootstrap-server localhost:9092 \
  --group test-consumer-group \
  --property print.partition=true

Partition:2     Message 1 at 15:24:45
Partition:2     Message 5 at 15:24:52
Partition:2     Message 6 at 15:24:54
Partition:2     Message 7 at 15:24:56
Partition:2     Message 13 at 15:25:07
Partition:2     Message 15 at 15:25:11
```
</details>
<details>
<summary><strong>Terminal 2</strong></summary>

```bash
 ~/kafka-learning-lab │ on main wip !3 ?2  kafka/bin/kafka-console-consumer.sh \
  --topic consumer-test \
  --bootstrap-server localhost:9092 \
  --group test-consumer-group \
  --property print.partition=true

Partition:1     Message 9 at 15:25:00
Partition:1     Message 10 at 15:25:02
Partition:1     Message 11 at 15:25:04
Partition:1     Message 12 at 15:25:06
Partition:1     Message 14 at 15:25:09
Partition:1     Message 17 at 15:25:15
Partition:1     Message 18 at 15:25:17
Partition:1     Message 25 at 15:25:29
Partition:1     Message 29 at 15:25:37
Partition:1     Message 30 at 15:25:39
```
</details>
<details>
<summary><strong>Terminal 3</strong></summary>

```bash
 ~/kafka-learning-lab │ on main wip  kafka/bin/kafka-console-consumer.sh \                                               ✔ │ at 03:04:48 PM 
  --topic consumer-test \
  --bootstrap-server localhost:9092 \
  --group test-consumer-group \
  --property print.partition=true

Partition:0     Message 2 at 15:24:47
Partition:0     Message 3 at 15:24:49
[2026-01-10 15:24:50,476] WARN [Consumer clientId=console-consumer, groupId=test-consumer-group] Connection to node 2 (localhost/127.0.0.1:9094) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
Partition:0     Message 4 at 15:24:51
Partition:0     Message 8 at 15:24:58
Partition:0     Message 16 at 15:25:13
Partition:0     Message 19 at 15:25:18
Partition:0     Message 20 at 15:25:20
Partition:0     Message 21 at 15:25:22
Partition:0     Message 22 at 15:25:24
Partition:0     Message 23 at 15:25:25
Partition:0     Message 24 at 15:25:27
Partition:0     Message 26 at 15:25:31
Partition:0     Message 27 at 15:25:33
Partition:0     Message 28 at 15:25:35
```
</details>

### Now See the Leader of Partition 0

```bash
kafka/bin/kafka-topics.sh --describe \
  --topic consumer-test \
  --bootstrap-server localhost:9092 | grep "Partition: 0"

# Example output:
Topic: consumer-test    Partition: 0    Leader: 1       Replicas: 2,1,0 Isr: 1,0        Elr: N/A        LastKnownElr: N/A
```


### Produce More Messages After starting the Broker 2

```bash
./scripts/start-broker-2.sh # Run this is specific terminal
./test-scripts/produce-messages.sh consumer-test 30 all
```

**All consumers continue receiving messages.** ✅

Outputs:
<details>
<summary><strong>Terminal 1</strong></summary>

```bash
Partition:2     Message 1 at 15:35:32
Partition:2     Message 2 at 15:35:33
Partition:2     Message 4 at 15:35:37
Partition:2     Message 6 at 15:35:40
Partition:2     Message 8 at 15:35:44
Partition:2     Message 15 at 15:35:56
Partition:2     Message 20 at 15:36:05
Partition:2     Message 21 at 15:36:06
Partition:2     Message 22 at 15:36:08
Partition:2     Message 25 at 15:36:13
Partition:2     Message 27 at 15:36:17
```
</details>
<details>
<summary><strong>Terminal 2</strong></summary>

```bash
Partition:1     Message 7 at 15:35:42
Partition:1     Message 9 at 15:35:46
Partition:1     Message 11 at 15:35:49
Partition:1     Message 12 at 15:35:51
Partition:1     Message 13 at 15:35:53
Partition:1     Message 26 at 15:36:15
Partition:1     Message 28 at 15:36:19
Partition:1     Message 29 at 15:36:21
Partition:1     Message 30 at 15:36:22
```
</details>
<details>
<summary><strong>Terminal 3</strong></summary>

```bash
Partition:0     Message 3 at 15:35:35
Partition:0     Message 5 at 15:35:39
Partition:0     Message 10 at 15:35:47
Partition:0     Message 14 at 15:35:54
Partition:0     Message 16 at 15:35:58
Partition:0     Message 17 at 15:36:00
Partition:0     Message 18 at 15:36:01
Partition:0     Message 19 at 15:36:03
Partition:0     Message 23 at 15:36:10
Partition:0     Message 24 at 15:36:12
```
</details>

### Now See the Leader of Partition 0

```bash
kafka/bin/kafka-topics.sh --describe \
  --topic consumer-test \
  --bootstrap-server localhost:9092 | grep "Partition: 0"

# Example output:
Topic: consumer-test    Partition: 0    Leader: 2       Replicas: 2,1,0 Isr: 1,0,2      Elr: N/A        LastKnownElr: N/A
```



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
- [ ] Monitoring setup (Ex: Grafana)
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
./scripts/monitor-cluster.sh

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
#or
./scripts/monitor-cluster.sh <topic>

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

# or 
./scripts/monitor-cluster.sh

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
# Universal
./scripts/monitor-cluster.sh
./scripts/monitor-cluster.sh <topic>

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
