#!/bin/bash

#####################################################################
# This script of example installs and runs the HEP-Benchmark-Suite
# The Suite configuration file
#       bmkrun_config.yml
# is included in the script itself.
# The configuration script enables the benchmarks to run
# and defines some meta-parameters, including tags as the SITE name.
#
# In this example only the HEP-score benchmark is configured to run.
# It runs with a slim configuration hepscore_slim.yml ideal to run
# in grid jobs (average duration: 40 min)
#
# The only requirements to run are
# git python3-pip singularity
#####################################################################

#--------------[Start of user editable section]---------------------- 
SITE=CA-UVic-Cloud  # Replace somesite with a meaningful site name
PUBLISH=true  # Replace false with true in order to publish results in AMQ
CERTIFKEY=/root/cernkey.pem  
CERTIFCRT=/root/cerncert.pem
#--------------[End of user editable section]------------------------- 


echo "Running script: $0"
cd $( dirname $0)

WORKDIR=$(pwd)/workdir
RUNDIR=$WORKDIR/suite_results
LOGFILE=$WORKDIR/output.txt
SUITE_CONFIG_FILE=bmkrun_config.yml
HEPSCORE_CONFIG_FILE=hepscore_config.yml

SERVER=dashb-mb.cern.ch
PORT=61123
TOPIC=/topic/vm.spec

GREEN='\033[0;32m'
CYAN='\033[0;36m'
ORANGE='\033[1;33m'
NC='\033[0m' # No Color

echo "Creating the WORKDIR $WORKDIR"
mkdir -p $WORKDIR
chmod a+rw -R $WORKDIR

cat > $WORKDIR/$HEPSCORE_CONFIG_FILE <<'EOF'
hepscore_benchmark:
  benchmarks:
      atlas-reco_mt-bmk:
        results_file: atlas-reco_mt_summary.json
        ref_scores:
          reco: 1
        weight: 1.0
        version: v0.1
        args:
          threads: 4
          events: 500
  settings:
    name: HEPscore20POC
    reference_machine: "CPU Intel(R) Xeon(R) CPU E5-2630 v3 @ 2.40GHz"
    registry: dir:///cvmfs/unpacked.cern.ch/gitlab-registry.cern.ch/hep-benchmarks/hep-workloads
    ##registry: oras://registry.cern.ch/hep-workloads
    method: geometric_mean
    repetitions: 3
    retries: 1
    scaling: 0
    container_exec: singularity
EOF

cat > $WORKDIR/$SUITE_CONFIG_FILE <<EOF2
activemq:
  server: $SERVER
  topic: $TOPIC
  port: $PORT
  ## include the certificate full path (see documentation)
  key: $CERTIFKEY
  cert: $CERTIFCRT

global:
  benchmarks:
  - hepscore
  mode: singularity
  publish: $PUBLISH
  rundir: $RUNDIR
  show: true
  tags:
    site: $SITE
    purpose: "TF measurements"
hepscore:
  config: $WORKDIR/$HEPSCORE_CONFIG_FILE
  version: v1.4
  options:
      userns: True
      clean: True
EOF2

cd $WORKDIR
export MYENV="env_bmk"        # Define the name of the environment.
python3.8 -m venv $MYENV        # Create a directory with the virtual environment.
source $MYENV/bin/activate    # Activate the environment.

# Select Suite wheel version
PKG_VERSION="latest"          # The latest points always to latest stable release

# Select Python3 version (py37, py38)
PY_VERSION="py38"

if [ $PKG_VERSION = "latest" ];
then
  echo "Latest release selected."
  PKG_VERSION=$(curl --silent https://hep-benchmarks.web.cern.ch/hep-benchmark-suite/releases/latest)
fi

wheels_version="hep-benchmark-suite-wheels-${PY_VERSION}-${PKG_VERSION}.tar"
echo -e "-> Downloading wheel: $wheels_version \n"

curl -O "https://hep-benchmarks.web.cern.ch/hep-benchmark-suite/releases/${PKG_VERSION}/${wheels_version}"
tar xvf ${wheels_version}
python3.8 -m pip install suite_wheels/*.whl
cat $SUITE_CONFIG_FILE

# Ensure there is no suite running already
PS_AUX_BMKRUN=$(ps aux | grep -c bmkrun)
if (( PS_AUX_BMKRUN > 1 ));
then
  echo -e "${ORANGE}Another instance of the HEP Benchmark Suite is already running. Please wait for it to finish before running the suite again.${NC}"
  exit 1
fi

MEM_BEFORE=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
bmkrun  --verbose -c $SUITE_CONFIG_FILE | tee -i $LOGFILE
MEM_AFTER=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)

RESULTS=$(awk '/Full results can be found in.*/ {print $(NF-1)}' $LOGFILE)
RUNDIR_DATE=$(perl -n -e'/^.*(run_2[0-9]{3}-[0-9]{2}-[0-9]{2}_[0-9]{4}).*$/ && print $1; last if $1' $LOGFILE)
SUITE_SUCCESSFUL=$(! grep -q ERROR $LOGFILE; echo $?)
AMQ_SUCCESSFUL=$(grep -q "Results sent to AMQ topic" $LOGFILE; echo $?)
rm -f $LOGFILE

# Create log tar if there were errors
if [ $SUITE_SUCCESSFUL -ne 0 ] && [ $RUNDIR_DATE ] ;
then
  LOG_TAR="${SITE}_${RUNDIR_DATE}.tar"
  find $RUNDIR/$RUNDIR_DATE/ \( -name archive_processes_logs.tgz -o -name hep-benchmark-suite.log -o -name HEPscore*.log \) -exec tar -rf $LOG_TAR {} &>/dev/null \;
  echo -e "${CYAN}\nThe suite has run into errors. If you need help from the administrators, please contact them by email and attach ${WORKDIR}/${LOG_TAR} to it ${NC}"
fi

# Show how to send results afterwards
if [ $RESULTS ] && { [ $PUBLISH == false ] || [ $AMQ_SUCCESSFUL -ne 0 ] ; };
then
  echo -e "${GREEN}\nThe results were not sent to AMQ. In order to send them, you can run:"
  echo -e "${WORKDIR}/${MYENV}/bin/python3.8 ${WORKDIR}/${MYENV}/lib/python3.8/site-packages/hepbenchmarksuite/plugins/send_queue.py --port=$PORT --server=$SERVER --topic $TOPIC --key $CERTIFKEY --cert $CERTIFCRT --file $RESULTS ${NC}"
fi

# Print warning message in case of memory increase
MEM_DIFF=$(($MEM_AFTER - $MEM_BEFORE))
if (( MEM_DIFF > 1048576 )); then
  echo -e "${ORANGE}The memory usage has increased by more than 1 GB since the start of the script. Please check there are no zombie processes in the machine before running the script again.${NC}"
fi

echo -e "\nYou are in python environment $MYENV. run \`deactivate\` to exit from it"
