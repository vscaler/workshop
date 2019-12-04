#!/bin/bash
echo openhpc_standard_packages:
yum list | grep OpenHPC | grep -E -v '^ |ndoutils-ohpc|nrpe-ohpc|ohpc-release-factory|python-Cython.|python-Cython-debuginfo|kmod-|gnu-|gnu7-|gnu8|intel-|slurm|munge|ganglia|nagios|warewulf|pbs|lustre|obs-'| awk '{print $1}' | sed -r 's|(.+)\..+|  - \1|'

echo openhpc_intel_packages:
yum list | grep OpenHPC | grep -E -v '^ |mvapich2-psm2|openmpi3-intel|lmod-defaults'|grep 'intel-'| awk '{print $1}' | sed -r 's|(.+)\..+|  - \1|'

echo openhpc_gnu_packages:
yum list | grep OpenHPC | grep -E -v '^ |mvapich2-psm2|openmpi3-gnu|lmod-defaults'|grep 'gnu-'| awk '{print $1}' | sed -r 's|(.+)\..+|  - \1|'

echo openhpc_gnu7_packages:
# mvapich2-psm2-gnu7-ohpc conflicts with mvapich2-gnu7-ohpc if we need the truescale version we can manually tweak
# openmpi3-pmix-slurm-gnu7-ohpc conflicts with openmpi3-gnu7-ohpc and we use slurm . . .
yum list | grep OpenHPC | grep -E -v '^ |mvapich2-psm2|openmpi3-gnu7|lmod-defaults'|grep 'gnu7-'| awk '{print $1}' | sed -r 's|(.+)\..+|  - \1|'

echo openhpc_gnu8_packages:
yum list | grep OpenHPC | grep -E -v '^ |mvapich2-psm2|openmpi3-gnu8|lmod-defaults'|grep 'gnu8-'| awk '{print $1}' | sed -r 's|(.+)\..+|  - \1|'

