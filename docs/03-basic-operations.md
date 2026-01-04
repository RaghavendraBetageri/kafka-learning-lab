# Kafka Basic Operations - Complete Hands-On Guide

Welcome to Apache Kafka learning journey. This guide is designed to take you from the basics to more advanced Kafka concepts, step by step. Every command and example has been tested in the `kafka-learning-lab` setup, so you can safely copy, paste, and run them as you learn.

## What We’ll Be Experimenting With Here

- **Core Operations**: Topics, producers, consumers (the essentials)
- **Intermediate Concepts**: Partition strategies, consumer groups, offset management
- **Advanced Features**: Transactions, log compaction, quotas, throttling
- **Real-World Scenarios**: E-commerce pipeline, fraud detection, analytics
- **Troubleshooting**: Common issues and how to fix them
- **Best Practices**: Production-ready configurations

**Time Investment:** 2-3 hours of hands-on practice.

---

## Quick Navigation

- [Our Learning Scenario](#our-learning-scenario-e-commerce-system)
- [Topic Lifecycle Management](#topic-lifecycle-management)
- [Producing Messages](#producing-messages)
- [Consuming Messages](#consuming-messages)
- [Partition Strategies](#partition-strategies)
- [Message Headers & Metadata](#message-headers--metadata)
- [Offset Management](#offset-management)
- [Advanced Topics](#advanced-topics)
- [Real-World Scenarios](#real-world-scenarios)
- [Troubleshooting Guide](#troubleshooting-guide)
- [Command Reference](#command-reference-cheat-sheet)

---

## Our Learning Scenario: E-Commerce System

To make learning practical and engaging, I’ve built a realistic e-commerce order processing system—similar to what you’d see in Amazon, Flipkart, or any modern online store.

### The Business Flow

```
Customer Places Order
        ↓
    Website Producer
        ↓
    Kafka Topic: "orders"
        ↓
    ┌───────┼───────┼───────┐
    ↓       ↓       ↓       ↓
Inventory Payment Shipping Analytics
Service   Service  Service  Service
```

**What happens in detail:**

1. **Customer** clicks "Buy Now" on website
2. **Website** sends order to Kafka topic
3. **Inventory Service** checks stock availability
4. **Payment Service** processes the transaction
5. **Shipping Service** creates shipping label
6. **Analytics Service** updates sales dashboards

All these services work independently! If payment is slow, inventory isn't affected.

### Topics We'll Create

Throughout this guide, we'll work with these topics:

- `orders` - Main order events (our primary example)
- `payments` - Payment transactions (high-value data)
- `user-activity` - Clickstream/behavior data (high-volume)
- `notifications` - User alerts (fire-and-forget)
- `inventory-updates` - Stock level changes
- `transactions-demo` - For exactly-once semantics
- `compacted-users` - For log compaction examples

---

## Topic Lifecycle Management

### Understanding Topics First

**What's a Topic?**
Think of a topic as a category or folder where related messages live together. Like organizing files in computer!

**Real-world analogy:**
- Topic = WhatsApp Group
- Message = Message in that group
- Partition = Sub-groups within main group (for parallel processing)
- Offset = Message number in sequence

**Key Concepts:**
- **Partition**: Topics are split into partitions for parallelism (think: multiple checkout counters at a store)
- **Replication Factor**: How many copies of data to keep (like saving files on multiple drives)
- **Retention**: How long to keep messages (garbage collection)

### Creating First Topic

Let's start simple and build up complexity!

#### Basic Topic Creation

**What we're doing:** Creating a basic `orders` topic with 3 partitions and replication factor of 2.

```bash
# Navigate to your Kafka learning lab
cd ~/kafka-learning-lab

# Create the orders topic
kafka/bin/kafka-topics.sh --create \
  --topic orders \
  --bootstrap-server localhost:9092 \
  --partitions 3 \
  --replication-factor 2
```

**Expected Output:**
```
Created topic orders.
```

**What just happened? Let's break it down:**

1. **3 Partitions Created**: `orders-0`, `orders-1`, `orders-2`
   - Each partition is like a separate queue
   - More partitions = more parallelism = higher throughput
   
2. **Replication Factor 2**: Each partition has 2 copies
   - 1 leader (handles reads/writes)
   - 1 follower (backup replica)
   - If leader fails, follower takes over automatically

3. **Kafka Distributed the Partitions `kafka/bin/kafka-topics.sh --describe --topic orders --bootstrap-server localhost:9093`**:
      ```bash
      Topic: orders   TopicId: hkSlW-cySde06XDoeu-xig PartitionCount: 3       ReplicationFactor: 2    Configs: min.insync.replicas=1,segment.bytes=1073741824
        Topic: orders   Partition: 0    Leader: 2       Replicas: 0,2   Isr: 2  Elr: N/A        LastKnownElr: N/A
        Topic: orders   Partition: 1    Leader: 2       Replicas: 2,1   Isr: 1,2        Elr: N/A        LastKnownElr: N/A
        Topic: orders   Partition: 2    Leader: 1       Replicas: 1,0   Isr: 1  Elr: N/A        LastKnownElr: N/A
      ```
   Notice how leadership is spread evenly! Smart, right? 🧠

    <details> 
    <summary><strong>Know more about --bootstrap-server</strong></summary>

    **Simple explanation**

    `--bootstrap-server` tells a Kafka client where to find the Kafka cluster.
    Think of it like giving an address so Kafka knows where to knock first.

    **What actually happens**
    When you run:
    ```bash
    --bootstrap-server localhost:9092
    ```
    1. The CLI connects to one broker
    2. That broker shares full cluster details (other brokers, topics, leaders)
    3. The client can now talk to any broker in the cluster
    You only need one reachable broker to get started.

    **Can I use any broker?**
    Yes. These all work the same:
    ```bash
    --bootstrap-server localhost:9092
    --bootstrap-server localhost:9093
    --bootstrap-server localhost:9094
    ```
    Once connected to any one, Kafka discovers the rest.

    **Why use multiple bootstrap servers?**: 
    Production best practice:
    ```bash
    --bootstrap-server localhost:9092,localhost:9093,localhost:9094
    ```
    If one broker is down, Kafka automatically tries the next one.
    This avoids a single point of failure.
    </details>

    <details> 
    <summary><strong>How to delete a topic</strong></summary>

    ```bash
    kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --delete --topic topic_name
    ```
    </details>

**Verify Topic Creation:**
```bash
# List all topics
kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092

# You should see:
# orders
# __consumer_offsets (internal Kafka topic)
```

**Check the Filesystem** (see the actual partition directories):
```bash
# List partition directories
ls -lh /tmp/kafka-logs-*/orders-*

# Example output:
# /tmp/kafka-logs-0/orders-0:
# Permissions Size User              Date Modified Name
# .rw-r--r--@  10M nc25593_shivanand  2 Jan 09:51   00000000000000000000.index
# .rw-r--r--@    0 nc25593_shivanand  2 Jan 09:51   00000000000000000000.log
# .rw-r--r--@  10M nc25593_shivanand  2 Jan 09:51   00000000000000000000.timeindex
# .rw-r--r--@    8 nc25593_shivanand  2 Jan 09:51   leader-epoch-checkpoint
# .rw-r--r--@   43 nc25593_shivanand  2 Jan 09:51   partition.metadata

# /tmp/kafka-logs-0/orders-2:  (follower replica)
# Permissions Size User              Date Modified Name
# .rw-r--r--@  10M nc25593_shivanand  2 Jan 09:51   00000000000000000000.index
# .rw-r--r--@    0 nc25593_shivanand  2 Jan 09:51   00000000000000000000.log
# .rw-r--r--@  10M nc25593_shivanand  2 Jan 09:51   00000000000000000000.timeindex
# .rw-r--r--@    0 nc25593_shivanand  2 Jan 09:51   leader-epoch-checkpoint
# .rw-r--r--@   43 nc25593_shivanand  2 Jan 09:51   partition.metadata

# /tmp/kafka-logs-1/orders-1: 
# .
# ...
# /tmp/kafka-logs-1/orders-2:  (follower replica)
# .
# ...

# /tmp/kafka-logs-2/orders-0:
# .
# ...
# /tmp/kafka-logs-2/orders-1:  (follower replica)
# .
# ...
```

We can literally see where data is stored!

---

#### Topic with Custom Configurations

Now let's get more sophisticated. Different use cases need different configurations. Let's create three topics optimized for different scenarios.

**Scenario 1: Payments Topic (Long Retention for Compliance)**

Financial data needs to be kept for auditing. Let's configure for that:

```bash
kafka/bin/kafka-topics.sh --create \
  --topic payments \
  --bootstrap-server localhost:9092 \
  --partitions 3 \
  --replication-factor 2 \
  --config retention.ms=2592000000 \
  --config min.insync.replicas=2 \
  --config compression.type=lz4
```

**Configuration Breakdown:**

| Config | Value | Why? |
|--------|-------|------|
| `retention.ms=2592000000` | 30 days (in milliseconds) | Keep payment records for a month for compliance and dispute resolution |
| `min.insync.replicas=2` | Both replicas must acknowledge | Can't lose payment data! Both leader and follower must confirm write |
| `compression.type=lz4` | Fast compression | Reduces storage by ~50% and network bandwidth. LZ4 is fast with good compression |

**When to use this config:** Any critical business data - transactions, orders, customer data, audit logs.

---

**Scenario 2: User Activity Topic (Short Retention for Analytics)**

Clickstream data is high-volume but only needed temporarily:

```bash
kafka/bin/kafka-topics.sh --create \
  --topic user-activity \
  --bootstrap-server localhost:9092 \
  --partitions 6 \
  --replication-factor 2 \
  --config retention.ms=86400000 \
  --config segment.ms=3600000
```

**Configuration Breakdown:**

| Config | Value | Why? |
|--------|-------|------|
| `partitions=6` | 6 (more than other topics) | Clickstream = HIGH volume. More partitions = more parallel processing |
| `retention.ms=86400000` | 1 day (24 hours) | Analytics processed daily, don't need historical clicks |
| `segment.ms=3600000` | 1 hour | Close log segments every hour for efficient cleanup |

**When to use this config:** Logs, metrics, temporary event data, IoT sensor readings.

---

**Scenario 3: Notifications Topic (Fire-and-Forget)**

User notifications are consumed quickly and don't need durability:

```bash
kafka/bin/kafka-topics.sh --create \
  --topic notifications \
  --bootstrap-server localhost:9092 \
  --partitions 3 \
  --replication-factor 2 \
  --config retention.ms=3600000 \
  --config min.insync.replicas=1
```

**Configuration Breakdown:**

| Config | Value | Why? |
|--------|-------|------|
| `retention.ms=3600000` | 1 hour | Notifications consumed within minutes, no need to keep long |
| `min.insync.replicas=1` | Only leader needs to ack | Losing occasional notification is acceptable for speed |

**When to use this config:** Real-time notifications, alerts, non-critical updates.

---

**Test Your Configuration:**
```bash
# View detailed config
kafka/bin/kafka-topics.sh --describe \
  --topic payments \
  --bootstrap-server localhost:9092

# Output shows:
# - Partitions and their leaders
# - Replica assignments
# - Custom configs: retention.ms=2592000000, min.insync.replicas=2, compression.type=lz4

Topic: payments TopicId: Gr1EiJAcTK26b_EyIuradA PartitionCount: 3       ReplicationFactor: 2    Configs: compression.type=lz4,min.insync.replicas=2,segment.bytes=1073741824,retention.ms=2592000000
        Topic: payments Partition: 0    Leader: 0       Replicas: 0,2   Isr: 0,2        Elr: N/A        LastKnownElr: N/A
        Topic: payments Partition: 1    Leader: 2       Replicas: 2,1   Isr: 2,1        Elr: N/A        LastKnownElr: N/A
        Topic: payments Partition: 2    Leader: 1       Replicas: 1,0   Isr: 1,0        Elr: N/A        LastKnownElr: N/A
```

---

#### Understanding Partition Count Selection

**The Big Question:** How many partitions should I create?

**Simple Formula:**
```
partitions = (desired_throughput) / (consumer_throughput)
```

**Example:**
- Need 600 MB/s total throughput
- Each consumer processes 100 MB/s
- Partitions needed: 600 ÷ 100 = **6 partitions**

**Trade-off Table:**

| Partition Count | Pros | Cons | Use Case |
|----------------|------|------|----------|
| **Few (1-3)** | Simple ordering, fewer resources | Low parallelism, single consumer bottleneck | Low-traffic topics, strict ordering needed |
| **Medium (3-12)** | Good balance | Balanced for most cases | Most production use cases |
| **Many (50+)** | Maximum parallelism, high throughput | More overhead, complex rebalancing, more files | Very high-traffic systems |

**Rule of Thumb for Your 3-Broker Cluster:**
```bash
# Low traffic (< 10 MB/s)
partitions = 3  # (1× brokers)

# Medium traffic (10-100 MB/s)
partitions = 6  # (2× brokers)

# High traffic (> 100 MB/s)
partitions = 9-12  # (3-4× brokers)
```

**⚠️ Critical Warning:** You can **increase** partitions later, but **CANNOT decrease** without recreating the topic!

**Why can't we decrease partitions?**
Imagine you have user data in partition 5. If you reduce from 6 to 3 partitions, where does partition 5's data go? It's not possible to merge partitions safely. You'd have to:
1. Create new topic with fewer partitions
2. Copy all data
3. Delete old topic

That's why choosing the right number upfront is important!

---

### Listing Topics

Now let's see what topics we have.

```bash
# List all topics
kafka/bin/kafka-topics.sh --list \
  --bootstrap-server localhost:9092
```

**Expected Output:**
```
__consumer_offsets
notifications
orders
payments
user-activity
```

**Understanding Internal Topics:**

- `__consumer_offsets` - Stores consumer group offset commits (where each group is in reading)

This is created automatically by Kafka. Don't delete it!

**Filtering Topics (using shell tools):**
```bash
# Show only user-created topics (exclude internal)
kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092 | grep -v "^__"

# Count total topics
kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092 | wc -l

# Find specific topic pattern
kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092 | grep "order"
```

---

### Describing Topics

Want to see the nitty-gritty details of a topic? Use describe!

```bash
kafka/bin/kafka-topics.sh --describe \
  --topic orders \
  --bootstrap-server localhost:9092
```

**Example Output:**
```
Topic: orders   TopicId: hkSlW-cySde06XDoeu-xig PartitionCount: 3       ReplicationFactor: 2    Configs: min.insync.replicas=1,segment.bytes=1073741824
        Topic: orders   Partition: 0    Leader: 0       Replicas: 0,2   Isr: 2,0        Elr: N/A        LastKnownElr: N/A
        Topic: orders   Partition: 1    Leader: 2       Replicas: 2,1   Isr: 1,2        Elr: N/A        LastKnownElr: N/A
        Topic: orders   Partition: 2    Leader: 1       Replicas: 1,0   Isr: 1,0        Elr: N/A        LastKnownElr: N/A
```

**Let's decode this**

**For Partition 0:**
```
Leader: 0        → Broker 0 handles all reads/writes
Replicas: 0,2    → Data exists on Broker 0 and Broker 1
Isr: 2,0         → Both replicas are in-sync (caught up)
```

**Visual Representation:**
```
Partition 0:
┌──────────────┐  replicates  ┌──────────────┐
│  Broker 0    │─────────────→│  Broker 1    │
│  (LEADER)    │              │  (FOLLOWER)  │
│  ✍️ Writes   │              │  👁️ Reads    │
│  📖 Reads    │              │  backup      │
└──────────────┘              └──────────────┘

Partition 1:
┌──────────────┐  replicates  ┌──────────────┐
│  Broker 2    │─────────────→│  Broker 0    │
│  (LEADER)    │              │  (FOLLOWER)  │
└──────────────┘              └──────────────┘

Partition 2:
┌──────────────┐  replicates  ┌──────────────┐
│  Broker 1    │─────────────→│  Broker 2    │
│  (LEADER)    │              │  (FOLLOWER)  │
└──────────────┘              └──────────────┘
```

**Load Balancing!**
- Each broker is leader for exactly 1 partition
- Leadership is distributed evenly
- No single broker is overloaded

This is Kafka's automatic load balancing in action!

**Understanding ISR (In-Sync Replicas):**

ISR is super important! It tells you which replicas are "healthy" and caught up.

```
Healthy: Isr: 0,1     → Both replicas in sync ✅
Problem: Isr: 0       → Only leader in sync ⚠️
                        Follower is down or lagging!
```

**Check Configuration Only:**
```bash
kafka/bin/kafka-configs.sh --describe \
  --entity-type topics \
  --entity-name payments \
  --bootstrap-server localhost:9092

# Output:
# Dynamic configs for topic payments are:
#   compression.type=lz4 sensitive=false synonyms={DYNAMIC_TOPIC_CONFIG:compression.type=lz4, DEFAULT_CONFIG:compression.type=producer}
#   min.insync.replicas=2 sensitive=false synonyms={DYNAMIC_TOPIC_CONFIG:min.insync.replicas=2, STATIC_BROKER_CONFIG:min.insync.replicas=1, DEFAULT_CONFIG:min.insync.replicas=1}
#   retention.ms=2592000000 sensitive=false synonyms={DYNAMIC_TOPIC_CONFIG:retention.ms=2592000000}
```

**Describe All Topics at Once:**
```bash
# Get details for ALL topics
kafka/bin/kafka-topics.sh --describe \
  --bootstrap-server localhost:9092

# This shows partition distribution across your entire cluster
```

---

### Modifying Topics

Sometimes you need to change topic settings after creation. Let's learn how!

#### Adding Partitions

**When you'd do this:**
- Traffic increased, need more parallelism
- Want to add more consumers to consumer group
- Current partition count is a bottleneck

**Example:**
```bash
# Increase orders topic from 3 to 6 partitions
kafka/bin/kafka-topics.sh --alter \
  --topic orders \
  --partitions 6 \
  --bootstrap-server localhost:9092
```

**⚠️ CRITICAL WARNING - Read This Carefully!**

When you add partitions, the hashing algorithm changes. This breaks ordering for keyed messages!

**Before (3 partitions):**
```
hash("USER-500") % 3 = 1  → Partition 1
All USER-500 messages → Partition 1
```

**After (6 partitions):**
```
hash("USER-500") % 6 = 4  → Partition 4
New USER-500 messages → Partition 4
Old USER-500 messages still in Partition 1
```

**Result:** USER-500's messages are now split across Partition 1 and 4. Ordering broken! 💔

**When it's SAFE to add partitions:**
- ✅ No keys used (round-robin distribution)
- ✅ New topic with no existing data
- ✅ Ordering within key not critical
- ✅ You're willing to lose ordering guarantees

**When to AVOID adding partitions:**
- ❌ Strict ordering by key required
- ❌ Existing messages need to stay with new messages of same key
- ❌ Stateful stream processing (Kafka Streams, ksqlDB)

**Verify the Change:**
```bash
kafka/bin/kafka-topics.sh --describe --topic orders --bootstrap-server localhost:9092

# Should show: PartitionCount: 6
```

---

#### Modifying Topic Configuration

Unlike partitions, configurations can be changed safely!

**Example 1: Change Retention Period**
```bash
# Increase payments retention from 30 to 60 days
kafka/bin/kafka-configs.sh --alter \
  --entity-type topics \
  --entity-name payments \
  --add-config retention.ms=5184000000 \
  --bootstrap-server localhost:9092
```

**Example 2: Enable Compression**
```bash
# Add LZ4 compression to orders topic
kafka/bin/kafka-configs.sh --alter \
  --entity-type topics \
  --entity-name orders \
  --add-config compression.type=lz4 \
  --bootstrap-server localhost:9092
```

**Example 3: Increase Min In-Sync Replicas** (stronger durability):
```bash
# Require both replicas to acknowledge writes
kafka/bin/kafka-configs.sh --alter \
  --entity-type topics \
  --entity-name payments \
  --add-config min.insync.replicas=2 \
  --bootstrap-server localhost:9092
```

**Example 4: Multiple Configs at Once**
```bash
# Change multiple settings together
kafka/bin/kafka-configs.sh --alter \
  --entity-type topics \
  --entity-name user-activity \
  --add-config retention.ms=172800000,segment.ms=3600000,compression.type=snappy \
  --bootstrap-server localhost:9092
```

**Remove Configuration** (revert to broker default):
```bash
kafka/bin/kafka-configs.sh --alter \
  --entity-type topics \
  --entity-name orders \
  --delete-config compression.type \
  --bootstrap-server localhost:9092
```

**Verify Changes:**
```bash
kafka/bin/kafka-configs.sh --describe \
  --entity-type topics \
  --entity-name payments \
  --bootstrap-server localhost:9092

# Check that new configs appear
```

---

### Deleting Topics

Sometimes you need to remove a topic entirely.

**⚠️ EXTREME WARNING:** This is **IRREVERSIBLE**! All messages will be **PERMANENTLY DELETED**!

```bash
# Delete a topic
kafka/bin/kafka-topics.sh --delete \
  --topic test-topic \
  --bootstrap-server localhost:9092
```

**Expected Output:**
```
Topic test-topic is marked for deletion.
Note: This will have no impact if delete.topic.enable is not set to true.
```

**What Happens Behind the Scenes:**

1. Topic marked for deletion in ZooKeeper
2. Brokers stop accepting writes to this topic
3. Partition directories deleted: `/tmp/kafka-logs-*/test-topic-*`
4. Metadata removed from ZooKeeper
5. Process completes (seconds for small topics, minutes for large)

**Verify Deletion:**
```bash
# Topic should disappear from list
kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092

# Filesystem should be clean
ls /tmp/kafka-logs-*/test-topic-* 2>/dev/null || echo "Topic data deleted ✅"
```

**Troubleshooting:** If topic doesn't delete, check broker configuration:
```bash
# In server.properties, ensure this is set:
grep delete.topic.enable ~/kafka-learning-lab/kafka/config/server-0.properties

# Should show: delete.topic.enable=true
```

---

## Producing Messages

Let's send actual data to Kafka.

### Simple String Messages
#### Core Command
```bash
kafka/bin/kafka-console-producer.sh \
  --topic orders \
  --bootstrap-server localhost:9092
```
**Usage**: Type messages line-by-line, press Enter. Each line = 1 message. Exit: `Ctrl+C`

---

#### Key Concepts

#### Sticky Partitioning (Kafka 2.4+)
- **Behavior**: Batches messages together → same partition → better performance
- **Example**: 4 quick messages → all to Partition 2
- **Why**: Reduces network calls, increases throughput
- **Trade-off**: Short-term imbalance for long-term efficiency

#### Message Flow
```
Your Input → Batch → Single Partition → Disk (/tmp/kafka-logs-*/orders-*/)
```

---

#### Verification Commands

#### Check Message Counts (Kafka 3.0+)
```bash
# Recommended
kafka/bin/kafka-get-offsets.sh \
  --bootstrap-server localhost:9092 \
  --topic orders

```

**Output Example**:
```
orders:0:0
orders:2:4    ← 4 messages in Partition 2
orders:5:0
```
Format: `topic:partition:end_offset`

#### View Physical Files
```bash
ls -lh /tmp/kafka-logs-*/orders-*
```

---

#### Producer Properties (Testing vs Production)

| Property | Default | Testing | Production |
|----------|---------|---------|------------|
| `batch.size` | 16384 (16KB) | 100-500 bytes | 32768-65536 bytes |
| `linger.ms` | 0 | 100ms | 10-50ms |
| `compression.type` | none | - | lz4/snappy |
| `acks` | 1 | 1 | all (critical data) |

##### Testing Config (Force Distribution)
```bash
kafka/bin/kafka-console-producer.sh \
  --topic orders \
  --bootstrap-server localhost:9092 \
  --producer-property batch.size=100 \
  --producer-property linger.ms=100
```

#### Production Config (High Throughput)
```bash
kafka/bin/kafka-console-producer.sh \
  --topic orders \
  --bootstrap-server localhost:9092 \
  --producer-property batch.size=32768 \
  --producer-property linger.ms=10 \
  --producer-property compression.type=lz4 \
  --producer-property acks=1
```

---

#### Distribution Testing

#### Test 1: Quick Messages (Sticky Partitioning)
```bash
echo -e "msg1\nmsg2\nmsg3\nmsg4" | kafka/bin/kafka-console-producer.sh \
  --topic orders --bootstrap-server localhost:9092
```
**Result**: All → 1 partition (normal behavior)

#### Test 2: Forced Distribution (600 messages)
```bash
for i in {1..600}; do 
  echo "Message $i"
  sleep 0.01
done | kafka/bin/kafka-console-producer.sh \
  --topic orders \
  --bootstrap-server localhost:9092 \
  --producer-property batch.size=100 \
  --producer-property linger.ms=100
```
**Result**: Even distribution across all partitions (16-18% each)

---

### Producing from a File

Typing messages manually is tedious. Let's batch-send from a file!

**Create Sample Data:**
```bash
cat > /tmp/orders.txt << 'EOL'
Order #1001: User Alice bought laptop for $1200
Order #1002: User Bob bought mouse for $25
Order #1003: User Charlie bought keyboard for $75
Order #1004: User Diana bought monitor for $350
Order #1005: User Eve bought headphones for $150
EOL
```

**Send All Lines to Kafka:**
```bash
kafka/bin/kafka-console-producer.sh \
  --topic orders \
  --bootstrap-server localhost:9092 \
  < /tmp/orders.txt
```

**✅ Done!** All 5 orders sent in one command. Much faster! 🚀

**When to use file input:**
- Bulk data loading
- Testing with realistic volumes
- Replaying historical events
- Migration from other systems

**Verify:**
```bash
# Count should increase by 5
kafka/bin/kafka-get-offsets.sh \
  --bootstrap-server localhost:9092 \
  --topic orders
```

---

### JSON Payloads

In real applications, we use structured JSON data. Let's level up!

**Why JSON?**
- ✅ Structured data (fields, nested objects)
- ✅ Language-agnostic (Python, Java, Node.js all understand)
- ✅ Self-documenting (field names explain meaning)
- ✅ Easily parsed and validated

#### Creating Realistic Order JSON

**E-Commerce Order Structure:**
```json
{
  "order_id": "ORD-1001",
  "user_id": "USER-500",
  "timestamp": "2026-01-01T12:30:00Z",
  "items": [
    {
      "product_id": "LAPTOP-X1",
      "product_name": "Dell XPS 15",
      "quantity": 1,
      "price": 1200.00
    }
  ],
  "total_amount": 1200.00,
  "payment_method": "credit_card",
  "shipping_address": {
    "street": "123 Main St",
    "city": "San Francisco",
    "state": "CA",
    "zip": "94102"
  },
  "status": "pending"
}
```

**Create JSON File with Multiple Orders:**
```bash
cat > /tmp/orders-json.txt << 'EOL'
{"order_id":"ORD-1001","user_id":"USER-500","timestamp":"2026-01-01T12:30:00Z","items":[{"product_id":"LAPTOP-X1","quantity":1,"price":1200.00}],"total_amount":1200.00,"payment_method":"credit_card","status":"pending"}
{"order_id":"ORD-1002","user_id":"USER-501","timestamp":"2026-01-01T12:31:15Z","items":[{"product_id":"MOUSE-M20","quantity":2,"price":25.00}],"total_amount":50.00,"payment_method":"paypal","status":"pending"}
{"order_id":"ORD-1003","user_id":"USER-502","timestamp":"2026-01-01T12:32:30Z","items":[{"product_id":"KEYBOARD-K50","quantity":1,"price":75.00},{"product_id":"MOUSE-M20","quantity":1,"price":25.00}],"total_amount":100.00,"payment_method":"debit_card","status":"pending"}
EOL
```

**⚠️ Important:** Each JSON object must be on a **single line** (no pretty-printing in the file).

**Produce JSON Messages:**
```bash
kafka/bin/kafka-console-producer.sh \
  --topic orders \
  --bootstrap-server localhost:9092 \
  < /tmp/orders-json.txt
```

**Verify JSON Integrity:**
#### Three Methods Overview

| Method | Speed | Use Case | Filtering |
|--------|-------|----------|-----------|
| Partition + Offset | ⚡ Fast | Recent messages, known location | ❌ Manual |
| jq Filter (all JSON) | 🐢 Slower | Find any JSON in topic | ✅ Auto |
| jq Filter (objects) | 🐢 Slower | Find JSON objects only | ✅ Smart |

---

#### Method 1: Specific Partition + Offset (Fastest)

##### Command
```bash
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --partition 3 \
  --offset 95 \
  --bootstrap-server localhost:9092 \
  --max-messages 10
```

##### Finding the Right Offset
```bash
# Step 1: Check end offsets
kafka/bin/kafka-get-offsets.sh --bootstrap-server localhost:9092 --topic orders
# Output: orders:3:98

# Step 2: Calculate starting offset (for last 10 messages)
# 98 - 10 = 88

# Step 3: Read from offset
kafka/bin/kafka-console-consumer.sh --topic orders --partition 3 --offset 88 \
  --bootstrap-server localhost:9092
```

**Pros**: Fast, precise, efficient  
**Cons**: Requires offset calculation, shows mixed content

---

#### Method 2: Filter All Valid JSON (Automatic)

##### Command
```bash
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --from-beginning \
  --bootstrap-server localhost:9092 \
  --timeout-ms 10000 2>/dev/null | \
  jq -R 'fromjson? | select(. != null)' 2>/dev/null
```

**Result**: Shows all valid JSON (including numbers, strings)

##### How It Works
```
Message → jq -R (raw) → fromjson? (try parse) → select (filter) → Output
"text"          ❌ null (filtered out)
"1"             ✅ 1 (JSON primitive, kept)
"{...}"         ✅ {...} (JSON object, kept)
```

**Pros**: Automatic, comprehensive  
**Cons**: Shows JSON primitives (numbers), slower

---

#### Method 3: Filter JSON Objects Only (Recommended)

##### Option A: By Object Type
```bash
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --from-beginning \
  --bootstrap-server localhost:9092 \
  --timeout-ms 10000 2>/dev/null | \
  jq -R 'fromjson? | select(type == "object")' 2>/dev/null
```

##### Option B: By Specific Field (Best)
```bash
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --from-beginning \
  --bootstrap-server localhost:9092 \
  --timeout-ms 10000 2>/dev/null | \
  jq -R 'fromjson? | select(.order_id != null)' 2>/dev/null
```

**Result**: Only JSON objects with `order_id` field

**Pros**: Clean output, field validation  
**Cons**: Slower for large topics

---

#### Advanced jq Techniques

##### Extract Specific Fields
```bash
# Show only order_id and total_amount
... | jq -R 'fromjson? | select(.order_id != null) | {order_id, total_amount}'
```

##### Calculate Total Revenue
```bash
... | jq -R 'fromjson? | select(.order_id != null)' 2>/dev/null | \
  jq -s 'map(.total_amount) | add'
# Output: 1350
```
**Explanation**: `-s` (slurp) → `map()` (extract) → `add` (sum)

##### Filter by Criteria
```bash
# Orders > $100
... | jq -R 'fromjson? | select(.order_id != null and .total_amount > 100)'

# Credit card payments only
... | jq -R 'fromjson? | select(.payment_method == "credit_card")'

# Pending orders
... | jq -R 'fromjson? | select(.status == "pending")'
```

---

#### jq Options Explained

| Option | Purpose | Example |
|--------|---------|---------|
| `-R` | Raw input (read as strings) | `jq -R` |
| `fromjson?` | Try parse JSON (safe) | `fromjson?` (no error on fail) |
| `select()` | Filter condition | `select(.order_id != null)` |
| `type` | Check data type | `type == "object"` |
| `-s` | Slurp (array of all) | `jq -s 'map(...) \| add'` |
| `map()` | Transform array | `map(.total_amount)` |


---

#### Message Size Considerations

**Kafka Message Size Limits:**
- Default max: **1 MB** (1,048,576 bytes)
- Can increase up to ~100 MB (not recommended)

**Why Size Matters:**

**Small Messages (< 10 KB):**
- ✅ Fast network transfer
- ✅ Low latency
- ✅ Efficient batching
- ✅ Better throughput

**Large Messages (> 1 MB):**
- ❌ Slow network transfer
- ❌ Higher latency
- ❌ Memory pressure on brokers
- ❌ Client memory issues
- ⚠️ Requires configuration changes

**Check Your Message Size:**
```bash
# Count bytes in JSON message
echo | cat /tmp/orders-json.txt | wc -c

# 701 bytes (well within limits!)
```

**If You Need Large Messages:**

Update broker config (in `server.properties`):
```properties
message.max.bytes=10485760  # 10 MB
```

Update producer:
```bash
kafka/bin/kafka-console-producer.sh \
  --topic large-files \
  --bootstrap-server localhost:9092 \
  --producer-property max.request.size=10485760
```

**🎯 Best Practice - Don't Store Blobs in Kafka!**

Instead of embedding large files:
```json
{
  "order_id": "ORD-1001",
  "invoice_pdf": "<base64-encoded-pdf-data-5MB>"  // ❌ BAD!
}
```

Store references instead:
```json
{
  "order_id": "ORD-1001",
  "invoice_url": "s3://invoices/ord-1001.pdf",  // ✅ GOOD!
  "thumbnail_url": "s3://thumbnails/ord-1001.jpg"
}
```

This keeps Kafka fast and messages small!

---

### Messages with Keys

Now we get to one of Kafka's most powerful features - **message keys**!

#### Why Keys Matter

**The Problem Without Keys:**

Imagine sending these 3 messages for USER-500:
```
Message A: Add laptop to cart
Message B: Add mouse to cart
Message C: Checkout
```

**Without keys**, they might go to different partitions:
```
Partition 0: Message B (Add mouse)
Partition 1: Message C (Checkout)
Partition 2: Message A (Add laptop)
```

Consumer might process them as: **B → C → A**

User checks out BEFORE adding laptop! 😱 Cart is wrong!

**The Solution With Keys:**

Use `user_id` as key. All messages with same key → same partition → guaranteed order!

```
Key = "USER-500"
↓
All messages → Partition 1
↓
Consumer reads in order: A → B → C ✅
```

#### How Kafka Chooses Partitions

**The Hashing Magic:**
```
partition = hash(key) % number_of_partitions
```

**Example:**
```
Key: "USER-500"
Hash: MurmurHash("USER-500") = 1847382910
Partition: 1847382910 % 3 = 1
→ Always goes to Partition 1!
```

**Properties:**
- ✅ **Deterministic**: Same key always → same partition
- ✅ **Uniform distribution**: Hash spreads keys evenly
- ✅ **Sticky**: Partition doesn't change (unless you add partitions!)

#### Producing Messages with Keys

**Start Producer with Key Support:**
```bash
kafka/bin/kafka-console-producer.sh \
  --topic orders \
  --bootstrap-server localhost:9092 \
  --property parse.key=true \
  --property key.separator=:
```

**Now type messages in `key:value` format:**
```
>USER-500:{"order_id":"ORD-1001","user_id":"USER-500","action":"add_to_cart","item":"laptop","amount":1200.00}
>USER-501:{"order_id":"ORD-1002","user_id":"USER-501","action":"add_to_cart","item":"mouse","amount":50.00}
>USER-500:{"order_id":"ORD-1003","user_id":"USER-500","action":"add_to_cart","item":"mouse","amount":25.00}
>USER-502:{"order_id":"ORD-1004","user_id":"USER-502","action":"checkout","amount":350.00}
>USER-500:{"order_id":"ORD-1005","user_id":"USER-500","action":"checkout","total":1225.00}
>^C
```

**What Just Happened:**

```
USER-500 messages:
  ├─ ORD-1001 → hash("USER-500") % 3 = Partition 1
  ├─ ORD-1003 → hash("USER-500") % 3 = Partition 1
  └─ ORD-1005 → hash("USER-500") % 3 = Partition 1
  ✅ All in same partition, guaranteed order!

USER-501 messages:
  └─ ORD-1002 → hash("USER-501") % 3 = Partition 0

USER-502 messages:
  └─ ORD-1004 → hash("USER-502") % 3 = Partition 2
```

**Verify Partition Assignment:**
```bash
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --from-beginning \
  --bootstrap-server localhost:9092 \
  --property print.key=true \
  --property print.partition=true \
  --property key.separator=" | " \
  --max-messages 5

# Example output:
# Partition:1 | USER-500 | {"order_id":"ORD-1001",...}
# Partition:0 | USER-501 | {"order_id":"ORD-1002",...}
# Partition:1 | USER-500 | {"order_id":"ORD-1003",...}  ← Same partition!
# Partition:2 | USER-502 | {"order_id":"ORD-1004",...}
# Partition:1 | USER-500 | {"order_id":"ORD-1005",...}  ← Same partition!
```

Perfect! All USER-500 messages in Partition 1!

---

#### Key Selection Strategies

Different use cases need different keys. Here are proven patterns:

**Strategy 1: User ID (Most Common)**
```bash
# Key = user_id
USER-12345:{"event":"login","timestamp":"2026-01-01T10:00:00Z"}
USER-12345:{"event":"add_to_cart","product_id":"LAPTOP-X1"}
USER-12345:{"event":"checkout","total":1200.00}
```
- ✅ **Benefit**: All user actions processed in order
- ✅ **Use Case**: User session tracking, shopping cart state, user behavior analysis

**Strategy 2: Order ID (Transaction Processing)**
```bash
# Key = order_id
ORD-1001:{"status":"created","user_id":"USER-500"}
ORD-1001:{"status":"payment_processing"}
ORD-1001:{"status":"shipped","tracking":"ABC123"}
ORD-1001:{"status":"delivered"}
```
- ✅ **Benefit**: Order lifecycle events stay together
- ✅ **Use Case**: Order status updates, workflow orchestration, state machines

**Strategy 3: Device ID (IoT)**
```bash
# Key = device_id
SENSOR-001:{"temperature":22.5,"humidity":45}
SENSOR-001:{"temperature":22.7,"humidity":46}
SENSOR-001:{"temperature":22.3,"humidity":44}
```
- ✅ **Benefit**: All readings from device in order
- ✅ **Use Case**: Sensor data, anomaly detection, time-series analysis

**Strategy 4: Account ID (Financial)**
```bash
# Key = account_id
ACC-500:{"type":"deposit","amount":1000.00,"balance":5000.00}
ACC-500:{"type":"withdrawal","amount":200.00,"balance":4800.00}
ACC-500:{"type":"deposit","amount":500.00,"balance":5300.00}
```
- ✅ **Benefit**: Account balance calculations always correct
- ✅ **Use Case**: Banking systems, ledger, double-entry bookkeeping

**Strategy 5: No Key (High Throughput)**
```bash
# No key → round-robin distribution
{"log_level":"INFO","message":"System started"}
{"log_level":"DEBUG","message":"Processing request"}
{"log_level":"INFO","message":"Request completed"}
```
- ✅ **Benefit**: Maximum parallelism, even distribution
- ✅ **Use Case**: Logs, metrics, independent events, stateless processing

---

#### ⚠️ What Breaks Ordering

Remember our warning about adding partitions? Here's the detailed impact:

**Original Setup (3 partitions):**
```
hash("USER-500") % 3 = 1 → Partition 1
```

**After Adding Partitions (now 6):**
```
hash("USER-500") % 6 = 4 → Partition 4
```

**Impact:**
```
Old messages (USER-500):  Partition 1
New messages (USER-500):  Partition 4
↓
Messages split across partitions!
↓
Ordering broken for USER-500!
```

**When to Use Keys vs. No Keys:**

| Scenario | Use Key? | Why |
|----------|----------|-----|
| User shopping cart | ✅ Yes (user_id) | Must process actions in order |
| Financial transactions | ✅ Yes (account_id) | Balance must be calculated correctly |
| Click stream analytics | ❌ No key | Don't care about order, want maximum throughput |
| Application logs | ❌ No key | Independent events, order doesn't matter |
| IoT sensor data | ✅ Yes (device_id) | Detect anomalies in sensor readings |

---

### Batch Production

For high throughput, we need batching! Let's optimize performance.

#### Understanding Batching

**Without Batching (inefficient):**
```
Message 1 → Network → Broker  (1 network call)
Message 2 → Network → Broker  (1 network call)
Message 3 → Network → Broker  (1 network call)
Total: 3 network round-trips
```

**With Batching (efficient):**
```
[Message 1, Message 2, Message 3] → Network → Broker
Total: 1 network round-trip
Result: 3× fewer network calls = Much higher throughput! 🚀
```

#### Default Console Producer

```bash
# Basic producer (no explicit batching)
kafka/bin/kafka-console-producer.sh \
  --topic orders \
  --bootstrap-server localhost:9092

# Each line sent separately (inefficient for bulk)
```

#### Optimized Batch Producer

```bash
kafka/bin/kafka-console-producer.sh \
  --topic orders \
  --bootstrap-server localhost:9092 \
  --producer-property batch.size=32768 \
  --producer-property linger.ms=10 \
  --producer-property compression.type=lz4
```

**Configuration Breakdown:**

| Property | Value | What It Does |
|----------|-------|--------------|
| `batch.size=32768` | 32 KB | Wait until 32 KB of messages accumulated before sending |
| `linger.ms=10` | 10 ms | Wait up to 10ms for more messages (trade latency for throughput) |
| `compression.type=lz4` | LZ4 compression | Compress batch before sending (reduces network) |

**Trade-off Visualization:**
```
┌───────────────────────────────────────────────┐
│ batch.size=16KB, linger.ms=0 (default)        │
│ [M1] → send immediately                       │
│ [M2] → send immediately                       │
│ [M3] → send immediately                       │
│ Result: Low latency (~1ms), lower throughput  │
└───────────────────────────────────────────────┘

┌───────────────────────────────────────────────┐
│ batch.size=32KB, linger.ms=10                 │
│ [M1, M2, M3, M4] → wait 10ms or 32KB → send  │
│ Result: Higher latency (~10ms), much higher   │
│         throughput (3-5× improvement!)        │
└───────────────────────────────────────────────┘
```

**When to Use Batching:**

✅ **Good for:**
- Bulk data ingestion (logs, events, ETL)
- High-throughput scenarios (analytics, monitoring)
- Network bandwidth limited environments
- Cost optimization (fewer network calls)

❌ **Bad for:**
- Ultra-low latency requirements (< 5ms)
- Real-time trading systems
- Interactive applications (chat, notifications)

#### Testing Batch Performance

Let's measure the difference!

**Generate Test Data:**
```bash
# Create 10,000 test messages
for i in {1..10000}; do
  echo "Message $i: timestamp=$(date +%s)"
done > /tmp/bulk-test.txt
```

**Measure WITHOUT Batching:**
```bash
time kafka/bin/kafka-console-producer.sh \
  --topic test-batch \
  --bootstrap-server localhost:9092 \
  < /tmp/bulk-test.txt
```

**Measure WITH Batching:**
```bash
time kafka/bin/kafka-console-producer.sh \
  --topic test-batch \
  --bootstrap-server localhost:9092 \
  --producer-property batch.size=65536 \
  --producer-property linger.ms=10 \
  --producer-property compression.type=lz4 \
  < /tmp/bulk-test.txt
```

**Result:** Batching is 1.5-2× faster!

---

## Consuming Messages

Now let's read the messages we've been producing!

### Basic Consumption

#### Reading from Beginning

Want to see ALL historical messages? Use `--from-beginning`:

```bash
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --from-beginning \
  --bootstrap-server localhost:9092
```

**What Happens:**
1. Consumer connects to all the partitions
2. Starts reading from offset 0 (first message ever)
3. Shows ALL historical messages
4. Continues tailing for new messages (stays open)
5. Press `Ctrl+C` to stop

**Example Output:**
```
Order received: laptop, 1200
Order received: mouse, 25
{"order_id":"ORD-1001","user_id":"USER-500",...}
{"order_id":"ORD-1002","user_id":"USER-501",...}
^CProcessed a total of 8 messages
```

**Understanding Offsets:**
```
Partition 0: [Msg@0] [Msg@1] [Msg@2] [Msg@3]
              ↑                           ↑
           offset 0                   offset 3

--from-beginning starts here ↑
```

---

#### Reading Only New Messages

Don't want history? Omit `--from-beginning`:

```bash
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --bootstrap-server localhost:9092
```

**What Happens:**
1. Consumer starts from **latest offset** (end of log)
2. Ignores all historical messages
3. Waits for NEW messages
4. Shows them as they arrive

**Live Demo:**

**Terminal 1 - Start Consumer:**
```bash
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --bootstrap-server localhost:9092

# Waiting for messages...
```

**Terminal 2 - Send Message:**
```bash
echo "New order: tablet, $500" | \
kafka/bin/kafka-console-producer.sh \
  --topic orders \
  --bootstrap-server localhost:9092
```

**Terminal 1 - Instantly Shows:**
```
New order: tablet, $500
```

Real-time!

---

#### Consuming Limited Messages

Don't want to read forever? Limit the count:

```bash
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --from-beginning \
  --max-messages 5 \
  --bootstrap-server localhost:9092
```

**Output (first 5 messages only):**
```
Message 1
Message 2
Message 3
Message 4
Message 5
Processed a total of 5 messages
```

Then consumer exits automatically.

**Use Cases:**
- ✅ Quick sampling ("show me 10 examples")
- ✅ Testing without terminal spam
- ✅ Data quality checks
- ✅ Debugging specific messages

---

#### Consuming with Full Metadata

Want to see EVERYTHING about each message?

```bash
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --from-beginning \
  --bootstrap-server localhost:9092 \
  --property print.key=true \
  --property print.partition=true \
  --property print.offset=true \
  --property print.timestamp=true \
  --property key.separator=" | " \
  --max-messages 3
```

**Rich Output:**
```
Partition:1 Offset:0 CreateTime:1735728630000 Key:USER-500 | {"order_id":"ORD-1001",...}
Partition:1 Offset:1 CreateTime:1735728635000 Key:USER-500 | {"order_id":"ORD-1003",...}
Partition:0 Offset:0 CreateTime:1735728632000 Key:USER-501 | {"order_id":"ORD-1002",...}
```

**Metadata Breakdown:**
- **Partition:1** → Message stored in partition 1
- **Offset:0** → First message in that partition
- **CreateTime:1735728630000** → Timestamp (Unix epoch ms)
- **Key:USER-500** → Message key (for routing)
- **Value:** → Actual JSON payload

**Convert Timestamp to Human-Readable:**
```bash
# On macOS
date -r $((1735728630000 / 1000))

# On Linux
date -d @$((1735728630000 / 1000))

# Output: Wed Jan  1 12:30:30 IST 2026
```

---

#### Pretty-Printing JSON

Make JSON readable with `jq`:

```bash
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --from-beginning \
  --max-messages 1 \
  --bootstrap-server localhost:9092 | jq .
```

**Beautiful Output:**
```json
{
  "order_id": "ORD-1002",
  "user_id": "USER-501",
  "action": "add_to_cart",
  "item": "mouse",
  "amount": 50.00
}
```

**Filter Specific Fields:**
```bash
# Show only order_id and total_amount
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --from-beginning \
  --max-messages 1 \
  --bootstrap-server localhost:9092 | jq '{order_id, amount, unlisted_field}'

# Output:
{
  "order_id": "ORD-1002",
  "amount": 50.00,
  "unlisted_field": null
}
```

**Aggregate Data:**
```bash
# Calculate total revenue from all orders
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --from-beginning \
  --max-messages 2 \
  --bootstrap-server localhost:9092 | jq -s 'map(.amount) | add'

# Output: 
Processed a total of 2 messages
1225
```

---

### Consumer Groups

Now we get to Kafka's superpower - **Consumer Groups**!

#### What is a Consumer Group?

**Definition:** A consumer group is a set of consumers that work together as a team to consume a topic.

**Key Properties:**
1. Each partition consumed by **exactly one** consumer in the group
2. Multiple groups can consume the same topic **independently**
3. Kafka tracks offset **per group** (not per consumer)

**Visual Example:**

```
Topic: orders (3 partitions)

Consumer Group "inventory-service":
┌──────────────┐
│  Consumer A  │ → reads Partition 0
│  Consumer B  │ → reads Partition 1
│  Consumer C  │ → reads Partition 2
└──────────────┘
Group offsets:
  - Partition 0: offset 145
  - Partition 1: offset 203
  - Partition 2: offset 178

Consumer Group "analytics-service":
┌──────────────┐
│  Consumer X  │ → reads ALL partitions (0, 1, 2)
└──────────────┘
Group offsets:
  - Partition 0: offset 98  ← Different from inventory!
  - Partition 1: offset 150
  - Partition 2: offset 120

✅ Same topic, same messages
✅ Each group at different position
✅ Groups don't affect each other!
```

**Real-World Analogy:**

Think of a newspaper (topic):
- **Family Group** (inventory-service): Dad reads sports, Mom reads business, Kid reads comics
- **Office Group** (analytics-service): Boss reads entire paper alone

Both groups reading same newspaper, but:
- Different reading patterns
- Different pace
- Independent progress tracking

---

#### Creating and Using Consumer Groups

**Start Consumer with Group:**
```bash
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --group inventory-service \
  --bootstrap-server localhost:9092
```

**What Happens:**
1. Consumer joins group "inventory-service"
2. If group is **new** → starts from latest offset (ignores history)
3. If group **exists** → resumes from last committed offset
4. Kafka assigns partitions to this consumer
5. Consumer starts reading

**First-Time (New Group):**
```bash
# New group starts from latest (no history)
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --group fresh-group \
  --bootstrap-server localhost:9092

# Only shows NEW messages going forward
```

**Resuming (Existing Group):**
```bash
# Group previously read 50 messages
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --group existing-group \
  --bootstrap-server localhost:9092

# Resumes from message 51 (where it left off!)
```

**Force Read from Beginning (Even for Existing Group):**

First, reset the group offsets:
```bash
# Stop all consumers in the group first!

# Reset to beginning
kafka/bin/kafka-consumer-groups.sh --reset-offsets \
  --group inventory-service \
  --topic orders \
  --to-earliest \
  --execute \
  --bootstrap-server localhost:9092
```

Now start consumer:
```bash
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --group inventory-service \
  --bootstrap-server localhost:9092

# Reads from beginning now!
```

---

#### List All Consumer Groups

```bash
kafka/bin/kafka-consumer-groups.sh --list \
  --bootstrap-server localhost:9092

# Example output:
# inventory-service
# existing-group
```

---

#### Describe Consumer Group (The Power Command!)

This is THE command for monitoring consumers:

```bash
kafka/bin/kafka-consumer-groups.sh --describe \
  --group inventory-service \
  --bootstrap-server localhost:9092
```

**Rich Output:**
```
GROUP             TOPIC  PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG  CONSUMER-ID        HOST          CLIENT-ID
inventory-service orders 0          145             150             5    consumer-1-abc123  /127.0.0.1    consumer-1
inventory-service orders 1          203             203             0    consumer-2-def456  /127.0.0.1    consumer-2
inventory-service orders 2          178             180             2    consumer-3-ghi789  /127.0.0.1    consumer-3
```

**Understanding Each Column:**

| Column | Meaning | Example |
|--------|---------|---------|
| **CURRENT-OFFSET** | Where consumer last read | 145 |
| **LOG-END-OFFSET** | Latest message in partition | 150 |
| **LAG** | Messages behind (LOG-END - CURRENT) | 5 |
| **CONSUMER-ID** | Unique ID of consumer instance | consumer-1-abc123 |
| **HOST** | Where consumer is running | /127.0.0.1 |

**Partition 0 Interpretation:**
```
Consumer at offset:     145
Latest message:         150
Lag:                    5 messages behind

├──[145]──────────────[150]
   ↑ Consumer here     ↑ Latest message
   
   5 messages to catch up!
```

**Partition 1 Interpretation:**
```
Consumer at offset:     203
Latest message:         203
Lag:                    0

├────────────────────[203]
                      ↑ Consumer caught up!
   
   ✅ No lag! Perfect!
```

**LAG Interpretation Guide:**

| LAG Value | Status | Action |
|-----------|--------|--------|
| 0 | ✅ Caught up | Healthy, no action |
| 1-100 | ⚠️ Slightly behind | Normal under load, monitor |
| 1,000+ | 🔥 Falling behind | Investigate! Scale up? |
| Growing | 🚨 Can't keep up | Critical! Add consumers now! |

---

### Parallel Consumption

**The Problem:** Single consumer too slow? Let's add teammates!

#### Scaling Demo

**Setup - Create High-Volume Topic:**
```bash
kafka/bin/kafka-topics.sh --create \
  --topic high-volume \
  --partitions 3 \
  --replication-factor 2 \
  --bootstrap-server localhost:9092
```

**Test 1: Single Consumer (Bottleneck)**

**Terminal 1:**
```bash
kafka/bin/kafka-console-consumer.sh \
  --topic high-volume \
  --group demo-group \
  --bootstrap-server localhost:9092

# This consumer handles ALL 3 partitions
# Bottleneck: One worker doing everything!
```

**Test 2: Three Consumers (Parallel Power!)**

**Terminal 1:**
```bash
kafka/bin/kafka-console-consumer.sh \
  --topic high-volume \
  --group demo-group \
  --bootstrap-server localhost:9092
```

**Terminal 2:**
```bash
kafka/bin/kafka-console-consumer.sh \
  --topic high-volume \
  --group demo-group \
  --bootstrap-server localhost:9092
```

**Terminal 3:**
```bash
kafka/bin/kafka-console-consumer.sh \
  --topic high-volume \
  --group demo-group \
  --bootstrap-server localhost:9092
```

**Kafka Automatically Distributes:**
```
Consumer 1 → Partition 0
Consumer 2 → Partition 1
Consumer 3 → Partition 2

Result: 3× throughput! 🚀
```

**Verify Assignment:**
```bash
kafka/bin/kafka-consumer-groups.sh --describe \
  --group demo-group \
  --bootstrap-server localhost:9092

# Shows which consumer assigned to which partition
```

**Visual Representation (Look at CONSUMER-ID):**

**Before (1 consumer):**
```
GROUP           TOPIC           PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG             CONSUMER-ID                                           HOST            CLIENT-ID
demo-group      high-volume     0          0               0               0               console-consumer-bac2bc23-dfe2-4b7d-93fe-b61a737bba46 /127.0.0.1      console-consumer
demo-group      high-volume     2          0               0               0               console-consumer-bac2bc23-dfe2-4b7d-93fe-b61a737bba46 /127.0.0.1      console-consumer
demo-group      high-volume     1          0               0               0               console-consumer-bac2bc23-dfe2-4b7d-93fe-b61a737bba46 /127.0.0.1      console-consumer%      
┌──────────────────┐
│   Consumer A     │
├──────────────────┤
│   Partition 0    │
│   Partition 1    │ ← Handles ALL partitions
│   Partition 2    │
└──────────────────┘
Throughput: 1× (bottleneck!)
```

**After (3 consumers):**
```
GROUP           TOPIC           PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG             CONSUMER-ID                                           HOST            CLIENT-ID
demo-group      high-volume     1          0               0               0               console-consumer-883bb348-9863-4dcb-860f-648dc57df17a /127.0.0.1      console-consumer
demo-group      high-volume     2          0               0               0               console-consumer-bac2bc23-dfe2-4b7d-93fe-b61a737bba46 /127.0.0.1      console-consumer
demo-group      high-volume     0          0               0               0               console-consumer-391b47e7-8793-4571-b995-a9729c7d9bd4 /127.0.0.1      console-consumer%      
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│ Consumer A  │  │ Consumer B  │  │ Consumer C  │
├─────────────┤  ├─────────────┤  ├─────────────┤
│ Partition 0 │  │ Partition 1 │  │ Partition 2 │
└─────────────┘  └─────────────┘  └─────────────┘
Throughput: 3× (parallelized!)
```

---

#### Rebalancing: The Choreography

**What is Rebalancing?**
When consumers join/leave, Kafka reassigns partitions.

**Triggers:**
- New consumer joins group
- Consumer leaves gracefully (shutdown)
- Consumer crashes (heartbeat timeout)
- Consumer becomes slow (exceeds `session.timeout.ms`)

**Live Rebalancing Demo:**

**Step 1: Start with 1 Consumer**
```bash
# Terminal 1
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --group rebalance-demo \
  --bootstrap-server localhost:9092

# Assignment: Consumer 1 gets [0, 1, 2]
```

**Step 2: Add 2nd Consumer (Triggers Rebalance)**
```bash
# Terminal 2
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --group rebalance-demo \
  --bootstrap-server localhost:9092

# Rebalance happens!
# New assignment:
#   Consumer 1: [0, 1]
#   Consumer 2: [2]
```

**Step 3: Add 3rd Consumer (Another Rebalance)**
```bash
# Terminal 3
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --group rebalance-demo \
  --bootstrap-server localhost:9092

# Rebalance again!
# Perfect distribution:
#   Consumer 1: [0]
#   Consumer 2: [1]
#   Consumer 3: [2]
```

**Step 4: Stop Consumer 2 (Ctrl+C in Terminal 2)**
```
# Rebalance triggered!
# Orphaned partition 1 reassigned:
#   Consumer 1: [0, 1]  ← Picked up partition 1
#   Consumer 3: [2]
```

**Rebalance Timeline:**
```
10:00:00  Consumer 1 joins  → Rebalance 1 → [0,1,2] to C1
10:01:00  Consumer 2 joins  → Rebalance 2 → [0,1] to C1, [2] to C2
10:02:00  Consumer 3 joins  → Rebalance 3 → [0] to C1, [1] to C2, [2] to C3
10:03:00  Consumer 2 leaves → Rebalance 4 → [0,1] to C1, [2] to C3
```

**During Rebalance:**
- ⚠️ Consumers **PAUSE** processing (can't read messages)
- ⚠️ Usually lasts 100ms - 1 second
- ⚠️ Frequent rebalances hurt performance ("rebalance storm")


---

#### Optimal Consumer Count

**The Golden Rule:**
```
Optimal consumers = Number of partitions
```

**Examples:**

**3 Partitions:**
- 1 consumer ❌ Underutilized (sequential)
- 2 consumers ⚠️ Uneven (2 partitions to one, 1 to other)
- 3 consumers ✅ Perfect (1:1 mapping)
- 4 consumers ⚠️ Wasteful (1 consumer idle)

**Assignment Scenarios:**

**Scenario 1: 3 partitions, 2 consumers (Unbalanced)**
```
┌────────────┐  ┌────────────┐
│ Consumer A │  │ Consumer B │
├────────────┤  ├────────────┤
│ Partition 0│  │ Partition 2│
│ Partition 1│  └────────────┘
└────────────┘
A does 2× work of B (unbalanced!)
```

**Scenario 2: 3 partitions, 3 consumers (OPTIMAL)**
```
┌──────────┐  ┌──────────┐  ┌──────────┐
│Consumer A│  │Consumer B│  │Consumer C│
├──────────┤  ├──────────┤  ├──────────┤
│Partition0│  │Partition1│  │Partition2│
└──────────┘  └──────────┘  └──────────┘
Perfect balance! ✅
```

**Scenario 3: 3 partitions, 5 consumers (Wasteful)**
```
┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐
│Consumer│  │Consumer│  │Consumer│  │Consumer│  │Consumer│
│   A    │  │   B    │  │   C    │  │   D    │  │   E    │
├────────┤  ├────────┤  ├────────┤  ├────────┤  ├────────┤
│ Part 0 │  │ Part 1 │  │ Part 2 │  │ (IDLE) │  │ (IDLE) │
└────────┘  └────────┘  └────────┘  └────────┘  └────────┘
D and E do nothing! Wasted resources! ❌
```

**How to Scale When Overloaded:**

If 3 consumers can't keep up (lag growing):

1. **Check Lag:**
```bash
kafka/bin/kafka-consumer-groups.sh --describe \
  --group my-group \
  --bootstrap-server localhost:9092

# If LAG growing → need more consumers
```

2. **Increase Partitions:**
```bash
# Increase from 3 to 6 partitions
kafka/bin/kafka-topics.sh --alter \
  --topic orders \
  --partitions 6 \
  --bootstrap-server localhost:9092
```

3. **Add More Consumers** (3 → 6):
```bash
# Start 3 additional consumers in the group
# Rebalance happens automatically
# Now 6 consumers handling 6 partitions (1:1)
```

4. **Verify Improved Throughput:**
```bash
# Check lag again - should be decreasing
kafka/bin/kafka-consumer-groups.sh --describe \
  --group my-group \
  --bootstrap-server localhost:9092
```

---

### Consumer Offsets

Offsets are like bookmarks in a book. They track "where am I in reading?"

#### Understanding Offsets

**What is an Offset?**
Offset = Position of a message in a partition (like a row number)

```
Partition 0: [Msg@0] [Msg@1] [Msg@2] [Msg@3] [Msg@4]
              ↑       ↑       ↑       ↑       ↑
           offset   offset  offset  offset  offset
             0        1       2       3       4
```

**Types of Offsets:**

**1. Current Offset** (where consumer last read):
```
Consumer read up to offset 3
→ Current offset = 3
→ Next read will be offset 4
```

**2. Committed Offset** (stored in Kafka for crash recovery):
```
Consumer reads offset 5
Consumer commits offset 5 to Kafka
Consumer crashes 💥
Consumer restarts 
Kafka says: "Resume from offset 5"
```

**3. Log-End Offset** (latest message):
```
Partition has messages up to offset 100
→ Log-end offset = 100
→ Next new message will be offset 101
```

**Lag Calculation:**
```
LAG = Log-End Offset - Current Offset

Example:
Current offset:  80
Log-end offset:  100
Lag: 100 - 80 = 20 messages behind
```

---

#### Offset Commit Strategies

**1. Automatic Commit (Default, Easiest)**

```bash
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --group auto-commit-demo \
  --bootstrap-server localhost:9092

# Default: auto-commits every 5 seconds
# (controlled by auto.commit.interval.ms=5000)
```

**What Happens:**
```
Time  0s: Read messages 0-10
Time  5s: Auto-commit → "I'm at offset 10"
Time 10s: Auto-commit → "I'm at offset 25"
Time 15s: Crash! 💥
Restart:  Kafka says "Resume from offset 25"
```

**Risk of Auto-Commit:**

The Problematic Scenario:
```
Time 0s:  Read message offset 10
Time 1s:  Processing message 10 (takes 10 seconds...)
Time 5s:  Auto-commit triggers → commits offset 10 ❌
Time 8s:  Crash mid-processing! 💥
Restart:  Offset 10 already committed
Result:   Message 10 LOST (never fully processed)
```

This is called **"at-most-once"** semantics - might lose messages.

**2. Manual Commit (Safer, More Control)**

Console consumer doesn't support manual commits well, but here's the concept:

```python
# Python pseudo-code (we'll do this in docs/06)
def process_messages():
    message = consumer.poll()  # Read message offset 10
    
    # Do your business logic
    process_order(message)     # Process message 10
    save_to_database(message)  # Save to DB
    
    # Only commit AFTER successful processing
    consumer.commit()          # Commit offset 10 ✅
```

This ensures **"at-least-once"** semantics - might reprocess, but won't lose.

---

#### View Current Offsets

**Check Consumer Group Offsets:**
```bash
kafka/bin/kafka-consumer-groups.sh --describe \
  --group inventory-service \
  --bootstrap-server localhost:9092
```

**Output:**
```
GROUP              TOPIC  PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG
inventory-service  orders 0          145             150             5
inventory-service  orders 1          203             203             0
inventory-service  orders 2          178             180             2
```

**Get Earliest/Latest Offsets for Topic:**

```bash
# Earliest (first message) offset
kafka/bin/kafka-get-offsets.sh \
  --broker-list localhost:9092 \
  --topic orders \
  --time -2

# Output:
orders:0:0
orders:1:0
orders:2:0
orders:3:0
orders:4:0
orders:5:0
# (All partitions start at offset 0)
```

```bash
# Latest (last message + 1) offset
kafka/bin/kafka-get-offsets.sh \
  --broker-list localhost:9092 \
  --topic orders \
  --time -1

# Output:
orders:0:3
orders:1:5
orders:2:0
orders:3:0
orders:4:2
orders:5:0
# (Partition 0 has 3 messages total)
```

---

## Partition Strategies

Let's dive deeper into how to use partitions effectively!

### Partition Key Selection for Ordering

Remember: **Same key → Same partition → Guaranteed ordering**

#### E-Commerce Ordering Scenarios

**Scenario 1: User Shopping Cart** (key = user_id)

All cart events for a user must be ordered:

```bash
kafka/bin/kafka-console-producer.sh \
  --topic cart-events \
  --bootstrap-server localhost:9092 \
  --property parse.key=true \
  --property key.separator=:

# Type these:
>USER-123:{"action":"add_to_cart","item":"laptop","price":1200}
>USER-123:{"action":"add_to_cart","item":"mouse","price":25}
>USER-123:{"action":"checkout","total":1225}
```

**Result:**
```
All 3 events guaranteed in order:
1. Add laptop
2. Add mouse
3. Checkout
✅ Because same key "USER-123" → same partition
```

**Scenario 2: Order Fulfillment** (key = order_id)

Order goes through lifecycle stages:

```bash
kafka/bin/kafka-console-producer.sh \
  --topic order-status \
  --bootstrap-server localhost:9092 \
  --property parse.key=true \
  --property key.separator=:

>ORD-5001:{"status":"created","timestamp":"2026-01-01T10:00:00Z"}
>ORD-5001:{"status":"paid","timestamp":"2026-01-01T10:01:30Z"}
>ORD-5001:{"status":"shipped","timestamp":"2026-01-01T11:30:00Z"}
>ORD-5001:{"status":"delivered","timestamp":"2026-01-01T15:00:00Z"}
```

**Guaranteed Order:**
```
created → paid → shipped → delivered ✅
```

**Scenario 3: No Key Needed** (independent events)

Pageview events don't need ordering:

```bash
kafka/bin/kafka-console-producer.sh \
  --topic pageviews \
  --bootstrap-server localhost:9092

# No key property needed
>{"page":"/home","user":"USER-123"}
>{"page":"/products","user":"USER-456"}
>{"page":"/cart","user":"USER-789"}

# Round-robin distribution → maximum parallelism
```

---

### Hot Partition Problem

**What is a Hot Partition?**
One partition receiving disproportionate load, becoming a bottleneck.

**Example Problem: E-Commerce with Power Seller**

```
Regular sellers: 10 orders/day each
Power seller:    10,000 orders/day

Key = seller_id:
hash(power_seller_id) % 3 = Partition 1

Result:
Partition 0: 1,000 orders/day  ✅ Normal
Partition 1: 12,000 orders/day 🔥 HOT! (10K from power seller)
Partition 2: 1,000 orders/day  ✅ Normal

Consumer on Partition 1 overwhelmed!
```

**Solution 1: Composite Key** (add randomness)

Instead of:
```
seller_id as key
```

Use:
```
seller_id + random_suffix
```

```bash
# Spread power seller across partitions
>SELLER-999-rand001:{"order_data":"..."}
>SELLER-999-rand002:{"order_data":"..."}
>SELLER-999-rand003:{"order_data":"..."}

# Now power seller's orders distributed
# Trade-off: Lose global ordering for that seller
```

**Solution 2: More Partitions**

```bash
# Increase from 3 to 12 partitions
kafka/bin/kafka-topics.sh --alter \
  --topic orders \
  --partitions 12 \
  --bootstrap-server localhost:9092

# Power seller still goes to 1 partition, but:
# - That partition is 1/12 of topic (not 1/3)
# - Can add more consumers to balance
```

**Solution 3: Application-Level Routing**

```python
# Detect hot keys, route differently
if seller_id == "POWER_SELLER_999":
    # Send to dedicated high-volume topic
    producer.send("orders-high-volume", order)
else:
    # Normal sellers to regular topic
    producer.send("orders-regular", order)
```

**Monitor for Hot Partitions:**

```bash
# Check message count per partition
for partition in {0..2}; do
  echo -n "Partition $partition: "
  kafka/bin/kafka-get-offsets.sh \
    --broker-list localhost:9092 \
    --topic orders \
    --time -1 | grep ":$partition:" | awk -F: '{print $3}'
done

# Output:
# Partition 0: 1,520  ✅ Balanced
# Partition 1: 15,890 🔥 HOT!
# Partition 2: 1,440  ✅ Balanced
```

---

## Message Headers & Metadata

Headers are key-value metadata attached to messages (like HTTP headers).

### What are Message Headers?

**Message Structure:**
```
Kafka Message:
├─ Key: USER-500
├─ Value: {"order_id":"ORD-1001","amount":1200.00}
├─ Headers:
│  ├─ source=web
│  ├─ trace-id=xyz-789
│  ├─ schema-version=1.0
│  └─ priority=high
└─ Timestamp: 1735728630000
```

**Use Cases:**

| Use Case | Header Example | Purpose |
|----------|----------------|---------|
| Routing | `source=mobile-app` | Route to different consumers |
| Tracing | `trace-id=abc-123` | Distributed tracing across services |
| Versioning | `schema-version=2.0` | Handle format changes |
| Authorization | `user-role=admin` | Access control |
| Filtering | `priority=high` | Process urgent messages first |

---

### Message Timestamps

Every Kafka message has a timestamp (Unix epoch milliseconds).

**Two Types:**

1. **CreateTime** (default): When producer created message
2. **LogAppendTime**: When broker received message

**View Timestamps:**
```bash
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --from-beginning \
  --max-messages 3 \
  --bootstrap-server localhost:9092 \
  --property print.timestamp=true

# Output:
# CreateTime:1735728630000    {"order_id":"ORD-1001",...}
# CreateTime:1735728635000    {"order_id":"ORD-1002",...}
```

**Convert to Human-Readable:**
```bash
# macOS
date -r $((1735728630000 / 1000))
# Output: Thu Jan  1 12:30:30 IST 2026

# Linux
date -d @$((1735728630000 / 1000))
```

**Configure Timestamp Type:**
```bash
# Use LogAppendTime instead
kafka/bin/kafka-configs.sh --alter \
  --entity-type topics \
  --entity-name orders \
  --add-config message.timestamp.type=LogAppendTime \
  --bootstrap-server localhost:9092
```

**CreateTime vs. LogAppendTime:**

```
CreateTime (default):
  ✅ Preserves original event time
  ✅ Good for event-time processing
  ❌ Can be inaccurate (clock skew)

LogAppendTime:
  ✅ Consistent (single broker clock)
  ✅ Good for ingestion-time processing
  ❌ Loses original event time
```

---

## Offset Management

Offsets are critical for consumer reliability. Let's master them!

### Resetting Consumer Group Offsets

**What is Offset Reset?**
Changing where a consumer group starts reading.

**Common Use Cases:**
1. Reprocess historical data (bug fix, re-analyze)
2. Skip bad messages
3. Start from specific timestamp
4. Catch up after long downtime

**⚠️ Prerequisites:** Consumer group must be **inactive** (no running consumers).

**Stop Consumers First:**
```bash
# Check for active consumers
kafka/bin/kafka-consumer-groups.sh --describe \
  --group inventory-service \
  --bootstrap-server localhost:9092

# Stop all consumers (Ctrl+C in their terminals)

# Verify no active members
kafka/bin/kafka-consumer-groups.sh --describe \
  --group inventory-service \
  --bootstrap-server localhost:9092 | grep -i consumer-id

# CONSUMER-ID column should be empty
```

---

### Reset to Earliest (Beginning)

Rewind to first message ever written:

```bash
kafka/bin/kafka-consumer-groups.sh --reset-offsets \
  --group inventory-service \
  --topic orders \
  --to-earliest \
  --execute \
  --bootstrap-server localhost:9092
```

**Output:**
```
GROUP              TOPIC  PARTITION  NEW-OFFSET
inventory-service  orders 0          0
inventory-service  orders 1          0
inventory-service  orders 2          0
```

**Verify:**
```bash
# Start consumer - reads ALL history
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --group inventory-service \
  --bootstrap-server localhost:9092
```

**Use Case:**
```
Scenario: Analytics bug dropped 50% of data
Solution: Reset to earliest, reprocess everything
```

---

### Reset to Latest (End)

Skip all existing messages, start from next new one:

```bash
kafka/bin/kafka-consumer-groups.sh --reset-offsets \
  --group inventory-service \
  --topic orders \
  --to-latest \
  --execute \
  --bootstrap-server localhost:9092
```

**Output:**
```
GROUP              TOPIC  PARTITION  NEW-OFFSET
inventory-service  orders 0          150
inventory-service  orders 1          203
inventory-service  orders 2          180
```

**Use Case:**
```
Scenario: Consumer down 3 days, 1M backlogged messages
Solution: Skip backlog, only process new messages
```

---

### Reset to Specific Timestamp

Start from first message after given time:

```bash
# Reset to 1 hour ago
TIMESTAMP=$(date -v-1H +%s)000  # macOS (milliseconds)

kafka/bin/kafka-consumer-groups.sh --reset-offsets \
  --group inventory-service \
  --topic orders \
  --to-datetime "${TIMESTAMP}" \
  --execute \
  --bootstrap-server localhost:9092
```


**Use Case:**
```
Scenario: DB crashed at 10:00 AM, need replay from 9:55 AM
Solution: Reset to 2026-01-01T09:55:00
```

---

### Reset to Specific Offset

Set exact offset number:

```bash
# Reset partition 0 to offset 100
kafka/bin/kafka-consumer-groups.sh --reset-offsets \
  --group inventory-service \
  --topic orders:0 \
  --to-offset 100 \
  --execute \
  --bootstrap-server localhost:9092
```

**Reset All Partitions:**
```bash
kafka/bin/kafka-consumer-groups.sh --reset-offsets \
  --group inventory-service \
  --topic orders \
  --to-offset 50 \
  --execute \
  --bootstrap-server localhost:9092
```

**Use Case:**
```
Scenario: Bad data at offsets 80-85 in partition 1
Solution: Reset partition 1 to offset 86, skip bad data
```

---

### Shift Offsets (Relative Movement)

Move offsets by relative amount:

**Shift Forward (skip N messages):**
```bash
# Skip next 10 messages
kafka/bin/kafka-consumer-groups.sh --reset-offsets \
  --group inventory-service \
  --topic orders \
  --shift-by 10 \
  --execute \
  --bootstrap-server localhost:9092
```

**Shift Backward (reprocess last N):**
```bash
# Reprocess last 20 messages
kafka/bin/kafka-consumer-groups.sh --reset-offsets \
  --group inventory-service \
  --topic orders \
  --shift-by -20 \
  --execute \
  --bootstrap-server localhost:9092
```

**Use Case:**
```
Scenario: Last 50 messages had wrong business logic
Solution: Shift by -50, reprocess with fix
```

---

### Dry-Run (Preview First!)

**Always** preview before executing:

```bash
# Remove --execute to preview
kafka/bin/kafka-consumer-groups.sh --reset-offsets \
  --group inventory-service \
  --topic orders \
  --to-earliest \
  --bootstrap-server localhost:9092

# Shows what WOULD happen (safe!)
```

**Output:**
```
GROUP              TOPIC  PARTITION  NEW-OFFSET
inventory-service  orders 0          0
inventory-service  orders 1          0
inventory-service  orders 2          0

# But offsets NOT actually changed
```

**Best Practice:** Always dry-run → verify → add `--execute`

---

### Export/Import Offsets (Backup & Restore)

**Export Current Offsets:**
```bash
kafka/bin/kafka-consumer-groups.sh --reset-offsets \
  --group inventory-service \
  --topic orders \
  --to-current \
  --export \
  --bootstrap-server localhost:9092 > /tmp/offsets-backup.csv
```

**CSV Contents:**
```
orders,0,145
orders,1,203
orders,2,178
```

**Import Offsets:**
```bash
kafka/bin/kafka-consumer-groups.sh --reset-offsets \
  --group inventory-service \
  --from-file /tmp/offsets-backup.csv \
  --execute \
  --bootstrap-server localhost:9092
```

**Use Case:**
```
Testing new consumer logic:
1. Export offsets before test
2. Run new consumer
3. If broken, import old offsets to revert
```

---

## Advanced Topics

Now let's explore Kafka's sophisticated features!

### Transactions

**What are Transactions?**
Atomic write of multiple messages - either ALL commit or ALL abort.

**Why Transactions Matter:**

**WITHOUT Transactions (broken):**
```
Transfer $100 from Account A to B:

Step 1: Write "debit A: $100" to topic ✅
Step 2: Producer crashes! 💥
Step 3: Write "credit B: $100" never happens ❌

Result: A debited, B never credited → Money lost! 😱
```

**WITH Transactions (correct):**
```
producer.beginTransaction()
producer.send("debit A: $100")
producer.send("credit B: $100")
producer.commitTransaction()  ← Both succeed atomically

If crash before commit:
  → Transaction aborted
  → NEITHER message visible
  → Money transfer never happened (consistent!)
```

**Use Cases:**
- ✅ Financial transactions (payments, transfers)
- ✅ Multi-table updates (distributed databases)
- ✅ Exactly-once semantics (read → process → write)
- ✅ Cross-topic atomicity

---

#### Transaction Demo Setup

**Create Transaction Topic:**
```bash
kafka/bin/kafka-topics.sh --create \
  --topic account-updates \
  --partitions 3 \
  --replication-factor 2 \
  --config min.insync.replicas=2 \
  --bootstrap-server localhost:9092
```

**Why `min.insync.replicas=2`?**
Transactions require strong durability. Both leader and follower must ack.

**Transactional Consumer:**
```bash
# Only reads committed transactions
kafka/bin/kafka-console-consumer.sh \
  --topic account-updates \
  --from-beginning \
  --isolation-level read_committed \
  --bootstrap-server localhost:9092
```

**Isolation Levels:**

```
read_uncommitted (default):
  - Sees ALL messages (even aborted transactions)
  - Faster, but can see inconsistent data
  - Use for: non-critical data

read_committed:
  - Only sees committed transactions
  - Slower, but always consistent
  - Use for: financial/critical data
```

**Note:** True transactional producers require programming language clients (Python, Java). We'll cover this in `docs/06-python-integration.md`.

---

### Log Compaction

**What is Log Compaction?**
Keeps only the **latest value** for each key, deleting old values.

**Normal Retention:**
```
Messages deleted after time (e.g., 7 days)
Entire history deleted
```

**Log Compaction:**
```
Keeps latest value per key
Older values deleted
Topic becomes "changelog" of current state
```

**Visual Example:**

**Before Compaction:**
```
Offset  Key      Value
0       USER-1   {"name":"Alice","email":"alice@old.com"}
1       USER-2   {"name":"Bob","email":"bob@old.com"}
2       USER-1   {"name":"Alice","email":"alice@new.com"}  ← Updated
3       USER-3   {"name":"Charlie","email":"charlie@old.com"}
4       USER-2   {"name":"Bob","email":"bob@new.com"}      ← Updated
5       USER-1   {"name":"Alice","email":"alice@latest.com"} ← Updated again
```

**After Compaction:**
```
Offset  Key      Value
2       USER-1   {"name":"Alice","email":"alice@latest.com"}  ← Latest only!
3       USER-3   {"name":"Charlie","email":"charlie@old.com"}
4       USER-2   {"name":"Bob","email":"bob@new.com"}         ← Latest only!

# Offsets 0, 1, 5 deleted (old values)
```

---

#### Log Compaction Use Cases

**Use Case 1: User Profile Database**
```
Topic: user-profiles (compacted)
Key = user_id, Value = profile JSON

USER-100:{"name":"Alice","city":"NYC"}
USER-100:{"name":"Alice","city":"SF"}      ← Moved
USER-100:{"name":"Alice","city":"LA"}      ← Moved again

After compaction: Only latest {"city":"LA"} kept
→ Topic acts as database of current profiles
```

**Use Case 2: Configuration Management**
```
Topic: service-configs (compacted)
Key = config_name, Value = config_value

"max_connections":"100"
"max_connections":"200"  ← Updated
"max_connections":"500"  ← Updated

After compaction: Only "500" kept
→ Always get latest config
```

**Use Case 3: CDC (Change Data Capture)**
```
Topic: database-changelog (compacted)
Key = row_id, Value = latest row state

ORDER-1:{"status":"pending"}
ORDER-1:{"status":"paid"}
ORDER-1:{"status":"shipped"}

After compaction: Only {"status":"shipped"} kept
→ Topic mirrors current database state
```

---

#### Creating Compacted Topic

```bash
kafka/bin/kafka-topics.sh --create \
  --topic user-profiles \
  --partitions 3 \
  --replication-factor 2 \
  --config cleanup.policy=compact \
  --config min.cleanable.dirty.ratio=0.01 \
  --config segment.ms=60000 \
  --bootstrap-server localhost:9092
```

**Configuration:**

| Config | Value | Purpose |
|--------|-------|---------|
| `cleanup.policy=compact` | Enable compaction | Instead of time-based deletion |
| `min.cleanable.dirty.ratio=0.01` | 1% dirty | Compact when 1% has duplicates (aggressive) |
| `segment.ms=60000` | 60 seconds | Close segment every minute (faster compaction for testing) |

---

#### Testing Log Compaction

**Step 1: Produce Updates for Same Keys**

```bash
kafka/bin/kafka-console-producer.sh \
  --topic user-profiles \
  --bootstrap-server localhost:9092 \
  --property parse.key=true \
  --property key.separator=:

# Type multiple updates for USER-1:
>USER-1:{"name":"Alice","version":1,"email":"alice1@test.com"}
>USER-2:{"name":"Bob","version":1,"email":"bob1@test.com"}
>USER-1:{"name":"Alice","version":2,"email":"alice2@test.com"}
>USER-3:{"name":"Charlie","version":1,"email":"charlie1@test.com"}
>USER-1:{"name":"Alice","version":3,"email":"alice3@test.com"}
>USER-2:{"name":"Bob","version":2,"email":"bob2@test.com"}
>^C
```

**Step 2: Read Before Compaction**

```bash
kafka/bin/kafka-console-consumer.sh \
  --topic user-profiles \
  --from-beginning \
  --property print.key=true \
  --property key.separator=" | " \
  --bootstrap-server localhost:9092 \
  --timeout-ms 5000

# Shows ALL messages (including duplicates):
# USER-1 | version:1
# USER-2 | version:1
# USER-1 | version:2  ← Duplicate
# USER-3 | version:1
# USER-1 | version:3  ← Duplicate
# USER-2 | version:2  ← Duplicate
```

**Step 3: Wait for Compaction**

```bash
# Wait for segment.ms (60s) + compaction
echo "Waiting 90 seconds for compaction..."
sleep 90
```

**Step 4: Trigger segment close**
```bash
echo "TRIGGER:segment-close" | kafka/bin/kafka-console-producer.sh \
  --topic user-profiles \
  --bootstrap-server localhost:9092 \
  --property parse.key=true \
  --property key.separator=:
```

**Step 5: Read After Compaction**

```bash
kafka/bin/kafka-console-consumer.sh \
  --topic user-profiles \
  --from-beginning \
  --property print.key=true \
  --property key.separator=" | " \
  --bootstrap-server localhost:9092 \
  --timeout-ms 5000

# Shows ONLY latest values:
# USER-1 | version:3  ← Latest only!
# USER-2 | version:2  ← Latest only!
# USER-3 | version:1

# Old versions deleted! ✅
```

---

#### Deleting Keys (Tombstones)

**What is a Tombstone?**
Message with key but NULL value → signals "delete this key".

**How It Works:**
```
Step 1: Produce tombstone (NULL value)
Step 2: Compaction runs → deletes all previous messages with that key
Step 3: Eventually deletes tombstone itself
Result: Key completely gone!
```

**Produce Tombstone:**
```bash
# Delete USER-1 by sending NULL value
echo "USER-1:" | kafka/bin/kafka-console-producer.sh \
  --topic user-profiles \
  --bootstrap-server localhost:9092 \
  --property parse.key=true \
  --property key.separator=: \
  --property null.marker=""

# Empty value after : means NULL
```
```bash
echo "TRIGGER2:close-segment-with-tombstone" | kafka/bin/kafka-console-producer.sh \
  --topic user-profiles \
  --bootstrap-server localhost:9092 \
  --property parse.key=true \
  --property key.separator=:
```

**Verify Deletion:**
```bash
# Wait for compaction
sleep 90

# Read topic - USER-1 should be gone
kafka/bin/kafka-console-consumer.sh \
  --topic user-profiles \
  --from-beginning \
  --property print.key=true \
  --bootstrap-server localhost:9092 \
  --timeout-ms 5000

# Output: USER-2, USER-3 present, NO USER-1! ✅
```

**Tombstone Retention:**
```
delete.retention.ms=86400000  (24 hours default)

Why wait 24 hours?
  → Offline consumers need time to see tombstone
  → After 24h, safe to assume all consumers saw it
  → Then tombstone itself deleted
```

---

### Quotas & Throttling

**What are Quotas?**
Rate limits on producers/consumers to prevent one client from overwhelming the cluster.

**Why Quotas Matter:**
```
Without Quotas:
  - Noisy producer saturates bandwidth
  - Other producers starved
  - Cluster unstable

With Quotas:
  - Fair resource allocation
  - Prevents DoS attacks
  - Predictable performance
```

**Throttling Behavior:**
```
Client exceeds quota:
  ├─ Broker slows down responses (adds delay)
  ├─ Client automatically backs off
  └─ Other clients unaffected
```

---

#### Configure Producer Quota

**For Specific Client:**
```bash
# Limit "heavy-producer" to 1 MB/s
kafka/bin/kafka-configs.sh --alter \
  --add-config 'producer_byte_rate=1048576' \
  --entity-type clients \
  --entity-name heavy-producer \
  --bootstrap-server localhost:9092
```

**Default for All Producers:**
```bash
# Default: 10 MB/s for any producer
kafka/bin/kafka-configs.sh --alter \
  --add-config 'producer_byte_rate=10485760' \
  --entity-type clients \
  --entity-default \
  --bootstrap-server localhost:9092
```

**Verify Quota:**
```bash
kafka/bin/kafka-configs.sh --describe \
  --entity-type clients \
  --entity-name heavy-producer \
  --bootstrap-server localhost:9092

# Output: producer_byte_rate=1048576
```

---

#### Testing Quota Throttling

**Set Aggressive Quota (for testing):**
```bash
# Very low limit: 100 KB/s
kafka/bin/kafka-configs.sh --alter \
  --add-config 'producer_byte_rate=102400' \
  --entity-type clients \
  --entity-name quota-test-producer \
  --bootstrap-server localhost:9092
```

**Produce Rapidly (exceeds quota):**
```bash
# Generate large messages
for i in {1..1000}; do
  echo "Message $i: $(head -c 10000 /dev/urandom | base64)"
done | kafka/bin/kafka-console-producer.sh \
  --topic test-quota \
  --bootstrap-server localhost:9092 \
  --producer-property client.id=quota-test-producer

# You'll notice slowdown as producer hits quota limit
```

**Monitor Throttling:**
```bash
# Check broker logs for quota violations
tail -f ~/kafka-learning-lab/kafka/logs/server.log | grep -i quota

# Look for:
# [Throttle time] Producing to topic test-quota for client quota-test-producer delayed for 250 ms
```

**Remove Quota:**
```bash
kafka/bin/kafka-configs.sh --alter \
  --delete-config producer_byte_rate \
  --entity-type clients \
  --entity-name quota-test-producer \
  --bootstrap-server localhost:9092
```

---

#### Consumer Quotas

**Set Consumer Quota:**
```bash
# Limit consumer to 2 MB/s
kafka/bin/kafka-configs.sh --alter \
  --add-config 'consumer_byte_rate=2097152' \
  --entity-type clients \
  --entity-name slow-consumer \
  --bootstrap-server localhost:9092
```

**Test:**
```bash
# Consumer automatically throttled to 2 MB/s
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --from-beginning \
  --bootstrap-server localhost:9092 \
  --consumer-property client.id=slow-consumer
```

---

#### Request Rate Quotas

**What It Limits:**
Number of requests/second (not bytes) - prevents metadata spam.

**Set Request Rate Quota:**
```bash
# Limit to 10 requests/second
kafka/bin/kafka-configs.sh --alter \
  --add-config 'request_percentage=10' \
  --entity-type clients \
  --entity-name chatty-client \
  --bootstrap-server localhost:9092
```

**Use Cases:**
- Prevent metadata request spam
- Limit admin operations (topic creation)
- Protect cluster from misbehaving clients

---

## Real-World Scenarios

Let's apply everything we've learned to realistic business scenarios!

### Scenario 1: E-Commerce Order Processing Pipeline

**Business Requirement:**
```
When customer places order:
1. Inventory service checks stock
2. Payment service charges card
3. Shipping service creates label
4. Notification service sends email
5. Analytics service tracks revenue

All services independent, can be down/slow without affecting others
```

**Kafka Solution:**

**Step 1: Create Order Topic**
```bash
kafka/bin/kafka-topics.sh --create \
  --topic orders \
  --partitions 6 \
  --replication-factor 2 \
  --config retention.ms=2592000000 \
  --config min.insync.replicas=2 \
  --bootstrap-server localhost:9092
```

**Step 2: Inventory Service Consumes  (Terminal 1)**
```bash
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --group inventory-service \
  --bootstrap-server localhost:9092 \
  --timeout-ms 60000 2>/dev/null | \
while IFS= read -r line; do
  order_id=$(echo "$line" | jq -r '.order_id' 2>/dev/null)
  product=$(echo "$line" | jq -r '.items[0].product_name' 2>/dev/null)
  quantity=$(echo "$line" | jq -r '.items[0].quantity' 2>/dev/null)
  
  if [ "$order_id" != "null" ] && [ -n "$order_id" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🏭 [INVENTORY SERVICE]"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 Order ID: $order_id"
    echo "🔍 Checking stock for: $product"
    echo "📊 Quantity requested: $quantity"
    echo "✅ Stock available - RESERVED"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
  fi
done
```

**Step 3: Payment Service Consumes (independently)  (Terminal 2)**
```bash
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --group payment-service \
  --bootstrap-server localhost:9092 \
  --timeout-ms 60000 2>/dev/null | \
while IFS= read -r line; do
  order_id=$(echo "$line" | jq -r '.order_id' 2>/dev/null)
  amount=$(echo "$line" | jq -r '.total_amount' 2>/dev/null)
  method=$(echo "$line" | jq -r '.payment_method' 2>/dev/null)
  user=$(echo "$line" | jq -r '.user_id' 2>/dev/null)
  
  if [ "$order_id" != "null" ] && [ -n "$order_id" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "💳 [PAYMENT SERVICE]"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 Order ID: $order_id"
    echo "👤 User: $user"
    echo "💰 Amount: \$$amount"
    echo "💳 Method: $method"
    echo "✅ Payment SUCCESSFUL"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
  fi
done
```

**Step 4: Analytics Service Consumes (independently)  (Terminal 3)**
```bash
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --group analytics-service \
  --bootstrap-server localhost:9092 \
  --timeout-ms 60000 2>/dev/null | \
while IFS= read -r line; do
  order_id=$(echo "$line" | jq -r '.order_id' 2>/dev/null)
  amount=$(echo "$line" | jq -r '.total_amount' 2>/dev/null)
  user=$(echo "$line" | jq -r '.user_id' 2>/dev/null)
  items=$(echo "$line" | jq -r '.items | length' 2>/dev/null)
  product=$(echo "$line" | jq -r '.items[0].product_name' 2>/dev/null)
  city=$(echo "$line" | jq -r '.shipping_address.city' 2>/dev/null)
  
  if [ "$order_id" != "null" ] && [ -n "$order_id" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 [ANALYTICS SERVICE]"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 Order ID: $order_id"
    echo "👤 User: $user"
    echo "💵 Revenue: \$$amount"
    echo "🛍️  Items: $items ($product)"
    echo "📍 Location: $city"
    echo "✅ Data LOGGED"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
  fi
done
```

**Step 5: Website Produces Order  (Terminal 4)**
```bash
echo 'ORD-2001:{"order_id":"ORD-2001","user_id":"USER-500","timestamp":"2026-01-04T19:40:00Z","items":[{"product_id":"LAPTOP-X1","product_name":"Dell XPS 15","quantity":1,"price":1200.00}],"total_amount":1200.00,"payment_method":"credit_card","shipping_address":{"street":"123 Main St","city":"San Francisco","state":"CA","zip":"94102"},"status":"pending"}' | \
kafka/bin/kafka-console-producer.sh \
  --topic orders \
  --bootstrap-server localhost:9092 \
  --property parse.key=true \
  --property key.separator=:

AND

echo 'ORD-2002:{"order_id":"ORD-2002","user_id":"USER-501","timestamp":"2026-01-04T19:41:00Z","items":[{"product_id":"PHONE-IP15","product_name":"iPhone 15 Pro","quantity":2,"price":999.00}],"total_amount":1998.00,"payment_method":"paypal","shipping_address":{"street":"456 Oak Ave","city":"New York","state":"NY","zip":"10001"},"status":"pending"}' | \
kafka/bin/kafka-console-producer.sh \
  --topic orders \
  --bootstrap-server localhost:9092 \
  --property parse.key=true \
  --property key.separator=:

AND

echo 'ORD-2004:{"order_id":"ORD-2004","user_id":"USER-500","timestamp":"2026-01-04T19:43:00Z","items":[{"product_id":"MONITOR-U27","product_name":"4K Monitor 27 inch","quantity":1,"price":450.00}],"total_amount":450.00,"payment_method":"credit_card","shipping_address":{"street":"123 Main St","city":"San Francisco","state":"CA","zip":"94102"},"status":"pending"}' | \
kafka/bin/kafka-console-producer.sh \
  --topic orders \
  --bootstrap-server localhost:9092 \
  --property parse.key=true \
  --property key.separator=:
```

**Benefits:**
- ✅ Each service independent (can be down without affecting others)
- ✅ Services process at own pace
- ✅ Add new services without changing existing ones
- ✅ Historical replay (new service can process past orders)

---

### Scenario 2: Fraud Detection System

**Business Requirement:**
```
Detect fraudulent transactions in real-time:
1. Transaction arrives
2. Check against fraud rules
3. Flag suspicious patterns
4. Alert security team
```

**Kafka Solution:**

**Step 1: Create Transactions Topic**
```bash
kafka/bin/kafka-topics.sh --create \
  --topic transactions \
  --partitions 12 \
  --replication-factor 2 \
  --bootstrap-server localhost:9092

# High partitions for high throughput
```

**Step 2: Produce Transactions (keyed by account_id)**
```bash
kafka/bin/kafka-console-producer.sh \
  --topic transactions \
  --bootstrap-server localhost:9092 \
  --property parse.key=true \
  --property key.separator=: << 'EOF'
ACC-100:{"txn_id":"TXN-001","account_id":"ACC-100","amount":50.00,"merchant":"Starbucks","timestamp":"2026-01-01T14:00:00Z"}
ACC-100:{"txn_id":"TXN-002","account_id":"ACC-100","amount":2000.00,"merchant":"Electronics Store","timestamp":"2026-01-01T14:00:30Z"}
ACC-100:{"txn_id":"TXN-003","account_id":"ACC-100","amount":1500.00,"merchant":"Jewelry Store","timestamp":"2026-01-01T14:01:00Z"}
ACC-200:{"txn_id":"TXN-004","account_id":"ACC-200","amount":30.00,"merchant":"Gas Station","timestamp":"2026-01-01T14:02:00Z"}
EOF
```

**Step 3: Fraud Detector Consumes**
```bash
kafka/bin/kafka-console-consumer.sh \
  --topic transactions \
  --group fraud-detector \
  --bootstrap-server localhost:9092 | \
while read txn; do
  account=$(echo $txn | jq -r '.account_id')
  amount=$(echo $txn | jq -r '.amount')
  txn_id=$(echo $txn | jq -r '.txn_id')
  merchant=$(echo $txn | jq -r '.merchant')
  
  # Simple rule: Flag transactions > $1000
  if (( $(echo "$amount > 1000" | bc -l) )); then
    echo "🚨 [FRAUD ALERT] Account $account: High-value transaction \$amount"
    echo "   Transaction: $txn_id"
    echo "   Merchant: $merchant"
    echo "   Action: Hold for review"
  else
    echo "✅ [APPROVED] Transaction $txn_id: \$amount"
  fi
  echo ""
done
```

**Why Key on account_id?**
```
All ACC-100 transactions → same partition
→ Same consumer processes them
→ Consumer can track velocity (3 txns in 1 minute)
→ Detect "card testing" attacks
```

---

### Scenario 3: Real-Time Analytics Dashboard

**Business Requirement:**
```
Display live metrics:
- Orders per minute
- Revenue per minute
- Top products
Update every 10 seconds
```

**Step 1: Continuous Order Production (simulate traffic)**
```bash
# Start continuous order production (1 order per second)
(while true; do
  order_id="ORD-$(date +%s)"
  amount=$((RANDOM % 500 + 50))
  products=("Laptop" "Phone" "Tablet" "Monitor" "Keyboard" "Mouse" "Headphones")
  product=${products[$((RANDOM % 7))]}
  
  echo "{\"order_id\":\"$order_id\",\"amount\":$amount,\"product\":\"$product\",\"timestamp\":\"$(date -Iseconds)\"}" | \
  kafka/bin/kafka-console-producer.sh \
    --topic orders \
    --bootstrap-server localhost:9092 2>/dev/null
  
  sleep 1
done) &

PRODUCER_PID=$!
echo "✅ Producer started with PID: $PRODUCER_PID"
echo "💡 Run this to stop: kill $PRODUCER_PID"
echo ""

```

**Step 2: Analytics Consumer (aggregates data)**
```bash
kafka/bin/kafka-console-consumer.sh \
  --topic orders \
  --group analytics-dashboard \
  --bootstrap-server localhost:9092 2>/dev/null | \
{
  count=0
  total=0
  start_time=$(date +%s)
  
  while IFS= read -r line; do
    # Parse amount
    amount=$(echo "$line" | grep -o '"amount":[0-9]*' | grep -o '[0-9]*')
    product=$(echo "$line" | grep -o '"product":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$amount" ]; then
      count=$((count + 1))
      total=$((total + amount))
      
      # Print dashboard every 10 orders
      if [ $((count % 10)) -eq 0 ]; then
        elapsed=$(($(date +%s) - start_time))
        if [ $elapsed -eq 0 ]; then elapsed=1; fi
        rate=$(echo "scale=2; $count / $elapsed" | bc)
        avg=$((total / count))
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📊 [REAL-TIME DASHBOARD]"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📦 Total Orders: $count"
        echo "💰 Total Revenue: \$$total"
        echo "📈 Avg Order Value: \$$avg"
        echo "⚡ Order Rate: $rate orders/sec"
        echo "⏱️  Running: $elapsed seconds"
        echo "🛍️  Last Product: $product"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
      fi
    fi
  done
}

```

**Expected Output:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 [REAL-TIME DASHBOARD]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📦 Total Orders: 10
💰 Total Revenue: $3417
📈 Avg Order Value: $341
⚡ Order Rate: 2.50 orders/sec
⏱️  Running: 4 seconds
🛍️  Last Product: Monitor
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 [REAL-TIME DASHBOARD]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📦 Total Orders: 20
💰 Total Revenue: $6034
📈 Avg Order Value: $301
⚡ Order Rate: 1.33 orders/sec
⏱️  Running: 15 seconds
🛍️  Last Product: 
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
.
.
.
```

**Stop Producer:**
```bash
kill $PRODUCER_PID
```

---

## Command Reference Cheat Sheet

Quick reference for all commands!

### Topic Operations
```bash
# Create
kafka/bin/kafka-topics.sh --create --topic NAME --partitions N --replication-factor M --bootstrap-server localhost:9092

# List
kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092

# Describe
kafka/bin/kafka-topics.sh --describe --topic NAME --bootstrap-server localhost:9092

# Delete
kafka/bin/kafka-topics.sh --delete --topic NAME --bootstrap-server localhost:9092

# Alter partitions
kafka/bin/kafka-topics.sh --alter --topic NAME --partitions N --bootstrap-server localhost:9092

# Modify config
kafka/bin/kafka-configs.sh --alter --entity-type topics --entity-name NAME --add-config KEY=VALUE --bootstrap-server localhost:9092
```

### Producer Operations
```bash
# Basic
kafka/bin/kafka-console-producer.sh --topic NAME --bootstrap-server localhost:9092

# With keys
kafka/bin/kafka-console-producer.sh --topic NAME --bootstrap-server localhost:9092 --property parse.key=true --property key.separator=:

# From file
kafka/bin/kafka-console-producer.sh --topic NAME --bootstrap-server localhost:9092 < file.txt

# With compression
kafka/bin/kafka-console-producer.sh --topic NAME --bootstrap-server localhost:9092 --producer-property compression.type=lz4

# With batching
kafka/bin/kafka-console-producer.sh --topic NAME --bootstrap-server localhost:9092 --producer-property batch.size=32768 --producer-property linger.ms=10
```

### Consumer Operations
```bash
# From latest
kafka/bin/kafka-console-consumer.sh --topic NAME --bootstrap-server localhost:9092

# From beginning
kafka/bin/kafka-console-consumer.sh --topic NAME --from-beginning --bootstrap-server localhost:9092

# With group
kafka/bin/kafka-console-consumer.sh --topic NAME --group GROUP --bootstrap-server localhost:9092

# With metadata
kafka/bin/kafka-console-consumer.sh --topic NAME --from-beginning --bootstrap-server localhost:9092 --property print.key=true --property print.partition=true --property print.offset=true --property print.timestamp=true

# Specific partition
kafka/bin/kafka-console-consumer.sh --topic NAME --partition N --from-beginning --bootstrap-server localhost:9092

# Limited messages
kafka/bin/kafka-console-consumer.sh --topic NAME --from-beginning --max-messages N --bootstrap-server localhost:9092
```

### Consumer Group Operations
```bash
# List groups
kafka/bin/kafka-consumer-groups.sh --list --bootstrap-server localhost:9092

# Describe group
kafka/bin/kafka-consumer-groups.sh --describe --group NAME --bootstrap-server localhost:9092

# Reset to earliest
kafka/bin/kafka-consumer-groups.sh --reset-offsets --group NAME --topic TOPIC --to-earliest --execute --bootstrap-server localhost:9092

# Reset to latest
kafka/bin/kafka-consumer-groups.sh --reset-offsets --group NAME --topic TOPIC --to-latest --execute --bootstrap-server localhost:9092

# Reset to timestamp
kafka/bin/kafka-consumer-groups.sh --reset-offsets --group NAME --topic TOPIC --to-datetime TIMESTAMP --execute --bootstrap-server localhost:9092

# Reset to offset
kafka/bin/kafka-consumer-groups.sh --reset-offsets --group NAME --topic TOPIC --to-offset N --execute --bootstrap-server localhost:9092

# Shift by N
kafka/bin/kafka-consumer-groups.sh --reset-offsets --group NAME --topic TOPIC --shift-by N --execute --bootstrap-server localhost:9092
```

### Monitoring Operations
```bash
# Get offsets
kafka/bin/kafka-get-offsets.sh --broker-list localhost:9092 --topic NAME --time -1

# List brokers
kafka/bin/zookeeper-shell.sh localhost:2181 ls /brokers/ids

# Topic configs
kafka/bin/kafka-configs.sh --describe --entity-type topics --entity-name NAME --bootstrap-server localhost:9092
```

### Cluster Operations
```bash
# Start ZooKeeper
./scripts/start-zookeeper.sh

# Start brokers
./scripts/start-broker-0.sh
./scripts/start-broker-1.sh
./scripts/start-broker-2.sh

# Stop all
./scripts/stop-all.sh

# Cleanup (deletes all data!)
./scripts/cleanup-logs.sh
```

---

## Next Steps

🎉 **Congratulations!** You've mastered Kafka basic operations!

**What You've Learned:**
- ✅ Topic lifecycle management
- ✅ Producing messages (simple, JSON, keyed, batched)
- ✅ Consuming messages (groups, offsets, parallel)
- ✅ Partition strategies and hot partition handling
- ✅ Advanced features (transactions, compaction, quotas)
- ✅ Real-world scenarios (e-commerce, fraud, analytics)

**What's Next?**

1. **docs/04-fault-tolerance-testing.md** 
   - Test broker failures
   - Partition reassignment
   - Replication recovery
   - Network partitions

2. **docs/05-replication-partitioning.md**
   - Deep dive: replication mechanics
   - ISR management
   - Leader election
   - Unclean leader election

3. **docs/06-python-integration.md**
   - Build real producers/consumers
   - Implement transactions
   - Handle errors gracefully
   - Production patterns

4. **docs/07-monitoring-setup.md**
   - Prometheus metrics
   - Grafana dashboards
   - Alerting rules
   - Performance tuning