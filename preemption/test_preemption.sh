#!/bin/bash

# Configuration
QOS_LOW="snail"
QOS_HIGH="rabbit"
PARTITION="defq" # Change this if your default partition has a different name

echo "=============================================="
echo "🐰 SLURM PREEMPTION TESTER: Snail vs Rabbit 🐌"
echo "=============================================="

# 1. Submit the Snail (Low Priority)
# We use sleep 180 to ensure it runs long enough to be preempted
echo "[1/4] Submitting Low Priority '$QOS_LOW' job..."
SNAIL_JOB=$(sbatch --qos=$QOS_LOW --partition=$PARTITION --job-name=SNAIL_TEST -c 150 --wrap="sleep 180" --parsable)

if [ -z "$SNAIL_JOB" ]; then
    echo "Error: Failed to submit Snail job."
    exit 1
fi
echo " -> Snail Job ID: $SNAIL_JOB submitted."

# 2. Show of Snail job to start Running
echo
echo "[2/4] Waiting for Snail to enter RUNNING state..."
squeue --job=$SNAIL_JOB | grep $SNAIL_JOB

# 3. Submit the Rabbit (High Priority)
echo
echo "[3/4] Submitting High Priority '$QOS_HIGH' job..."
RABBIT_JOB=$(sbatch --qos=$QOS_HIGH --partition=$PARTITION --job-name=RABBIT_TEST -c 150 --wrap="sleep 120" --parsable)
echo " -> Rabbit Job ID: $RABBIT_JOB submitted."

# 4. Monitor the Queue
echo
echo "[4/4] Monitoring preemption in real-time (5 seconds)..."
echo "-----------------------------------------------------"
echo "JOBID    NAME         QOS      STATE"
echo "-----------------------------------------------------"

for i in {1..5}; do
    # Display just the relevant jobs
    squeue --job=$SNAIL_JOB,$RABBIT_JOB --format="%.8i %.12j %.8q %.2t" --noheader
    echo "-----------------------------------------------------"
    sleep 1
done

echo
echo "Current running jobs"
squeue -u $USER

echo "Test Complete."
