#!/bin/bash
#SBATCH -A ai-lab
#SBATCH --job-name=test-billing
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --gres=gpu:1
#SBATCH --time=00:10:00

nvidia-smi
sleep 120
