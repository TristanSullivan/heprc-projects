#!/bin/bash

function run_workload(){
  filename=$1
  arrName=$2[@]
  evArr=("${!arrName}")

  echo ${evArr[@]}

  for i in ${evArr[@]}
  do
    sed -i "s/events:.*/events:\ $i/g" $filename
    ./$filename
  done

  mkdir workdir/suite_results/$filename
  mv workdir/suite_results/run* /workdir/suite_results/$filename

}


ali=( 1 2 3 4 5 10 20 )
run_workload alice.sh ali

gs=( 50 150 200 250 500 1000 ) #default 200
run_workload atlas-gen-sherpa.sh gs

recomt=( 25 50 75 100 150 200 500 ) # default 100
run_workload atlas-reco.sh recomt

#belle2.sh  
b2=( 10 25 40 50 75 100 200 ) #default 50
run_workload belle2.sh b2

#cms-digi,cms-reco default 50
run_workload cms-digi.sh b2
run_workload cms-reco.sh b2

#cms-gen-sim default 20
cgs=( 5 10 15 20 25 40 100 )
run_workload cms-gen-sim.sh cgs

#lhcb default 5
lhcb=( 2 3 5 7 10 20 )
run_workload lhcb.sh lhcb
