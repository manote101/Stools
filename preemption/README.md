Phase 1: Global Configuration (slurm.conf)
Slurm does not enable preemption by default. We must enable the plugin and define the mechanism.
1. Edit your slurm.conf file: Locate and modify (or add) the following parameters.
```bash
# 1. Enable the QoS Preemption Plugin 
PreemptType=preempt/qos

# 2. Define the Action (Choose ONE based on your needs) in slurm.conf

# OPTION A: CANCEL (The snail dies immediately)
# Best for: Ensuring resources are freed instantly; low-priority work is disposable.
PreemptMode=CANCEL

# OPTION B: REQUEUE (The snail stops, goes back to queue, and restarts later)
# Best for: Short jobs or if you 

# OPTION C: SUSPEND (The snail pauses in memory)
# Best for: Saving the snail's progress. Warning: Memory is still occupied.
# PreemptMode=SUSPEND,GANG
```

2. Push the configuration: Once saved, you must reconfigure the cluster.
```bash
scontrol reconfigure
```

## Create the QoS
```bash
sacctmgr add qos snail set Priority=100
sacctmgr add qos rabbit set Priority=300 Preempt=snail
# Example: modifying an existing user 'alice'
sacctmgr modify user where name=alice set QoS=rabbit,snail
```
