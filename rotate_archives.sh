#!/bin/bash

thisMonth=$(date +%m%y)
lastMonth=$(date -d "1 month ago" +%m%y)
twoMonths=$(date -d "2 months ago" +%m%y)
oneYearAgo=$(date -d "13 months ago" +%m%y)

wkdir="/home/mfens98/apel/archive"
logFile=$wkdir/../logs/archiveRotate$thisMonth.log

archives=($wkdir/*)

echo "$(date) Rotating Record Archives..." >> $logFile
for arch in ${archives[@]}
do
  case $arch in
    *"$oneYearAgo"*) #delete records older than 1 year
      rm -f $arch
    ;;
    
    *"$twoMonths"*) #compress records at 2 months old
      gzip -9 -S .gz $arch
    ;;

    *"$lastMonth"*) #make new record files for this month
      echo "APEL-individual-job-message: v0.3" > ${arch::-4}$thisMonth
    ;;
  esac
done >> $logFile 2>&1

echo "Compressing Old accounting logs and deleting even older ones..." >> $logFile
rm -f $wkdir/../logs/accountingLog.log.archive.old.gz
gzip -9 -S .old.gz $wkdir/../logs/accountingLog.log.archive >> $logFile 2>&1

rm -f $wkdir/../logs/ssmsend.log.old.gz
gzip -9 -S .old.gz $wkdir/../logs/ssmsend.log >> $logFile 2>&1

echo "Done!" >> $logFile
