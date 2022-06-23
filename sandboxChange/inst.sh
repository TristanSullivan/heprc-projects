#!/bin/bash

if [ ! -z $DIRAC ]
then
  tar -xf filemods.tar

  cp storeSandbox.py $DIRAC/BelleDIRAC/gbasf2/lib/job/storeSandbox.py
  cp gbasf2.py $DIRAC/BelleDIRAC/gbasf2/lib/gbasf2.py
  cp projectCLController.py $DIRAC/BelleDIRAC/Client/controllers/projectCLController.py

  rm -f storeSandbox.py gbasf2.py projectCLController.py
else
  echo "Please source gbasf2 bashrc file before running"
  exit 1
fi
