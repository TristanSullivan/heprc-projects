#!/bin/bash

function get_ISO_diff(){
  unset ISOdiff d h m s
  d=$(bc <<< "${1}/86400")
  h=$(bc <<< "(${1}%86400)/3600") 
  m=$(bc <<< "(${1}%3600)/60")
  s=$(bc <<< "${1}%60")

  if [ "$d" == "0" ] || [ "$d" == "" ]
  then
    ISOdiff=$(printf "PT%02dH%02dM%05.2fS" $h $m $s)
  else
    ISOdiff=$(printf "P%02dDT%02dH%02dM%05.2fS" $d $h $m $s)
  fi 
}

function write_messages(){
  
  echo "Site: ${content[Site]}"
#  echo "Status: ${content[JobStatus]}"
  echo "SubmitHost: ${content[SubmitHost]}"
  echo "MachineName: ${content[MachineName]}"
  echo "LocalJobId: ${content[LocalJobId]}"
  echo "LocalUserId: ${content[LocalUserId]}"
  echo "VO: ${content[VO]}"
  echo "WallDuration: ${content[WallDuration]}"
  echo "CpuDuration: ${content[CpuDuration]}"
  echo "Processors: ${content[Processors]}"
  echo "StartTime: ${content[StartTime]}"
  echo "EndTime: ${content[EndTime]}"
  echo "ServiceLevelType: ${content[ServiceLevelType]}"
  echo "ServiceLevel: ${content[ServiceLevel]}"
  echo "%%"

}

function site_error(){
  >&2 echo "ERROR: Site not found! You may be using a cloud/group that hasn't been added to the script yet ($1)"

}

function fail(){
  >&2 echo "Error: ${1}"
  return 0 # want script to continue
}

function debug_log(){
  if [ $DEBUG == "true" ]
  then
    echo "DEBUG: ${1}"
  fi
}

function parse_history(){
declare -A content
while read -r line
do
  IFS=" " read -ra linearr <<< "$line" 
  #echo "$line"
  case "$line" in

    *GlobalJobId*) #LocalJobId
      debug_log "JobId"
      fullID=${linearr[2]}
      IFS="#" read -ra IdArr <<< "$fullID" || fail "Couldn't get JobID"
      content[LocalJobId]=${IdArr[1]}
      debug_log "Job ID: $fullID"
    ;;

    *Owner*) #UserId
      debug_log "userID"
      content[LocalUserId]=${linearr[2]}
    ;;

#    *JobStatus*)
#      debug_log "Jobstatus"
#      code=${linearr[2]}
#
#      case "$code" in
#
#      1)
#        content[JobStatus]='queued'
#      ;;
#
#      2|6)
#        content[JobStatus]='started'
#      ;;
#
#      3)
#        content[JobStatus]='aborted'
#      ;;
#
#      4)
#        content[JobStatus]='completed'
#      ;;
#
#      5)
#        content[JobStatus]='held'
#      ;;
#
#      7)
#        content[JobStatus]='suspended'
#      ;;
#
#      *)
#        content[JobStatus]='unknown'
#      ;;
#
#      esac
#    ;;

    *RemoteWallClockTime*) #Wall Duration
      debug_log "wall time"
      wallSeconds=${linearr[2]}
      #get_ISO_diff ${linearr[2]} || fail "Converting wall time seconds to iso duration"
      content[WallDuration]=${wallSeconds%.*}
    ;;

    *CumulativeRemoteUserCpu*) #divide by number of cores at end
      debug_log "cpu time"
      cpuSeconds=${linearr[2]}
      #content[CpuSeconds]=$cpuSeconds
    ;;

    *JobStartDate*)
      debug_log "start time"
      startEpoch=${linearr[2]}
      content[StartTime]=$startEpoch    #$(date -d @"${linearr[2]}" -u +%Y-%m-%dT%H:%M:%SZ) || fail "Converting start time (in epoch) to ISO date"
    ;;

    *EnteredCurrentStatus*)
      debug_log "Alt end time"
      statusTime=${linearr[2]}
      #content[EndTime]=$(date -d @"${linearr[2]}" -u +%Y-%m-%dT%H:%M:%SZ)
    ;;

    *RemoteHost*) #machine name, submit host, VO, takes RemoteHost or LastRemoteHost
      
      if [[ $line == *"Last"* ]] || [[ "$groupName" == "" ]] #LastRemoteHost takes precedence over RemoteHost
      then
        debug_log "Getting Machine Name, Host VO..."

        machineAndSlot=${linearr[2]}
        debug_log "MachineAndSlot: $machineAndSlot"
        IFS="@" read -ra namearr <<< "$machineAndSlot" || fail "Reading host into array"
        debug_log "Name arr: ${namearr[@]}"
        fullName=${namearr[1]}
        content[MachineName]=$(echo $fullName | tr -d "\'\"")

        delim="--" #split machine name using "--" as delimiter
        s=$fullName$delim
        debug_log "s=fullNamedelim: $s"
        vmDetails=()
        while [[ $s ]]
        do
          vmDetails+=( "${s%%"$delim"*}" )
          s=${s#*"$delim"}
        done
        debug_log "vmDetails array: ${vmDetails[@]}"
        groupName=${vmDetails[0]}
        cloudName=${vmDetails[1]}
        case $groupName in
          *atlas*)
            content[SubmitHost]='csv2a.heprc.uvic.ca'
            content[VO]='atlas'
          ;;
          belle-validation)
            content[SubmitHost]='belle-sd.heprc.uvic.ca'
            content[VO]='belle'
          ;;
          *belle*)
            content[SubmitHost]='bellecs.heprc.uvic.ca'
            content[VO]='belle'
          ;;
          dune)
            content[SubmitHost]='dune-condor.heprc.uvic.ca'
            content[VO]='dune'
          ;;
          babar)
            content[SubmitHost]=""
          ;;
          testing)
            content[SubmitHost]=""
          ;;
          *)
            >&2 echo "ERROR: Unable to get submit host (HTCondor FQDN)"
          ;;
        esac
      fi
    ;;

    *MATCH_EXP_MachineHEPSPEC*)
      debug_log "hepspec"
      content[ServiceLevelType]="HEPSPEC"
      content[ServiceLevel]=$(echo "${linearr[2]}" | tr -d "\'\"")
    ;;

    *CpusProvisioned*|*MachineAttrCpus*) #same thing but different names
      debug_log "Processors"
      content[Processors]=${linearr[2]}
    ;;

    *RequestCpu*)
      debug_log "Requested cpus"
      cpuRequest=${linearr[2]}  
    ;;

    "") #When we get a newline we can write a record and clear our dictionary
        #also get site/queue names since using requirements string and vm name
      debug_log "Final stuff"
      #echo "Checking time and status for ID: ${content[LocalJobId]}"
      
      if [[ "$startEpoch" == "" || $(bc <<< "$statusTime-$startEpoch == 0") -eq 1 ]]
      then
        debug_log "Got aborted job with 0 wall time or no start time, not writing. Clearing vars."
        let nullRecords=$nullRecords+1
        debug_log "Unsetting at aborted"
        unset content code fullName delim s groupName cloudName startEpoch endEpoch statusTime recordFileName recordFileDir recordFilePath cpuPerCore wallSeconds machineAndSlot
        declare -A content 
        continue
      fi

      if [ $statusTime -gt $(date -d "Yesterday 23:59:59" -u +%s) ] #start time between yesterday 00:00:00 and yesterday 23:59:59
      then  #newer than yesterday
        if [ $progression != "-1" ]
        then
          debug_log "Got records that are too new..."
          progression="-1"
        fi
        debug_log "Unsetting at records too new"
        unset content code fullName delim s groupName cloudName startEpoch endEpoch statusTime recordFileName recordFileDir recordFilePath cpuPerCore wallSeconds machineAndSlot
        declare -A content 
        continue #get to the next record since reverse chronological order
      elif [ $statusTime -lt $(date -d "Yesterday 00:00:00" -u +%s) ]
      then
        if [ $progression != 1 ]
        then
          debug_log "Got a record that is too old, continuing just in case..."
          progression=1
        fi
        oldRecordDate=$statusTime #get this value so we can see where salvaged records are near to decide if we need to extend our leeway time
        debug_log "Unsetting at record too old"
        unset content code fullName delim s groupName cloudName startEpoch endEpoch recordFileName recordFileDir recordFilePath cpuPerCore wallSeconds machineAndSlot #dont unset status time yet!
        declare -A content
        if [ $statusTime -lt $(date -d "3 days ago 00:00:00" -u +%s) ]
        then
          unset statusTime
          endOfRecords="true"
          debug_log "End of leeway, exiting"
          break
        else
          debug_log ">>>>>>> Reached end of yesterday's records >>>>"
          flag="true"
          unset statusTime
          continue #all other records should be older than this but give some leeway since record not exatly in order
        fi
      fi

      if [ $progression != "0" ]
      then
        debug_log "Writing records from yesterday!"
        progression=0
      fi

      #echo "Doing final stuff"
      if "$flag"
      then
        let salCount=$salCount+1
        oldestDate=$oldRecordDate
        debug_log ">>>>>>>Salvaged a record from yesterday that was amongst records that are too old (near time $(date -d @"$oldRecordDate" -u)) >>>>>>>>"

      fi
      #calculate end time
      #echo "End time calculation"
      if [ $(bc <<< "$wallSeconds >= 0") -eq 1 ] #bc true is 1 
      then
          endEpoch=$(bc <<< "scale=0; $startEpoch+$wallSeconds")
          #endEpoch=$(bc <<< "scale=0; $startEpoch+$wallSeconds") || fail "Calculating end time (since epoch)"
          content[EndTime]=${endEpoch%.*}   #$(date -d @"$endEpoch" -u +%Y-%m-%dT%H:%M:%SZ) || fail "Converting end time to ISO date (if condition), tried to convert: $endEpoch"
      else #got negative wall time so use entered current status time as end time and get other values from there
        wallSeconds=$(bc <<< "scale=0; $statusTime-$startEpoch")
        content[EndTime]=${statusTime%.*} #$(date -d @"$statusTime" -u +%Y-%m-%dT%H:%M:%SZ) || fail "Converting end time to ISO date (else condition), tried to convert: $statusTime"
        #get_ISO_diff $wallSeconds || fail "Converting walltime to iso time duration"
        content[WallDuration]=${wallSeconds%.*} #$ISOdiff
      fi    

      case $groupName in #set SITE
        atlas-cern)
          #use cloud name to set site
          case $cloudName in
            *cern*)
              #cern site
              content[Site]="CERN-PROD" #is this correct?
              recordFileName="cern_record"
            ;;
            *hephy*)
              #hephy site
              content[Site]="HEPHY-UIBK"
              recordFileName="hephy_record"
            ;;
            *lrz*) #may have _cloud
              #lrz site
              content[Site]="LRZ-LMU"
              recordFileName="lrz_record"
            ;;
            *ecdf*)
              #ecdf site
              content[Site]="UKI-SCOTGRID-ECDF" #add cloud or other vo?
              recordFileName="ecdf_record"
            ;;
            *)
              site_error "Cern group but unkown cloud: $cloudName, so unknown site"
              content[Site]=""
              recordFileName=""
            ;;
          esac
        ;;
        atlas-uk)
          #set site as ecdf? currently not in use
          content[Site]="UKI-SCOTGRID-ECDF" #do we need to add _cloud or some other VO? 
          recordFileName="ecdf_record"
        ;;
        atlas-uvic|belle)
          #set to uvic site
          content[Site]="CA-UVic-Cloud" #is anything different for atlas/belle? or is this specified elsewhere (ie VO, submit host)
          recordFileName="uvic_record"
        ;;
        australia-belle)
          #set to melbourne site
          content[Site]="Australia-T2"
          recordFileName="melbourne_record"
        ;;
        babar)
          #skip record process
          content[Site]="babar"
          recordFileName=""
        ;;
        desy-belle)
          #desy site
          content[Site]="DESY-HH" #also a desy-zn site
          recordFileName="desy_record"
        ;;
        belle-validation)
          case $cloudName in

            *desy*)
              content[Site]="DESY-HH"
              recordFileName="desy_record"
            ;;
            *otter*|*beaver*|*heprc*)
              content[Site]="CA-UVic-Cloud"
              recordFileName="uvic_record"
            ;;
            *)
              content[Site]="CA-UVic-Cloud"
              recordFileName="uvic_record"
              fail "Got unknown cloud name for belle-validation: $cloudName. Assuming it's UVIC and continuing..."
            ;;
          esac
        ;;

        dune)
          #dune site (Marcus looking into)
          content[Site]="CA-DUNE"
          recordFileName="dune_record"
        ;;
        "")
          site_error "Group not listed: $groupName (JobStatus: ${content[JobStatus]}) (CloudName: $cloudName) (MachineandSlot: $machineAndSlot)"
          content[Site]=""
          recordFileName=""
        ;;

      esac

      if [ "${content[Processors]}" == "" ]
      then
        content[Processors]=$cpuRequest
      fi

      #calculate cpu time
      #echo "cpu/core calculation"
      cpuPerCore=$(bc <<< "scale=3; $cpuSeconds/${content[Processors]}") || fail "Calculating cpu time per core"

      #get_ISO_diff $cpuPerCore || fail "Setting cpu/core to iso time duration"
      content[CpuDuration]=${cpuPerCore%.*} #$ISOdiff

      #if remotewallclocktime negative use epoch times      
      #let wallTime=$endEpoch-$startEpoch
      #get_ISO_diff $wallTime
      #content[WallDuration]=$ISOdiff
      #echo "Hepspec setting if not set already"
      if [ "${content[ServiceLevel]}" == "" ]
      then
        content[ServiceLevelType]="HEPSPEC"
        content[ServiceLevel]="0.00"
        fail "HEPSPEC not specified! Setting to 0.00"
        unset content code fullName delim s groupName cloudName startEpoch endEpoch recordFileName recordFileDir recordFilePath cpuPerCore wallSeconds machineAndSlot statusTime
        declare -A content
        debug_log "Unsetting since HEPSPEC undefined"
        continue
      fi

 

      #if babar or testing job do not record!
      #echo "deciding to write out"
      case $groupName in
        babar|testing)
          #recordFilePath="/dev/null" #put file name in now so can easily add later
          #write_messages >> $recordFilePath
          #do nothing
        ;;
        *atlas*|*belle*|*dune*)
          if [ "$wallSeconds" != "0" ] #if job was aborted and didn't run don't log it
          then
            recordFileDir=${2}
            if [[ "$recordFileName" == *"uvic"* ]] #if recording for uvic add vo name 
            then
              recordFilePath=$recordFileDir${content[VO]}-$recordFileName$dateSuffix.alog
            else
              recordFilePath=$recordFileDir$recordFileName$dateSuffix.alog
            fi
            if [ ! -s "$recordFilePath" ] #if no file exists then add the header
            then
              echo "APEL-individual-job-message: v0.3" > $recordFilePath
            fi
            write_messages >> $recordFilePath
            let recordsWritten=$recordsWritten+1
            #echo "Writing Out!"
          fi
        ;;
        *)
          >&2 echo "ERROR: Unknown group: $groupName (not atlas, belle or dune), not writing record (JobStatus: ${content[JobStatus]}) (JobID: ${content[LocalJobId]})"
      esac
      debug_log "Unsetting at end of function"
      unset content code fullName delim s groupName cloudName startEpoch endEpoch statusTime recordFileName recordFileDir recordFilePath cpuPerCore wallSeconds machineAndSlot
      declare -A content
      debug_log "Starting next entry"
      debug_log
      debug_log
    ;;

  esac

done < <(condor_history -long -file ${1} | grep "^GlobalJobId\|^Owner\|^RemoteWallClockTime\|^CumulativeRemoteUserCpu\|^JobStartDate\|^EnteredCurrentStatus\|^LastRemoteHost\|^RemoteHost\|^MATCH_EXP_MachineHEPSPEC\|^CpusProvisioned\|^MachineAttrCpus\|^RequestCpus\|^\s*$")
}

function localRotate(){
  echo "Rotating Log"
  cat $logFile >> $logFile.archive
  rm -f $logFile
}

function rotateLogs(){
  #get rid of two days old accouting files and move yesterdays files to .old
  echo "Rotating accounting records"
  rm -f $recordFileDirectory*.alog.old
  recFiles=($recordFileDirectory*.alog)
  for f in ${recFiles[@]}
  do
    mv $f $f.old 
  done
}

function checkAndSplit(){ #takes wkdir=/home/mfens98/apel or other arg given

  cp $1/*.alog $1/outgoing/

  logsToSplit=($1/outgoing/*.alog)
  for log in ${logsToSplit[@]}
  do
    fsize=$(stat --printf="%s" $log)
    if [ $(bc <<< "$fsize >= 500000") == "1" ]
    then
      numSplits=$(bc <<< "scale=0; $fsize/490000 +1")
      recordDelims=($(grep -n "%%" $log | cut -d: -f1))

      startLine=1
      for (( i=1; i<=$numSplits; i++ ))
      do
        if ! [[ $i -eq 1 ]]
        then
          echo "APEL-individual-job-message: v0.3" > "$log-$i"
        fi

        if [[ "$i" == "$numSplits" ]]
        then
          index=-1
        else
          index=$(bc <<< "scale=0; ${#recordDelims[@]} / $numSplits * $i")
        fi
        endLine=${recordDelims[$index]}
        afterEnd=$(bc <<< "scale=0; $endLine+1" )
        p="p"; q="q"
        sedString="$startLine,$endLine$p;$afterEnd$q"

        #echo $sedString
        sed -n "$sedString" $log >> "$log-$i"

        startLine=$afterEnd

      done
      rm -f $log
    fi
  done
}



function main(){
  echo "*********************** Starting on $(hostname -s) $(date) ******************"
  
  export DEBUG="false"
  
  flag="false" #flag for if we are finished with current date
  endOfRecords="false"
  salCount=0
  recordsWritten=0
  nullRecords=0
  recordFileDirectory=${1}
  logFile="accountingLog.log"
  dateSuffix=$(date +%s)

  #get all condor history files in /var/log/condor/history
  histMain=$(condor_config_val HISTORY)
  histFiles=($(ls -1t $histMain*)) # -1t lists in order of modification time newest first, * will also select rotated history files
  progression="-2"

  rotateLogs

  for f in ${histFiles[@]}
  do
    echo "Parsing file $f"
    parse_history "$f" "$recordFileDirectory"
    if "$endOfRecords"
    then
      break
    fi
  done
  if [ "$salCount" == "0" ]
  then
    echo -e "Accounting Summary $(hostname -s)\n\tRecords Written: $recordsWritten\n\tRecords Salvaged: $salCount \
    \n\t(Cutoff: $(date -d '3 days ago 00:00:00' -u ))\n\tRecords not started: $nullRecords"
  else
    echo -e "Accounting Summary $(hostname -s)\n\tRecords Written: $recordsWritten\n\tRecords Salvaged: $salCount \
    \n\t(Oldest near date: $(date -d @$oldestDate -u) Cutoff: $(date -d '3 days ago 00:00:00' -u ))\n\tRecords not started: $nullRecords"
  fi
  echo -e "************************ Finished on $(hostname -s) $(date) *********************\n"

  
}
remoteRecordFileDir="/var/log/apel/"
wkdir="/home/mfens98/apel"

if [[ $wkdir == *"_"* ]]
then
  fail "Cannot have '_' in file path currently, exiting"
  return 1
fi

logFile="$wkdir/logs/accountingLog.log"
localRotate > /tmp/newLog.log 2> >(tee -a /tmp/newLog.log >&2)
mv /tmp/newLog.log $logFile
for host in csv2a bellecs "root@belle-sd" dune-condor
do
  ssh -p3121 -q $host.heprc.uvic.ca "$(typeset -f); main $remoteRecordFileDir" >> $logFile 2> >(tee -a $logFile >&2)
  scp -P3121 -q $host.heprc.uvic.ca:$remoteRecordFileDir\*.alog $wkdir >> $logFile 2> >(tee -a $logFile >&2)
done

#combine records from belle and belle-validation
vicRecords=($wkdir/belle-uvic*.alog)
tail -n +2 ${vicRecords[1]} >> ${vicRecords[0]}
if [[ "$?" == "0" ]]
then
  rm -f ${vicRecords[1]}
else
 fail "Combining belle-uvic records from bellecs and belle-sd" >> $logFile 2> >(tee -a $logFile >&2)
fi

desyRecords=($wkdir/desy*.alog)
tail -n +2 ${desyRecords[1]} >> ${desyRecords[0]}
if [[ "$?" == "0" ]]
then
  rm -f ${desyRecords[1]}
else
  fail "Combining desy records from bellecs and belle-sd" >> $logFile 2> >(tee -a $logFile >&2)
fi
#make record files smaller than 1MB



echo "Preparing to send record files" >> $logFile 2> >(tee -a $logFile >&2)

checkAndSplit $wkdir
  
cp $wkdir/outgoing/*uvic* /home/mfens98/test_out/
/home/mfens98/apel_container/run_apel.sh >> $logFile 2> >(tee -a $logFile >&2)

echo "Sending messages via the ssmsend container" >> $logFile 2> >(tee -a $logFile >&2)
# run apel_container
#need to delete records after they've been sent??
sudo podman run --rm --entrypoint ssmsend \
       -v /home/mfens98/apel_container/config/sender-dummy.cfg:/etc/apel/sender.cfg \
       -v $wkdir/outgoing:/var/spool/apel/outgoing \
       -v /etc/grid-security:/etc/grid-security \
       -v $wkdir/logs:/var/log/apel \
       stfc/ssm:latest >> $logFile 2> >(tee -a $logFile >&2)

#delete sent messages
rm -f $wkdir/outgoing/*

#move messages to archive
echo "Archiving messages" >> $logFile 2> >(tee -a $logFile >&2)
fullLogs=($wkdir/*.alog)

dateTag=$(date -d "Yesterday 00:00:00" -u +%m%y)
for record in ${fullLogs[@]}
do 
  IFS="_" read -ra splitName <<< $record #change in case _ exists elsewhere in file path?
  IFS="/" read -ra splitPath <<< ${splitName[0]}

  tail -n +2 $record >> $wkdir/archive/${splitPath[-1]}$dateTag

  rm -f $record
  unset splitName splitPath

done >> $logFile 2> >(tee -a $logFile >&2)
