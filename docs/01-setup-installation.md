# Kafka Learning Lab - Setup and Installation Guide

## Step 1: Setup and Installation

### Prerequisites

- macOS (M1 chip)
- Java 17+ installed
- 16GB RAM, 8-core processor
- Terminal access

### Verify Java Installation

```bash
java -version
```

**Expected Output:**
```
OpenJDK version "17.0.15" 2025-04-15
```

---

## Project Structure Creation

### Navigate to Project Directory

```bash
cd ~/kafka-learning-lab
```

### Create All Directories and Files

```bash
# Create directory structure
mkdir -p docs config scripts python/producer python/consumer python/tests monitoring/grafana-dashboards

# Create documentation files
touch README.md \
      docs/01-setup-installation.md \
      docs/02-cluster-configuration.md \
      docs/03-basic-operations.md \
      docs/04-fault-tolerance-testing.md \
      docs/05-replication-partitioning.md \
      docs/06-python-integration.md \
      docs/07-monitoring-setup.md \
      docs/08-spark-integration.md \
      docs/09-troubleshooting.md

# Create configuration files
touch config/zookeeper.properties \
      config/server-0.properties \
      config/server-1.properties \
      config/server-2.properties

# Create shell scripts
touch scripts/start-zookeeper.sh \
      scripts/start-broker-0.sh \
      scripts/start-broker-1.sh \
      scripts/start-broker-2.sh \
      scripts/stop-all.sh \
      scripts/cleanup-logs.sh

# Create Python files
touch python/requirements.txt \
      python/producer/simple_producer.py \
      python/producer/batch_producer.py \
      python/consumer/simple_consumer.py \
      python/consumer/consumer_group.py \
      python/tests/test_producer.py \
      python/tests/test_consumer.py

# Create monitoring configuration
touch monitoring/prometheus.yml
```

### Verify Structure

```bash
tree -L 3
```

**Expected Directory Structure:**
```
kafka-learning-lab/
├── README.md
├── config/
│   ├── server-0.properties
│   ├── server-1.properties
│   ├── server-2.properties
│   └── zookeeper.properties
├── docs/
│   ├── 01-setup-installation.md
│   ├── 02-cluster-configuration.md
│   ├── 03-basic-operations.md
│   ├── 04-fault-tolerance-testing.md
│   ├── 05-replication-partitioning.md
│   ├── 06-python-integration.md
│   ├── 07-monitoring-setup.md
│   ├── 08-spark-integration.md
│   └── 09-troubleshooting.md
├── kafka/
├── monitoring/
│   ├── grafana-dashboards/
│   └── prometheus.yml
├── python/
│   ├── consumer/
│   │   ├── consumer_group.py
│   │   └── simple_consumer.py
│   ├── producer/
│   │   ├── batch_producer.py
│   │   └── simple_producer.py
│   ├── requirements.txt
│   └── tests/
│       ├── test_consumer.py
│       └── test_producer.py
└── scripts/
    ├── cleanup-logs.sh
    ├── start-broker-0.sh
    ├── start-broker-1.sh
    ├── start-broker-2.sh
    ├── start-zookeeper.sh
    └── stop-all.sh
```

---

## Download and Install Kafka

### Download Kafka 3.9.1 (Scala 2.13)

```bash
cd ~/kafka-learning-lab
curl -O https://downloads.apache.org/kafka/3.9.1/kafka_2.13-3.9.1.tgz
```

**Download Size:** 116 MB compressed

### Extract Archive

```bash
tar -xzf kafka_2.13-3.9.1.tgz
```

**Extracted Size:** ~250 MB

### Rename to Simple 'kafka' Directory

```bash
mv kafka_2.13-3.9.1 kafka
```

### Clean Up Archive

```bash
rm kafka_2.13-3.9.1.tgz
```

### Verify Kafka Installation

```bash
kafka/bin/kafka-topics.sh --version
```

**Expected Output:**
```
3.9.1
```

---

## Configure Git

### Create .gitignore for Runtime Files

```bash
cat > .gitignore << 'EOF'
# Kafka runtime logs and data
/tmp/
kafka-logs-*/
zookeeper/

# Python
__pycache__/
*.pyc
.pytest_cache/

# IDE
.vscode/
.idea/

# macOS
.DS_Store
EOF
```

### Initialize Git Repository (Optional)

```bash
git init
git add .
git commit -m "Initial Kafka Learning Lab setup"
```

---

## Installation Summary

| Component | Details |
|-----------|---------|
| **Kafka Version** | 3.9.1 |
| **Scala Version** | 2.13 |
| **Java Version** | 17.0.15 |
| **Installation Size** | ~250 MB |
| **Location** | `~/kafka-learning-lab/kafka/` |

---

## Verification Checklist

Before proceeding to the next step, ensure:

- [ ] Java 17+ is installed and verified
- [ ] All directories and files are created successfully
- [ ] Kafka is downloaded and extracted
- [ ] Kafka version command returns `3.9.1`
- [ ] `.gitignore` is created and configured
- [ ] Project structure matches the expected layout

---

## Next Steps

Once verification is complete, proceed to:

**Step 3: Configure ZooKeeper**

Run the verification command and confirm Kafka version displays correctly!

---

## Troubleshooting

### Java Version Issues

If Java version is incorrect:

```bash
# Check available Java versions
/usr/libexec/java_home -V

# Set Java 17 as default
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
```

### Download Issues

If download fails or is interrupted:

```bash
# Remove partial download
rm -f kafka_2.13-3.9.1.tgz

# Retry download with resume capability
curl -C - -O https://downloads.apache.org/kafka/3.9.1/kafka_2.13-3.9.1.tgz
```

### Permission Issues

If you encounter permission errors:

```bash
# Make scripts executable
chmod +x scripts/*.sh
```

---

**Created by:** Raghavendra  
**Date:** December 2025  
**Purpose:** Kafka Learning Lab - Hands-on Distributed Streaming Platform