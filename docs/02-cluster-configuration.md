# Cluster Configuration Deep Dive

> **Purpose**: Comprehensive reference for understanding every configuration parameter in our 3-broker Kafka cluster.  
> **Audience**: Data engineers learning Kafka fundamentals through hands-on local experimentation.  
> **Environment**: macOS M1, 16GB RAM, local development setup.

---

## Quick Navigation

- [Architecture Overview](#architecture-overview)
- [ZooKeeper Configuration](#zookeeper-configuration)
- [Kafka Broker Configuration](#kafka-broker-configuration)
  - [Server Basics](#server-basics)
  - [Socket Server Settings](#socket-server-settings)
  - [Log Basics](#log-basics)
  - [Log Retention Policy](#log-retention-policy)
  - [Replication Settings](#replication-settings)
  - [ZooKeeper Settings](#zookeeper-settings-in-broker)
  - [Group Coordinator Settings](#group-coordinator-settings)
- [Configuration Differences Across Brokers](#configuration-differences-across-brokers)
- [M1 Mac Optimization Tips](#m1-mac-optimization-tips)
- [Common Mistakes & Troubleshooting](#common-mistakes--troubleshooting)
- [What Happens When...](#what-happens-when)
- [Testing Your Configuration](#testing-your-configuration)

---

## Architecture Overview

### Cluster Topology

```
┌─────────────────────────────────────────────────────────────┐
│                        ZooKeeper                            │
│                    localhost:2181                           │
│          (Cluster Metadata & Coordination)                  │
└─────────────┬─────────────┬─────────────┬───────────────────┘
              │             │             │
              │   ┌─────────┴─────────┐   │
              │   │   Registration    │   │
              │   │   & Heartbeats    │   │
              │   └───────────────────┘   │
              │             │             │
    ┌─────────▼─────┐  ┌───▼──────┐  ┌──▼─────────┐
    │   Broker 0    │  │ Broker 1 │  │  Broker 2  │
    │  Port: 9092   │  │Port: 9093│  │Port: 9094  │
    │  ID: 0        │  │ ID: 1    │  │  ID: 2     │
    │               │  │          │  │            │
    │  /tmp/kafka-  │  │ /tmp/    │  │  /tmp/     │
    │  logs-0       │  │ kafka-   │  │  kafka-    │
    │               │  │ logs-1   │  │  logs-2    │
    └───────────────┘  └──────────┘  └────────────┘
           ▲                ▲              ▲
           │                │              │
           └────────────────┴──────────────┘
              Replication (Factor: 2)
```

### Data Flow Example: Topic with 3 Partitions, Replication Factor 2

```
Topic: user-events (3 partitions, replication factor: 2)

Partition 0:  Leader: Broker 0  →  Follower: Broker 1
              └── Stores on: /tmp/kafka-logs-0/user-events-0/
                             /tmp/kafka-logs-1/user-events-0/

Partition 1:  Leader: Broker 1  →  Follower: Broker 2
              └── Stores on: /tmp/kafka-logs-1/user-events-1/
                             /tmp/kafka-logs-2/user-events-1/

Partition 2:  Leader: Broker 2  →  Follower: Broker 0
              └── Stores on: /tmp/kafka-logs-2/user-events-2/
                             /tmp/kafka-logs-0/user-events-2/

┌──────────────────────────────────────────────────────────┐
│  Each broker is both LEADER (for some) and               │
│  FOLLOWER (for others) - distributed leadership!         │
└──────────────────────────────────────────────────────────┘
```

---

## ZooKeeper Configuration

**File**: `config/zookeeper.properties`

### What is ZooKeeper's Role?

```
┌─────────────────────────────────────────────────────────┐
│                    ZooKeeper Manages:                   │
├─────────────────────────────────────────────────────────┤
│  • Broker Registry (which brokers are alive?)           │
│  • Topic Configurations (partitions, replication)       │
│  • Partition Leadership (who's the leader?)             │
│  • Consumer Group Offsets (legacy, pre-0.9)             │
│  • Controller Election (one broker manages cluster)     │
│  • ACLs & Quotas                                        │
└─────────────────────────────────────────────────────────┘
```

<details>
<summary><strong>📂 dataDir=/tmp/zookeeper</strong></summary>

**What it does**: Directory where ZooKeeper stores snapshots and transaction logs.

**Why it matters**: 
- Contains persistent cluster state
- All broker metadata, topic configs, partition assignments stored here
- ⚠️ **Warning**: `/tmp/` is cleared on reboot - production should use `/var/lib/zookeeper`

**Storage Pattern**:
```
/tmp/zookeeper/
├── version-2/
│   ├── snapshot.0           # State snapshots
│   ├── log.1                # Transaction log
│   └── log.2
└── myid                      # ZooKeeper node ID (for ensemble)
```

**Our Setup**: Using `/tmp/` for easy cleanup during learning experiments.

**Test It**:
```bash
# Check ZooKeeper data directory
ls -lah /tmp/zookeeper/version-2/

# Monitor growth during operations
watch -n 2 du -sh /tmp/zookeeper
```

</details>

<details>
<summary><strong>🔌 clientPort=2181</strong></summary>

**What it does**: Port where ZooKeeper listens for client connections.

**Why it matters**:
- Kafka brokers connect on this port
- Standard ZooKeeper port (like 80 for HTTP)
- All 3 brokers connect to `localhost:2181`

**Technical Detail**: 
- This is for client API, not inter-ZooKeeper communication
- In multi-node ZooKeeper ensemble, peer communication uses `2888` (follower) and `3888` (leader election)

**Test It**:
```bash
# Verify ZooKeeper is listening
lsof -i :2181

# Connect to ZooKeeper shell
kafka/bin/zookeeper-shell.sh localhost:2181

# Inside shell, explore structure:
ls /
ls /brokers
ls /brokers/ids
```

</details>

<details>
<summary><strong>🔗 maxClientCnxns=0</strong></summary>

**What it does**: Maximum concurrent connections from single IP (`0` = unlimited).

**Why it matters**:
- Our 3 brokers each maintain 1 connection = 3 total
- Admin tools (kafka-topics.sh, etc.) create temporary connections
- `0` prevents connection limit errors during learning

**Production Consideration**: Set to `60` to prevent connection flooding attacks.

**Test It**:
```bash
# Check which brokers are connected to ZooKeeper
kafka/bin/zookeeper-shell.sh localhost:2181 ls /brokers/ids
# Expected output: [0, 1, 2]

# Check ZooKeeper is listening and accepting connections
lsof -i :2181
# Should show ZooKeeper LISTEN + multiple ESTABLISHED connections

# Count active connections (each broker creates 1 connection)
lsof -i :2181 | grep ESTABLISHED | wc -l
# Expected: 6 (3 from broker side + 3 from ZooKeeper side = bidirectional)

# View connection details
lsof -i :2181 | grep ESTABLISHED
# Shows PID and port pairs for each broker connection
```

**Understanding the Connection Count**:
```
Why 6 connections instead of 3?

TCP connections are bidirectional, so lsof shows both ends:

ZooKeeper side (PID 71112):
  ├─ localhost:2181 → localhost:49381 (Broker 0)
  ├─ localhost:2181 → localhost:49388 (Broker 1) 
  └─ localhost:2181 → localhost:49392 (Broker 2)

Broker side (3 different PIDs):
  ├─ localhost:49381 → localhost:2181 (Broker 0)
  ├─ localhost:49388 → localhost:2181 (Broker 1)
  └─ localhost:49392 → localhost:2181 (Broker 2)

Total: 6 entries in lsof (but actually 3 physical connections)
```

</details>

<details>
<summary><strong>⚙️ admin.enableServer=false</strong></summary>

**What it does**: Disables embedded Jetty HTTP server for admin commands.

**Why it matters**:
- Admin server runs on port 8080 by default
- Provides metrics, health checks, management endpoints
- Disabled to reduce resource usage for learning

**If Enabled, You'd Get**:
```
http://localhost:8080/commands
http://localhost:8080/commands/stat
http://localhost:8080/commands/conf
```

</details>

<details>
<summary><strong>⏱️ tickTime=2000</strong></summary>

**What it does**: Basic time unit (2000ms = 2 seconds) for heartbeats and timeouts.

**Why it matters**:
- Fundamental timing unit in ZooKeeper
- One "tick" = 2 seconds
- Other timeouts are expressed as multiples of `tickTime`

**Example Calculation**:
```
tickTime = 2000ms
initLimit = 10 ticks
Actual timeout = 10 × 2000ms = 20 seconds
```

**Heartbeat Flow**:
```
Client ──[heartbeat]──> ZooKeeper    (every 2 seconds)
        <──[ack]────────

If no heartbeat for (sessionTimeout / tickTime) ticks:
  → Session expires, client considered dead
```

</details>

<details>
<summary><strong>🚀 initLimit=10</strong></summary>

**What it does**: Maximum ticks (10 × 2s = 20s) for follower to initially sync with leader.

**Why it matters**:
- During startup, followers need time to sync state
- If sync takes > 20 seconds → follower marked as failed
- ⚠️ Note: We have 1 ZooKeeper, so this doesn't apply to our setup (good practice to include)

**Formula**: `initLimit_seconds = initLimit × tickTime / 1000`

**Production Scenario**: 
- Large datasets might need `initLimit=20` (40 seconds)
- Fast networks can use `initLimit=5` (10 seconds)

</details>

<details>
<summary><strong>💓 syncLimit=5</strong></summary>

**What it does**: Maximum ticks (5 × 2s = 10s) a follower can lag behind leader during normal operation.

**Why it matters**:
- Heartbeat timeout for in-sync replicas
- If follower doesn't respond within 10s → removed from ensemble
- Prevents slow/failed nodes from blocking cluster

**Difference from initLimit**:
```
initLimit:  For initial data sync (startup)
syncLimit:  For ongoing heartbeats (normal operation)
```

</details>

---

## Kafka Broker Configuration

**Files**: `config/server-0.properties`, `config/server-1.properties`, `config/server-2.properties`

### Broker Responsibilities

```
┌────────────────────────────────────────────────────────┐
│               Kafka Broker Functions                   │
├────────────────────────────────────────────────────────┤
│  1. Storage       │ Write messages to disk (logs)      │
│  2. Serving       │ Handle producer/consumer requests  │
│  3. Replication   │ Leader/follower for partitions     │
│  4. Coordination  │ Register with ZooKeeper            │
└────────────────────────────────────────────────────────┘
```

---

## Server Basics

<details>
<summary><strong>🆔 broker.id=0 (or 1, or 2)</strong></summary>

**What it does**: Unique integer identifier for each broker.

**Why it matters**:
- Distinguishes brokers in the cluster
- Used in partition assignment, leader election, replication
- ZooKeeper tracks brokers by ID

**Our Setup**:
```
Broker 0: broker.id=0
Broker 1: broker.id=1
Broker 2: broker.id=2
```

**Auto-Generation**: If not set, Kafka auto-generates starting from `reserved.broker.max.id + 1` (default 1000).

**Best Practice**: Explicit IDs are clearer for troubleshooting.

**Test It**:
```bash
# Check which brokers are registered
kafka/bin/zookeeper-shell.sh localhost:2181 ls /brokers/ids

# Get broker details
kafka/bin/zookeeper-shell.sh localhost:2181 get /brokers/ids/0
```

</details>

---

## Socket Server Settings

<details>
<summary><strong>🌐 listeners=PLAINTEXT://localhost:9092</strong></summary>

**What it does**: URI where broker listens for connections.

**Format Breakdown**:
```
PLAINTEXT://localhost:9092
    ↓          ↓        ↓
Security   Hostname  Port
Protocol
```

**Why it matters**:
- Producers/consumers connect here to send/receive messages
- Each broker needs unique port
- `localhost` = only local connections (production uses actual hostname/IP)

**Our Setup**:
```
Broker 0: PLAINTEXT://localhost:9092
Broker 1: PLAINTEXT://localhost:9093
Broker 2: PLAINTEXT://localhost:9094
```

**Other Security Protocols**:
```
SSL://              - Encryption only
SASL_PLAINTEXT://   - Authentication only
SASL_SSL://         - Both encryption + authentication
```

**Test It**:
```bash
# Verify broker is listening
lsof -i :9092
lsof -i :9093
lsof -i :9094

# Test connection
telnet localhost 9092
```

</details>

<details>
<summary><strong>📢 advertised.listeners=PLAINTEXT://localhost:9092</strong></summary>

**What it does**: Address published to ZooKeeper for clients to use.

**Why it matters**:
- Client workflow:
  ```
  1. Client → ZooKeeper: "Where are the brokers?"
  2. ZooKeeper → Client: "Here are advertised.listeners"
  3. Client → Broker: Connects using advertised address
  ```

**Critical for Docker/Cloud**:
```
# Container scenario:
listeners=PLAINTEXT://0.0.0.0:9092              # Bind internally
advertised.listeners=PLAINTEXT://kafka1.company.com:9092  # Public address
```

**Our Setup**: Since localhost, both are the same.

**Common Mistake**:
```
❌ listeners=PLAINTEXT://0.0.0.0:9092
   advertised.listeners=PLAINTEXT://0.0.0.0:9092
   
   → Clients can't connect! (0.0.0.0 is not routable)

✅ listeners=PLAINTEXT://0.0.0.0:9092
   advertised.listeners=PLAINTEXT://kafka1.prod.com:9092
```

**Test It**:
```bash
# Get broker metadata (includes advertised listeners)
kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092

# Verify advertised address in ZooKeeper
kafka/bin/zookeeper-shell.sh localhost:2181 get /brokers/ids/0
```

</details>

<details>
<summary><strong>🧵 num.network.threads=3</strong></summary>

**What it does**: Threads handling network I/O (receiving/sending data).

**Why it matters**:
- Handle socket operations (accept, read, write)
- More threads = higher concurrent connection throughput
- Too many → context-switching overhead

**Thread Workflow**:
```
Producer ──┐
           ├─→ [Network Thread 1] ──→ Request Queue
Producer ──┤
           ├─→ [Network Thread 2] ──→ Request Queue
Consumer ──┘
           └─→ [Network Thread 3] ──→ Request Queue
```

**Default**: 3 (good for moderate load)
**Production**: 8-16 for high-throughput scenarios
**M1 Mac**: 3-4 is optimal for local testing

**Test It**:
```bash
# Monitor thread count
jstack <broker_pid> | grep "kafka-network-thread" | wc -l

```

</details>

<details>
<summary><strong>💾 num.io.threads=8</strong></summary>

**What it does**: Threads doing disk I/O (reading/writing log files).

**Why it matters**:
- Handle actual disk operations
- Disk I/O often the bottleneck in Kafka
- Parallelizes disk access across partitions

**I/O Flow**:
```
Request Queue
     ↓
[IO Thread 1] → Write to partition-0 log
[IO Thread 2] → Write to partition-1 log
[IO Thread 3] → Read from partition-2 log
[IO Thread 4] → Write to partition-3 log
     ⋮
[IO Thread 8]
```

**Default**: 8
**Production**: Should ≥ number of disks for optimal parallelization
**M1 Mac SSD**: 6-8 is good (M1 has fast unified storage)

**Tuning for M1**:
```properties
# M1 Mac optimization
num.io.threads=6                    # Slightly lower for single SSD
num.network.threads=4               # Match efficiency cores
```

</details>

<details>
<summary><strong>📨 socket.send.buffer.bytes=102400</strong></summary>

**What it does**: TCP send buffer size (100 KB).

**Why it matters**:
- OS-level buffer for sending data to clients
- Larger buffers = better throughput on high-latency networks
- Trade-off: More memory per connection

**Buffer Behavior**:
```
Broker Memory → [100 KB Send Buffer] → Network → Client
                      ↓
            If buffer fills, slow down!
```

**Default**: 102400 bytes (100 KB)
**Production**: 1-2 MB for high-throughput
**M1 Mac**: Default is fine for local testing

</details>

<details>
<summary><strong>📥 socket.receive.buffer.bytes=102400</strong></summary>

**What it does**: TCP receive buffer size (100 KB).

**Why it matters**:
- Buffers incoming data from clients
- Absorbs bursty traffic
- Prevents dropped packets during spikes

**Default**: 102400 bytes (100 KB)

</details>

<details>
<summary><strong>📦 socket.request.max.bytes=104857600</strong></summary>

**What it does**: Maximum single request size (100 MB).

**Why it matters**:
- Prevents clients from overwhelming broker with huge requests
- Includes message batches + metadata
- Must be > your max message size

**Request Types Limited**:
```
• Produce requests (message batches)
• Fetch requests (consumer reads)
• Metadata requests
```

**Default**: 104857600 bytes (100 MB)
**Production**: Adjust based on message sizes

**Common Issue**:
```
❌ Error: "Message batch size exceeds socket.request.max.bytes"
   
✅ Solution: Increase socket.request.max.bytes OR
             Reduce producer batch.size
```

</details>

---

## Log Basics

> **"Logs" in Kafka = append-only data structures where messages are stored** (NOT debugging logs!)

<details>
<summary><strong>📁 log.dirs=/tmp/kafka-logs-0</strong></summary>

**What it does**: Directory where Kafka stores partition data.

**Why it matters**:
- Actual message data lives here
- Each partition = subdirectory
- **Must be unique per broker** to avoid data corruption

**Directory Structure**:
```
/tmp/kafka-logs-0/
├── user-events-0/              # Partition 0 of topic "user-events"
│   ├── 00000000000000000000.log     # Segment file
│   ├── 00000000000000000000.index   # Offset index
│   ├── 00000000000000000000.timeindex
│   └── leader-epoch-checkpoint
├── user-events-1/
├── __consumer_offsets-0/       # Internal topic
└── meta.properties
```

**Our Setup**:
```
Broker 0: /tmp/kafka-logs-0
Broker 1: /tmp/kafka-logs-1
Broker 2: /tmp/kafka-logs-2
```

**Production Multi-Disk**:
```properties
log.dirs=/disk1/kafka,/disk2/kafka,/disk3/kafka

# Kafka distributes partitions across disks:
/disk1/kafka/topic-0/
/disk2/kafka/topic-1/
/disk3/kafka/topic-2/
```

**⚠️ Warning**: Never point multiple brokers to same log.dirs!

**Test It**:
```bash
# Explore partition structure
ls -lah /tmp/kafka-logs-0/

# Find all partitions for a topic
find /tmp/kafka-logs-* -name "user-events-*" -type d

# Check disk usage
du -sh /tmp/kafka-logs-*
```

</details>

<details>
<summary><strong>📊 num.partitions=3</strong></summary>

**What it does**: Default partitions for new topics (if not specified).

**Why it matters**:
- Partitions = unit of parallelism
- More partitions = more consumer parallelism = higher throughput
- Too many = overhead (more files, more metadata memory)

**Partition Distribution**:
```
Topic: user-events (3 partitions, replication: 2)

Partition 0: Broker 0 (leader), Broker 1 (follower)
Partition 1: Broker 1 (leader), Broker 2 (follower)
Partition 2: Broker 2 (leader), Broker 0 (follower)

Each broker handles different partitions → load balanced!
```

**Our Setup**: 3 partitions matches 3 brokers (good for even distribution).

**Choosing Partition Count**:
```
✅ Good: partition_count = broker_count × N
   (where N = 1, 2, 3... for even distribution)

Examples:
3 brokers → 3, 6, 9, 12 partitions
5 brokers → 5, 10, 15, 20 partitions
```

**Test It**:
```bash
# Create topic with default partitions
kafka/bin/kafka-topics.sh --create \
  --topic test-default \
  --bootstrap-server localhost:9092

# Verify partition count
kafka/bin/kafka-topics.sh --describe \
  --topic test-default \
  --bootstrap-server localhost:9092
```

</details>

<details>
<summary><strong>🔧 num.recovery.threads.per.data.dir=1</strong></summary>

**What it does**: Threads per log directory for startup recovery.

**Why it matters**:
- On broker start, validates/recovers partition logs
- More threads = faster startup after crashes
- Parallelizes across partitions

**Recovery Process**:
```
Broker Startup:
  ↓
[Recovery Thread 1] → Check partition-0 logs
[Recovery Thread 2] → Check partition-1 logs  (if set to 2)
[Recovery Thread 3] → Check partition-2 logs  (if set to 3)
  ↓
Broker Ready!
```

**Default**: 1 (conservative)
**Production**: Set to CPU cores for faster recovery
**M1 Mac**: 4-6 (match performance cores)

</details>

---

## Log Retention Policy

<details>
<summary><strong>⏳ log.retention.hours=168</strong></summary>

**What it does**: Keep messages for 168 hours (7 days) before deletion.

**Why it matters**:
- Kafka doesn't delete after consumption
- Multiple consumers can read same data
- After 7 days, old messages deleted to free space

**Retention Timeline**:
```
Message arrives → Day 0
                  ↓
Consumer reads  → Day 1 (message still exists!)
                  ↓
Another consumer→ Day 3 (message still exists!)
                  ↓
7 days pass     → Day 7 (message deleted)
```

**Priority Hierarchy** (if multiple set):
```
log.retention.ms          (highest priority)
log.retention.minutes
log.retention.hours       (lowest priority)
```

**Use Cases**:
```
Real-time analytics:   log.retention.hours=2
Audit logs:           log.retention.hours=720  (30 days)
Event sourcing:       log.retention.ms=-1      (infinite)
Our learning:         log.retention.hours=168  (7 days)
```

**Test It**:
```bash
# Create topic with custom retention
kafka/bin/kafka-topics.sh --create \
  --topic short-lived \
  --bootstrap-server localhost:9092 \
  --config retention.ms=60000  # 1 minute for testing

# Produce message
echo "test" | kafka/bin/kafka-console-producer.sh \
  --topic short-lived \
  --bootstrap-server localhost:9092

# Wait 61 seconds, then check (message should be gone)
kafka/bin/kafka-console-consumer.sh \
  --topic short-lived \
  --from-beginning \
  --bootstrap-server localhost:9092
```

</details>

<details>
<summary><strong>📄 log.segment.bytes=1073741824</strong></summary>

**What it does**: Max size of single log segment file (1 GB).

**Why it matters**:
- Kafka doesn't use one giant file per partition
- Splits into 1 GB segments
- Retention works on segment granularity

**Segment Structure**:
```
/tmp/kafka-logs-0/user-events-0/
├── 00000000000000000000.log  (1 GB, closed)
├── 00000000000001234567.log  (1 GB, closed)
├── 00000000000002468135.log  (500 MB, active ← writing here)
└── ...

Retention deletes entire segments, not individual messages!
```

**Retention Example**:
```
Segment 1: All messages older than 7 days → DELETED
Segment 2: Mix of old/new messages → KEPT (not deleted yet!)
Segment 3: All new messages → KEPT
```

**Trade-off**:
```
Larger segments (1 GB):
  ✅ Fewer files
  ❌ Coarser retention (might keep old data longer)

Smaller segments (100 MB):
  ✅ Finer-grained retention
  ❌ More files, more overhead
```

**M1 Mac Consideration**: Default 1 GB is fine (M1 SSD handles many files well).


</details>

<details>
<summary><strong>🔄 log.retention.check.interval.ms=300000</strong></summary>

**What it does**: How often (5 minutes) Kafka checks for segments to delete.

**Why it matters**:
- Deletion isn't instant when retention expires
- Background thread checks every 5 minutes
- Balances prompt deletion vs. CPU overhead

**Deletion Timeline**:
```
10:00 AM: Message expires (7 days old)
10:03 AM: Still on disk (next check at 10:05)
10:05 AM: Deletion thread runs → Segment deleted
```

**Production**: Usually fine at default.

</details>

---

## Replication Settings

> **MOST CRITICAL for fault tolerance and data durability!**

### Replication Visualization

```
┌────────────────────────────────────────────────────────┐
│  Topic: payments | 3 partitions | Replication: 2       │
└────────────────────────────────────────────────────────┘

Partition 0:
  ┌─────────────┐  replicates  ┌─────────────┐
  │  Broker 0   │─────────────→│  Broker 1   │
  │  (LEADER)   │              │  (FOLLOWER) │
  │  [WRITE]    │◄─── ack ─────│  [READ-ONLY]│
  └─────────────┘              └─────────────┘
       ↓
  Serves all reads/writes for Partition 0

If Broker 0 fails:
  ┌─────────────┐
  │  Broker 1   │  ← Promoted to LEADER
  │  (NEW LEADER)│     (automatic!)
  └─────────────┘
```

<details>
<summary><strong>🔁 default.replication.factor=2</strong></summary>

**What it does**: New topics get 2 copies of each partition (if not specified).

**Why it matters**:
```
Replication Factor 1:  No fault tolerance (data lost if broker dies)
Replication Factor 2:  Survives 1 broker failure
Replication Factor 3:  Survives 2 broker failures
```

**Formula**: `max_failures_tolerated = replication_factor - 1`

**Our Setup**: Factor 2 with 3 brokers
```
✅ Benefit: Can lose 1 broker, cluster still works
✅ Trade-off: Uses 2× storage
```

**Why Not Factor 3?**
- Demonstrates you can lose 1 broker and still function
- Saves disk space for learning
- In production, factor 3 is recommended

**Storage Impact**:
```
10 GB topic with replication factor 2:
  → Total cluster storage: 20 GB
  
10 GB topic with replication factor 3:
  → Total cluster storage: 30 GB
```

**Test It**:
```bash
# Create topic with explicit replication
kafka/bin/kafka-topics.sh --create \
  --topic critical-data \
  --partitions 3 \
  --replication-factor 2 \
  --bootstrap-server localhost:9092

# Verify replication
kafka/bin/kafka-topics.sh --describe \
  --topic critical-data \
  --bootstrap-server localhost:9092

# Output shows:
# Topic: critical-data  Partition: 0  Leader: 0  Replicas: 0,1  Isr: 0,1
#                       Partition: 1  Leader: 1  Replicas: 1,2  Isr: 1,2
#                       Partition: 2  Leader: 2  Replicas: 2,0  Isr: 2,0
```

</details>

<details>
<summary><strong>🛡️ min.insync.replicas=1</strong></summary>

**What it does**: Minimum replicas that must acknowledge a write (when producer uses `acks=all`).

**Why it matters**: Controls durability vs. availability trade-off.

**Producer Acks Levels**:
```
acks=0:  Fire and forget (no acknowledgment)
         ├─ Fastest
         └─ Can lose data

acks=1:  Leader acknowledges
         ├─ Medium speed
         └─ Data on leader, but might not be replicated

acks=all: Wait for min.insync.replicas
          ├─ Slowest
          └─ Strongest durability
```

**Our Setup**: `min.insync.replicas=1` with `acks=all`
```
Write Flow:
  Producer ──[message]──> Broker 0 (leader)
                          ↓
                     [writes to disk]
                          ↓
  Producer <──[ack]────── Leader (doesn't wait for follower)
                          ↓
                    [async replication to follower]

⚠️ Weak durability! If leader crashes before replication, data lost.
```

**Better Production Setting**:
```properties
default.replication.factor=3
min.insync.replicas=2

# This means:
# - Write succeeds only if leader + at least 1 follower have data
# - Can tolerate 1 broker failure and still accept writes
```

**Trade-off Matrix**:
```
┌─────────────────┬────────────┬──────────────┐
│ min.insync.rep  │ Durability │ Availability │
├─────────────────┼────────────┼──────────────┤
│ 1 (our setup)   │ Weak       │ High         │
│ 2 (recommended) │ Strong     │ Medium       │
│ 3 (paranoid)    │ Strongest  │ Low          │
└─────────────────┴────────────┴──────────────┘
```

**Why Our Setup Uses 1**: 
- Allows writes even if only 1 broker up
- Good for learning/experimentation
- Not recommended for production

**Test It**:
```bash
# Test with acks=all
kafka/bin/kafka-console-producer.sh \
  --topic test \
  --bootstrap-server localhost:9092 \
  --producer-property acks=all

# Stop a broker, verify writes still work (min.insync.replicas=1)
# Stop 2 brokers, writes should fail (only 1 broker left)
```

</details>

<details>
<summary><strong>📝 offsets.topic.replication.factor=2</strong></summary>

**What it does**: Replication for internal `__consumer_offsets` topic.

**Why it matters**:
- Kafka stores consumer group offsets in this special topic
- Tracks "which messages have been consumed"
- If lost, consumers lose their position → re-read everything or skip data

**Offset Storage**:
```
Consumer Group: analytics-team
  └── __consumer_offsets topic stores:
      user-events partition 0: offset 12345
      user-events partition 1: offset 67890
      user-events partition 2: offset 54321
```

**Our Setup**: Replication 2 = survives 1 broker failure.
**Production**: Set to 3 for critical workloads.

**Test It**:
```bash
# Check __consumer_offsets topic
kafka/bin/kafka-topics.sh --describe \
  --topic __consumer_offsets \
  --bootstrap-server localhost:9092

# View consumer offsets
kafka/bin/kafka-consumer-groups.sh --describe \
  --group my-group \
  --bootstrap-server localhost:9092
```

</details>

<details>
<summary><strong>🔒 transaction.state.log.replication.factor=2</strong></summary>

**What it does**: Replication for internal `__transaction_state` topic.

**Why it matters**:
- Used for exactly-once semantics (EOS) transactions
- Stores transaction coordinator state
- Critical for transactional producers/consumers

**When You Need This**:
```
Transactional Producer:
  producer.initTransactions();
  producer.beginTransaction();
  producer.send(record1);
  producer.send(record2);
  producer.commitTransaction();  ← Uses __transaction_state
```

**Production**: Set to 3 for transactional workloads.

</details>

<details>
<summary><strong>🎯 transaction.state.log.min.isr=1</strong></summary>

**What it does**: Minimum in-sync replicas for transaction state topic.

**Why it matters**: Similar to `min.insync.replicas` but specifically for transaction metadata.

**Production**: Set to 2 for stronger guarantees.

</details>

---

## ZooKeeper Settings (in Broker)

<details>
<summary><strong>🔗 zookeeper.connect=localhost:2181</strong></summary>

**What it does**: Connection string to ZooKeeper.

**Format**: `host1:port1,host2:port2,host3:port3/chroot`

**Why it matters**:
- Brokers register here and coordinate cluster operations
- All 3 brokers point to same ZooKeeper

**Our Setup**: Single ZooKeeper on `localhost:2181`

**Production Multi-Node**:
```properties
zookeeper.connect=zk1.prod.com:2181,zk2.prod.com:2181,zk3.prod.com:2181/kafka-prod

# The /kafka-prod is a "chroot" - namespaces Kafka data
```

**Test It**:
```bash
# Verify broker registration
kafka/bin/zookeeper-shell.sh localhost:2181 ls /brokers/ids

# Expected: [0, 1, 2]
```

</details>

<details>
<summary><strong>⏱️ zookeeper.connection.timeout.ms=18000</strong></summary>

**What it does**: Timeout (18 seconds) for establishing ZooKeeper connection.

**Why it matters**:
- If broker can't connect within 18s → fails to start
- Protects against hanging on unreachable ZooKeeper

**Production**: Increase if network is slow/unreliable.

</details>

---

## Group Coordinator Settings

<details>
<summary><strong>⚖️ group.initial.rebalance.delay.ms=0</strong></summary>

**What it does**: Delay before first rebalance when consumer group forms.

**Why it matters**: Prevents multiple rebalances during consumer startup.

**Rebalance Process**:
```
Consumer 1 joins → Kafka waits (delay) for more consumers
Consumer 2 joins → Still waiting...
Consumer 3 joins → Delay expires → ONE rebalance for all 3

vs.

delay=0:
Consumer 1 joins → Rebalance 1
Consumer 2 joins → Rebalance 2
Consumer 3 joins → Rebalance 3  (wasteful!)
```

**Our Setup**: `0` = rebalance immediately (good for development)
**Production**: `3000` (3 seconds) to avoid rebalance storms during rolling restarts

**Test It**:
```bash
# Start consumers with delay to see rebalance behavior
# Terminal 1:
kafka/bin/kafka-console-consumer.sh \
  --topic test \
  --group demo-group \
  --bootstrap-server localhost:9092

# Terminal 2 (wait 5 seconds):
kafka/bin/kafka-console-consumer.sh \
  --topic test \
  --group demo-group \
  --bootstrap-server localhost:9092

# With delay=0: 2 rebalances
# With delay=3000: 1 rebalance (if both start within 3s)
```

</details>

---

## Configuration Differences Across Brokers

**What Changes Between Brokers**:

| Setting | Broker 0 | Broker 1 | Broker 2 | Why Different? |
|---------|----------|----------|----------|----------------|
| `broker.id` | 0 | 1 | 2 | Unique identifier required |
| `listeners` | 9092 | 9093 | 9094 | Can't bind to same port |
| `advertised.listeners` | 9092 | 9093 | 9094 | Clients need distinct addresses |
| `log.dirs` | `/tmp/kafka-logs-0` | `/tmp/kafka-logs-1` | `/tmp/kafka-logs-2` | Prevent data corruption |

**Everything else is identical** to ensure consistent cluster behavior.

---

## M1 Mac Optimization Tips

### Memory Tuning for 16GB RAM

**Broker JVM Settings** (create `kafka/bin/kafka-server-start-optimized.sh`):
```bash
#!/bin/bash
export KAFKA_HEAP_OPTS="-Xmx2G -Xms2G"  # 2GB heap per broker
export KAFKA_JVM_PERFORMANCE_OPTS="-XX:+UseG1GC -XX:MaxGCPauseMillis=20 -XX:InitiatingHeapOccupancyPercent=35"

exec $(dirname $0)/kafka-server-start.sh "$@"
```

**Memory Allocation Strategy** (16GB total):
```
System/macOS:        4 GB
ZooKeeper:          512 MB
Broker 0:             2 GB
Broker 1:             2 GB
Broker 2:             2 GB
Other apps:           3 GB
Buffers/Cache:      2.5 GB
─────────────────────────
Total:               16 GB
```

### Thread Tuning for M1 Architecture

**M1 Pro/Max Configuration**:
```properties
# M1 has 8-10 cores (varies by model)
# Optimize for efficiency + performance cores

num.network.threads=4              # Balance network I/O
num.io.threads=6                   # Leverage fast SSD
num.recovery.threads.per.data.dir=4  # Fast startup
```

### Disk I/O Optimization

**M1 Unified Memory + SSD Benefits**:
```properties
# M1 SSD is extremely fast - can be more aggressive
log.flush.interval.messages=10000  # Flush less frequently
log.flush.interval.ms=1000         # 1 second flush interval
```

**⚠️ Warning**: Only for local testing! Production should rely on OS page cache.

### Monitoring M1 Performance

```bash
# CPU usage per broker
top -pid $(pgrep -f "kafka.Kafka.*server-0")

# Memory pressure
memory_pressure

# Disk I/O
iostat -w 2

# Java heap usage
jstat -gc $(pgrep -f "kafka.Kafka.*server-0") 1000
```

---

## Common Mistakes & Troubleshooting

### ❌ Mistake 1: Setting Replication Factor > Broker Count

```bash
# This WILL FAIL:
kafka/bin/kafka-topics.sh --create \
  --topic test \
  --partitions 3 \
  --replication-factor 5 \  # ❌ Only 3 brokers!
  --bootstrap-server localhost:9092

# Error: Replication factor: 5 larger than available brokers: 3
```

**Fix**: Replication factor ≤ broker count.

---

### ❌ Mistake 2: Forgetting Unique log.dirs

```properties
# server-0.properties
log.dirs=/tmp/kafka-logs

# server-1.properties
log.dirs=/tmp/kafka-logs  # ❌ SAME DIRECTORY!

# Result: Data corruption, brokers fighting over same files
```

**Fix**: Always use unique directories per broker.

---

### ❌ Mistake 3: Using /tmp/ in Production

```bash
# After Mac reboot:
ls /tmp/kafka-logs-0
# ls: /tmp/kafka-logs-0: No such file or directory

# All data GONE! 😱
```

**Fix**: Use permanent storage:
```properties
log.dirs=/var/lib/kafka/data
dataDir=/var/lib/zookeeper
```

---

### ❌ Mistake 4: Not Cleaning Up After Testing

```bash
# After 1 week of testing:
du -sh /tmp/kafka-logs-*
# 50G  /tmp/kafka-logs-0
# 50G  /tmp/kafka-logs-1
# 50G  /tmp/kafka-logs-2
# Total: 150GB on SSD!
```

**Fix**: Regular cleanup script:
```bash
# scripts/cleanup-all.sh
#!/bin/bash
kafka/bin/kafka-server-stop.sh
sleep 5
rm -rf /tmp/kafka-logs-*
rm -rf /tmp/zookeeper
```

---

### ❌ Mistake 5: Port Already in Use

```bash
kafka/bin/kafka-server-start.sh config/server-0.properties
# ERROR: Address already in use (bind failed) (java.net.BindException)
```

**Fix**:
```bash
# Find what's using the port
lsof -i :9092

# Kill old broker process
kill -9 <PID>

# Or use different ports in listeners
```

---

## What Happens When...

### 🔍 What happens when you set replication factor > broker count?

**Scenario**:
```bash
kafka/bin/kafka-topics.sh --create \
  --topic test \
  --replication-factor 5 \  # Only 3 brokers exist
  --bootstrap-server localhost:9092
```

**Result**: ❌ **ERROR: Replication factor exceeds available brokers**

**Why**: Can't create 5 copies with only 3 brokers. Kafka needs unique brokers for each replica.

**Visual**:
```
Need 5 replicas:  [Replica 1] [Replica 2] [Replica 3] [Replica 4] [Replica 5]
Only 3 brokers:   [Broker 0]  [Broker 1]  [Broker 2]  [???]       [???]
                                                        ↑
                                                   Not enough!
```

---

### 🔍 What happens when min.insync.replicas > replication factor?

**Scenario**:
```properties
default.replication.factor=2
min.insync.replicas=3  # ❌ Impossible!
```

**Result**: ✅ Topic creates, but **writes FAIL**:
```
ERROR: NotEnoughReplicasException: Number of insync replicas = 2 < min.insync.replicas = 3
```

**Why**: Can't wait for 3 replicas when only 2 exist.

---

### 🔍 What happens when you stop the leader broker?

**Scenario**:
```bash
# Check current leader
kafka/bin/kafka-topics.sh --describe --topic test --bootstrap-server localhost:9092
# Partition 0: Leader: 0  Replicas: 0,1  Isr: 0,1

# Stop broker 0
kill -9 $(pgrep -f "kafka.Kafka.*server-0")
```

**Result**: ✅ **Automatic failover!**
```
1. Broker 0 dies
2. ZooKeeper detects failure (no heartbeat)
3. Broker 1 elected as new leader (from ISR)
4. Producers/consumers automatically reconnect to Broker 1
5. No data loss (replica had all data)

New state:
# Partition 0: Leader: 1  Replicas: 0,1  Isr: 1
```

**Visual**:
```
Before:
  Broker 0 (LEADER) ──replicates──> Broker 1 (FOLLOWER)
     ↓ (clients write here)
  [Writes]

Broker 0 crashes:
  ❌ Broker 0 (DEAD)    Broker 1 (FOLLOWER)
                             ↓
                       (ZooKeeper promotes)
                             ↓
After:
  ❌ Broker 0 (DEAD)    Broker 1 (NEW LEADER)
                             ↓ (clients now write here)
                         [Writes]
```

---

### 🔍 What happens when all replicas of a partition fail?

**Scenario**: Stop Broker 0 and Broker 1 (both hold replicas of partition 0)

**Result**: 💀 **Partition unavailable**
```
ERROR: LeaderNotAvailableException

Producers: FAIL (can't write)
Consumers: FAIL (can't read)
```

**Recovery**: Start ANY broker with that partition → becomes leader.