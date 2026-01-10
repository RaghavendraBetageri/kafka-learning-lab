# Kafka Learning Lab 🚀

> **A comprehensive, hands-on Apache Kafka learning environment optimized for macOS M1 with 9 progressive learning modules, fault tolerance testing labs, and production-ready patterns.**

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Repository Structure](#repository-structure)
- [Learning Path](#learning-path)
- [Environment Setup](#environment-setup)


---

## Overview

**Kafka Learning Lab** is a production-grade learning environment designed to teach Apache Kafka through **hands-on experimentation** rather than passive reading. This repository contains:

- ✅ **Complete Kafka 3.9.1 Distribution** - Ready to run locally
- ✅ **9 Progressive Learning Modules** - From basics to advanced concepts
- ✅ **6 Fault Tolerance Labs** - Test real failure scenarios
- ✅ **3-Broker Cluster Setup** - Fully configured ZooKeeper + Kafka
- ✅ **Python Integration Examples** - Real producer/consumer code
- ✅ **Monitoring & Observability** - Prometheus/Grafana ready
- ✅ **Real-World Scenarios** - E-commerce, fraud detection, analytics

### Why This Lab?

Most Kafka tutorials are **theoretical**. This lab is **practical**:

| Traditional Tutorial | Kafka Learning Lab |
|---------------------|-------------------|
| Read about replication | Kill a broker, watch recovery happen |
| Study ISR concepts | Freeze a broker, observe ISR shrinkage |
| Learn about `acks` levels | Test data loss during failures |
| Understand consumer groups | Rebalance consumers while producing |
| Study configs | Adjust settings, measure impact |

---

## Quick Start

### Prerequisites

```bash
# Check Java version (17+ required)
java -version

# Check file descriptor limits (M1 Macs default too low)
ulimit -n
# If < 1000, increase: ulimit -n 10000
```

### 5-Minute Setup

```bash
# 1. Clone/navigate to project
cd ~/kafka-learning-lab

# 2. Start ZooKeeper (Terminal 1)
./scripts/start-zookeeper.sh

# 3. Start 3 Brokers (Terminals 2-4)
./scripts/start-broker-0.sh
./scripts/start-broker-1.sh
./scripts/start-broker-2.sh

# 4. Verify cluster health (Terminal 5)
./scripts/monitor-cluster.sh fault-test

# 5. Create a topic (Terminal 6)
./kafka/bin/kafka-topics.sh --create \
  --topic test-topic \
  --partitions 3 \
  --replication-factor 2 \
  --bootstrap-server localhost:9092

# 6. Produce messages (Terminal 7)
echo "Hello Kafka" | ./kafka/bin/kafka-console-producer.sh \
  --topic test-topic \
  --bootstrap-server localhost:9092

# 7. Consume messages (Terminal 8)
./kafka/bin/kafka-console-consumer.sh \
  --topic test-topic \
  --from-beginning \
  --bootstrap-server localhost:9092
```

**You now have a working 3-broker Kafka cluster!** 🎉

---

## Repository Structure

```
kafka-learning-lab/
├── README.md                             # This file (WIP)
├── .gitignore                            # Git configuration (WIP)
│
├── kafka/                                # Kafka 3.9.1 distribution (DONE)
│   ├── bin/                              # Executable scripts
│   ├── config/                           # Configuration templates
│   ├── libs/                             # JAR dependencies
│   └── logs/                             # Runtime logs
│
├── config/                               # Cluster configuration (DONE)
│   ├── zookeeper.properties              # ZooKeeper config
│   ├── server-0.properties               # Broker 0 (port 9092)
│   ├── server-1.properties               # Broker 1 (port 9093)
│   └── server-2.properties               # Broker 2 (port 9094)
│
├── docs/                                 # Learning modules (WIP)
│   ├── 01-setup-installation.md          # Environment setup (DONE)
│   ├── 02-cluster-configuration.md       # Deep dive: cluster config (DONE)
│   ├── 03-basic-operations.md            # Topics, producers, consumers (DONE)
│   ├── 04-fault-tolerance-testing.md     # 6 hands-on labs (DONE)
│   ├── 05-replication-partitioning.md    # Replication mechanics (Studying and planning)
│   ├── 06-python-integration.md          # Python clients (Future Plan)
│   ├── 07-monitoring-setup.md            # Prometheus/Grafana (Future Plan)
│   ├── 08-spark-integration.md           # Spark streaming (Future Plan)
│   └── 09-troubleshooting.md             # Common issues (Future Plan)
│
├── scripts/                              # Cluster management (WIP I will add scripts if we need in future)
│   ├── start-zookeeper.sh                # Start ZooKeeper
│   ├── start-broker-0.sh                 # Start broker 0
│   ├── start-broker-1.sh                 # Start broker 1
│   ├── start-broker-2.sh                 # Start broker 2
│   ├── stop-all.sh                       # Stop all services
│   ├── cleanup-logs.sh                   # Delete all data
│   └── monitor-cluster.sh                # Health dashboard
│
├── test-scripts/                         # Automated testing (WIP I will add scripts if we need in future)
│   ├── produce-messages.sh               # Send test messages
│   ├── consume-and-count.sh              # Consume and count
│   └── test-acks-during-failure.sh       # Automated failure tests
│
├── test-results/                         # Test output storage
│   └── kafka-consume-*.out               # Consumer output logs
│
├── python/                               # Python integration  (Future Plan)
│   ├── producer/                         # Producer examples
│   │   ├── simple_producer.py
│   │   └── batch_producer.py
│   ├── consumer/                         # Consumer examples
│   │   ├── simple_consumer.py
│   │   └── consumer_group.py
│   ├── tests/                            # Unit tests
│   │   ├── test_producer.py
│   │   └── test_consumer.py
│   └── requirements.txt                  # Python dependencies
│
└── monitoring/                           # Observability (Future Plan)
    ├── prometheus.yml                    # Metrics config
    └── grafana-dashboards/               # Dashboard JSON files
```

---

## Learning Path

### 🟢 **Beginner (2 hours)**

Start here if you're new to Kafka:

1. **01-setup-installation.md** (30 min)
   - Environment setup
   - Java verification
   - Kafka installation
   - Directory structure

2. **02-cluster-configuration.md** (30 min)
   - ZooKeeper role and configuration
   - 3-broker cluster architecture
   - Port assignments and log directories
   - Configuration parameter meanings

3. **03-basic-operations.md - Part 1** (1 hour)
   - Topic lifecycle (create, list, describe, delete)
   - Basic producing (console producer)
   - Basic consuming (console consumer)
   - Understanding partitions

**Deliverable:** You can create topics and send/receive messages.

---

### 🟡 **Intermediate (3 hours)**

Build deeper understanding:

1. **03-basic-operations.md - Part 2** (1.5 hours)
   - Producer properties and batching
   - Consumer groups and rebalancing
   - Offset management
   - Partition strategies and keys

2. **05-replication-partitioning.md** (1 hour)
   - Replication mechanics (leader/followers)
   - In-Sync Replicas (ISR) concept
   - Log segment structure
   - Replication factor trade-offs

3. **03-basic-operations.md - Part 3** (30 min)
   - Message headers and timestamps
   - Transactions and exactly-once semantics
   - Log compaction for state stores
   - Real-world scenarios (e-commerce, fraud detection)

**Deliverable:** You understand partitioning, replication, and consumer groups deeply.

---

### 🔴 **Advanced (4 hours)**

Master failure scenarios and production patterns:

1. **04-fault-tolerance-testing.md** (3 hours)
   - **Lab 1:** Leader broker failure & recovery (20 min)
   - **Lab 2:** ISR behavior during broker freeze (20 min)
   - **Lab 3:** Testing min.insync.replicas durability (20 min)
   - **Lab 4:** Multiple broker failures & quorum loss (20 min)
   - **Lab 5:** Producer behavior during failures (1 hour)
     - Test `acks=0` (fire-and-forget)
     - Test `acks=1` (leader only)
     - Test `acks=all` (full ISR)
   - **Lab 6:** Consumer rebalancing during failures (20 min)
   - Best practices & production recommendations (20 min)

2. **06-python-integration.md** (1 hour)
   - Building real producers with kafka-python
   - Consumer groups in production
   - Error handling and retries
   - Idempotent producers
   - Transaction support

**Deliverable:** You can design Kafka systems for production use and handle failures gracefully.

---

### 🎯 **Optional: Production Deep Dives**

1. **07-monitoring-setup.md**
   - Prometheus metrics collection
   - Grafana dashboard setup
   - Alerting rules
   - Performance monitoring

2. **08-spark-integration.md**
   - Structured Streaming with Kafka
   - Processing streaming data
   - Windowing and aggregations

3. **09-troubleshooting.md**
   - Common production issues
   - Debugging techniques
   - Log analysis
   - Performance tuning

---

## Environment Setup

### System Requirements

| Component | Requirement | Notes |
|-----------|-------------|-------|
| **OS** | macOS (M1/M2 optimized) | Linux/Windows also supported |
| **Java** | 17+ | `java -version` to check |
| **Disk Space** | 500 MB free | For Kafka + test data |
| **RAM** | 4+ GB | For 3 brokers + ZooKeeper |
| **Ulimit** | 10,000+ | See quick start above |

### macOS M1-Specific Setup

```bash
# Check current file descriptor limit
ulimit -n

# Temporarily increase (current session only)
ulimit -n 10000

# Make permanent (add to ~/.zshrc or ~/.bash_profile)
echo 'ulimit -n 10000' >> ~/.zshrc
source ~/.zshrc

# Verify
ulimit -n  # Should show 10000
```

### Port Assignments

| Service | Port | Configuration |
|---------|------|---------------|
| **ZooKeeper** | 2181 | `config/zookeeper.properties` |
| **Broker 0** | 9092 | `config/server-0.properties` |
| **Broker 1** | 9093 | `config/server-1.properties` |
| **Broker 2** | 9094 | `config/server-2.properties` |
| **Prometheus** | 9090 | `monitoring/prometheus.yml` |
| **Grafana** | 3000 | (if configured) |

### Data Directory Structure

```bash
# ZooKeeper data
/tmp/zookeeper/version-2/

# Kafka broker logs (one per broker)
/tmp/kafka-logs-0/      # Broker 0
/tmp/kafka-logs-1/      # Broker 1
/tmp/kafka-logs-2/      # Broker 2

# Example partition directory structure
/tmp/kafka-logs-0/topic-name-0/
├── 00000000000000000000.index
├── 00000000000000000000.log
├── 00000000000000000000.timeindex
├── leader-epoch-checkpoint
└── partition.metadata
```

### Cluster Configuration Details

#### ZooKeeper (config/zookeeper.properties)

```properties
# Data directory
dataDir=/tmp/zookeeper

# Listen port for clients (Kafka connects here)
clientPort=2181

# Server list for ensemble (single node setup)
server.0=localhost:2888:3888
```

**Key Concepts:**
- ZooKeeper maintains cluster metadata
- Broker leader election coordinator
- Consumer group coordination
- Configuration storage

#### Broker Configuration (config/server-0.properties)

```properties
# Unique broker ID
broker.id=0

# Listen port
listeners=PLAINTEXT://localhost:9092

# ZooKeeper connection
zookeeper.connect=localhost:2181

# Log storage
log.dirs=/tmp/kafka-logs-0

# Replication and durability
default.replication.factor=3
min.insync.replicas=2
log.flush.interval.messages=10000
```

**Key Settings Explained:**
- `broker.id`: Unique identifier (0, 1, 2 in our setup)
- `listeners`: Network endpoint for clients
- `zookeeper.connect`: ZooKeeper cluster address
- `log.dirs`: Where partition data is stored
- `default.replication.factor`: Default copies of data
- `min.insync.replicas`: Replicas that must ack for durability
