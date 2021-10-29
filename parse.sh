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
  echo "Status: ${content[JobStatus]}"
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

function parse_history(){
declare -A content
while read -r line
do
  IFS=" " read -ra linearr <<< "$line" 
  #echo "$line"
  case "$line" in

    *GlobalJobId*) #LocalJobId
      #echo "JobId"
      fullID=${linearr[2]}
      IFS="#" read -ra IdArr <<< "$fullID" || fail "Couldn't get JobID"
      content[LocalJobId]=${IdArr[1]}
    ;;

    *Owner*) #UserId
      #echo "userID"
      content[LocalUserId]=${linearr[2]}
    ;;

    *JobStatus*)
      #echo "Jobstatus"
      code=${linearr[2]}

      case "$code" in

      1)
        content[JobStatus]='queued'
      ;;

      2|6)
        content[JobStatus]='started'
      ;;

      3)
        content[JobStatus]='aborted'
      ;;

      4)
        content[JobStatus]='completed'
      ;;

      5)
        content[JobStatus]='held'
      ;;

      7)
        content[JobStatus]='suspended'
      ;;

      *)
        content[JobStatus]='unknown'
      ;;

      esac
    ;;

    *RemoteWallClockTime*) #Wall Duration
      #echo "wall time"
      wallSeconds=${linearr[2]}
      get_ISO_diff ${linearr[2]} || fail "Converting wall time seconds to iso duration"
      content[WallDuration]=$ISOdiff
    ;;

    *CumulativeRemoteUserCpu*) #divide by number of cores at end
      #echo "cpu time"
      cpuSeconds=${linearr[2]}
      #content[CpuSeconds]=$cpuSeconds
    ;;

    *JobStartDate*)
      #echo "start time"
      startEpoch=${linearr[2]}
      content[StartTime]=$(date -d @"${linearr[2]}" -u +%Y-%m-%dT%H:%M:%SZ) || fail "Converting start time (in epoch) to ISO date"
    ;;

    *EnteredCurrentStatus*)
      #echo "Alt end time"
      statusTime=${linearr[2]}
      #content[EndTime]=$(date -d @"${linearr[2]}" -u +%Y-%m-%dT%H:%M:%SZ)
    ;;

    *LastRemoteHost*) #machine name, submit host, VO
      #echo "machine ename host vo..."

      machineAndSlot=${linearr[2]}
      IFS="@" read -ra namearr <<< "$machineAndSlot" || fail "Reading host into array"
      fullName=${namearr[1]}
      content[MachineName]=$fullName

      delim="--"
      s=$fullName$delim
      vmDetails=()
      while [[ $s ]]
      do
        vmDetails+=( "${s%%"$delim"*}" )
        s=${s#*"$delim"}
      done
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

    ;;

    *MATCH_EXP_MachineHEPSPEC*)
      #echo "hepspec"
      content[ServiceLevelType]="HEPSPEC"
      content[ServiceLevel]=${linearr[2]}
    ;;

    *CpusProvisioned*|*MachineAttrCpus*) #same thing but different names
      #echo "Processors"
      content[Processors]=${linearr[2]}
    ;;

    *RequestCpu*)
      cpuRequest=${linearr[2]}  
    ;;

    "") #When we get a newline we can write a record and clear our dictionary
        #also get site/queue names since using requirements string and vm name

      #echo "Checking time and status for ID: ${content[LocalJobId]}"
      
      if [[ "$startEpoch" == "" || $(bc <<< "$statusTime-$startEpoch == 0") -eq 1 ]]
      then
        #echo "Got aborted job with 0 wall time or no start time, not writing. Clearing vars."
        let nullRecords=$nullRecords+1
        unset content code fullName delim s groupName cloudName startEpoch endEpoch statusTime recordFileName recordFileDir recordFilePath cpuPerCore wallSeconds
        declare -A content 
        continue
      fi

      if [ $statusTime -gt $(date -d "Yesterday 23:59:59" -u +%s) ] #start time between yesterday 00:00:00 and yesterday 23:59:59
      then  #newer than yesterday
        if [ $progression != "-1" ]
        then
          echo "Got records that are too new..."
          progression="-1"
        fi
        unset content code fullName delim s groupName cloudName startEpoch endEpoch statusTime recordFileName recordFileDir recordFilePath cpuPerCore wallSeconds
        declare -A content 
        continue #get to the next record since reverse chronological order
      elif [ $statusTime -lt $(date -d "Yesterday 00:00:00" -u +%s) ]
      then
        if [ $progression != 1 ]
        then
          echo "Got a record that is too old, continuing just in case..."
          progression=1
        fi
        unset content code fullName delim s groupName cloudName startEpoch endEpoch recordFileName recordFileDir recordFilePath cpuPerCore wallSeconds
        declare -A content
        if [ $statusTime -lt $(date -d "3 days ago 00:00:00" -u +%s) ]
        then
          unset statusTime
          endOfRecords="true"
          echo "End of leeway, exiting"
          break
        else
          #echo ">>>>>>> Reached end of yesterday's records >>>>"
          flag="true"
          unset statusTime
          continue #all other records should be older than this but give some leeway since record not exatly in order
        fi
      fi

      if [ $progression != "0" ]
      then
        echo "Writing records from yesterday!"
        progression=0
      fi

      #echo "Doing final stuff"
      if "$flag"
      then
        let salCount=$salCount+1
        echo ">>>>>>>Salvaged a record from yesterday that was amongst records that are too old>>>>>>>>"

      fi
      #calculate end time
      #echo "End time calculation"
      if [ $(bc <<< "$wallSeconds >= 0") -eq 1 ] #bc true is 1 
      then
          endEpoch=$(bc <<< "scale=0; $startEpoch+$wallSeconds") || fail "Calculating end time (since epoch)"
          content[EndTime]=$(date -d @"$endEpoch" -u +%Y-%m-%dT%H:%M:%SZ) || fail "Converting end time to ISO date (if condition), tried to convert: $endEpoch"
      else #got negative wall time so use entered current status time as end time and get other values from there
        let wallSeconds=$statusTime-$startEpoch
        content[EndTime]=$(date -d @"$statusTime" -u +%Y-%m-%dT%H:%M:%SZ) || fail "Converting end time to ISO date (else condition), tried to convert: $statusTime"
        get_ISO_diff $wallSeconds || fail "Converting walltime to iso time duration"
        content[WallDuration]=$ISOdiff
      fi    

      #if [ $(bc <<< "$wallSeconds == 0") -eq 1 ] #if job has 0 wall time do not record it, it was probably aborted before running
      #then
      #  echo "Got aborted job with 0 wall time, not writing. Clearing vars."
      #  unset content code fullName delim s groupName cloudName startEpoch endEpoch statusTime recordFileName recordFileDir recordFilePath cpuPerCore wallSeconds
      #  declare -A content 
      #  continue
      #fi

      case $groupName in #set SITE
        atlas-cern)
          #use cloud name to set site
          case $cloudName in
            *cern*)
              #cern site
              content[Site]="CERN-PROD" #is this correct?
              recordFileName="cern-record.log"
            ;;
            *hephy*)
              #hephy site
              content[Site]="HEPHY-UIBK"
              recordFileName="hephy-record.log"
            ;;
            *lrz*) #may have _cloud
              #lrz site
              content[Site]="LRZ-LMU"
              recordFileName="lrz-record.log"
            ;;
            *ecdf*)
              #ecdf site
              content[Site]="UKI-SCOTGRID-ECDF" #add cloud or other vo?
              recordFileName="ecdf-record.log"
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
          recordFileName="ecdf-record.log"
        ;;
        atlas-uvic|belle)
          #set to uvic site
          content[Site]="CA-UVic-Cloud" #is anything different for atlas/belle? or is this specified elsewhere (ie VO, submit host)
          recordFileName="uvic-record.log"
        ;;
        australia-belle)
          #set to melbourne site
          content[Site]="Australia-T2"
          recordFileName="melbourne-record.log"
        ;;
        babar)
          #skip record process
          content[Site]="babar"
          recordFileName=""
        ;;
        belle-validation|desy-belle)
          #desy site
          content[Site]="DESY-HH" #also a desy-zn site
          recordFileName="desy-record.log"
        ;;
        dune)
          #dune site (Marcus looking into)
          content[Site]="CA-DUNE"
          recordFileName="dune-record.log"
        ;;
        "")
          site_error "Group not listed: $groupName (JobStatus: ${content[JobStatus]})"
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

      get_ISO_diff $cpuPerCore || fail "Setting cpu/core to iso time duration"
      content[CpuDuration]=$ISOdiff

      #if remotewallclocktime negative use epoch times      
      #let wallTime=$endEpoch-$startEpoch
      #get_ISO_diff $wallTime
      #content[WallDuration]=$ISOdiff
      #echo "Hepspec setting if not set already"
      if [ "${content[ServiceLevel]}" == "" ]
      then
        content[ServiceLevelType]="HEPSPEC"
        content[ServiceLevel]="0.00"
        #fail "HEPSPEC not specified! Setting to 0.00"
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
            recordFileDir="/tmp/"
            recordFilePath=$recordFileDir$recordFileName
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
          >&2 echo "ERROR: Unknown group: $groupName. (not atlas, belle or dune), not writing record (JobStatus: ${content[JobStatus]})"
      esac
      unset content code fullName delim s groupName cloudName startEpoch endEpoch statusTime recordFileName recordFileDir recordFilePath cpuPerCore wallSeconds
      declare -A content
      #echo "Starting next entry"
    ;;

  esac

done < <(condor_history -long -file ${1} | grep "^GlobalJobId\|^Owner\|^JobStatus\|^RemoteWallClockTime\|^CumulativeRemoteUserCpu\|^JobStartDate\|^EnteredCurrentStatus\|^LastRemoteHost\|^MATCH_EXP_MachineHEPSPEC\|^CpusProvisioned\|^MachineAttrCpus\|^RequestCpus\|^\s*$")
#done < <(cat ~/history.test | grep "^GlobalJobId\|^Owner\|^JobStatus\|^RemoteWallClockTime\|^CumulativeRemoteUserCpu\|^JobStartDate\|^EnteredCurrentStatus\|^LastRemoteHost\|^MATCH_EXP_MachineHEPSPEC\|^CpusProvisioned\|^MachineAttrCpus\|^RequestCpus\|^\s*$")
}

echo "*********************** Starting History Parsing Script v1.0 ******************"
echo "*********************** $(date) **************************"
flag="false" #flag for if we are finished with current date
endOfRecords="false"
salCount=0
recordsWritten=0
nullRecords=0

#get all condor history files in /var/lib/condor/spool
histMain=$(condor_config_val HISTORY)
histFiles=($(ls -1t $histMain*)) # -1t lists in order of modification time newest first, * will also select rotated history files
progression="-2"

for f in ${histFiles[@]}
do
  echo "@@@@@@@@@@@@@@@@@@@@@@@ Parsing file $f @@@@@@@@@@@@@@@@@@"
  parse_history "$f"
  if "$endOfRecords"
  then
    break
  fi
done


echo -e "\n************************ Finished History Parsing Script *********************"
echo "************************ $(date) ************************"

echo -e "\n######### Accounting Summary ##########\n\tRecords Written: $recordsWritten\n\tRecords Salvaged: $salCount\n\tRecords not started: $nullRecords\n######################################"
