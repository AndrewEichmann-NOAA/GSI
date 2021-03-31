#! /bin/sh
#SBATCH --job-name=EFSOI-unit-test
#SBATCH --account=da-cpu
##SBATCH --qos=batch
#SBATCH --qos=debug
#SBATCH --nodes=100-100
#SBATCH --tasks-per-node=1
#SBATCH --cpus-per-task=40
#SBATCH -t 00:30:00
##SBATCH -o EFSOItest.log
#SBATCH --export=NONE
#SBATCH --comment=8e38412bcdfd020306129acd89ee4811

source expdir/config.base

export TEST_ROOT='/scratch1/NCEPDEV/da/Andrew.Eichmann/testtest'

# the following are set in config.base in a regular experiment, but switched to here for clarity
# and accessbility

export EXPDIR=$TEST_ROOT'/expdir'


export SLURM_SET='YES'
export RUN_ENVIR='emc'
export CDATE='2019111918'
export PDY='20191119'
export cyc='18'
export CDUMP='gdas'

$HOMEgfs/jobs/rocoto/efsoi.sh

cd $ROTDIR/osense
cmp osense_2019111918_final_baseline.dat osense_2019111918_final.dat

