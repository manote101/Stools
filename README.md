# First of all, enable required parameters in slurm.conf:
PriorityType=priority/multifactor
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageEnforce=associations,limits,qos

# Configure schedule to clear Usage logs (may use Daily duing test perid)
PriorityUsageResetPeriod=Monthly

# Restart services in slurm master:
systemctl restart slurmdbd
systemctl restart slurmctld

# Restart slurm services in all worker nodes:
systemctl restart slurmdbd
