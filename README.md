###TRES Quota & Usage Checker

This Python script processes Slurm account/user quota data and reports when CPU or GPU usage exceeds a specified percentage threshold of the allocated quota.

The script accepts:

  - **tres_percent** — usage threshold (%)

  - **filename** — input text file containing account/user quota data

It parses each line, classifies it as an Account, User, or Root entry, extracts CPU/GPU quota and usage, and prints alerts when thresholds are exceeded.

First, you have to run Slurm sshare command to get usage data from the cluster
```bash
sshare -ha -o Account,User,GrpTRESMins,GrpTRESRaw -Pn > usage_data.txt 
```

Then run 
```bash
python check_highusage.py 70 usage_data.txt
```
