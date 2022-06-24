#!/bin/bash
###########################################
# VERSION 1.0.2
# AUTHOR Mirko Van Colen - mirko@netapp.com
# UPDATES
# 1.0.0 : initial version
# 1.0.1 : Added abort functionality
# 1.0.2 : anticipate svm start burt
###########################################

# variables
username="admin"
password="*****" # base64
protocol="https://"

cluster1="cluster1"
svm1="svm1"
host1="10.0.0.1"

cluster2="cluster2"
svm2="svm2"
host2="10.0.0.2"

transferTimeoutSeconds=20

###########################################
# CODE BELOW ; DON'T CHANGE BELOW

# argument flags
force=false
verbose=false
activate=false
resync=false
help=false

# status holders
declare -A state
declare -A host
declare -A cluster
declare -A svm
declare -A svm_uri
declare -A subtype
declare -A sm_state
declare -A sm_source
declare -A sm_healthy
declare -A sm_lagtime
declare -A sm_uri
declare -A ok
declare -A message
declare -A reachable
declare -A rest_available

# Assign hash data
svm['cluster1']="$svm1"
cluster['cluster1']="$cluster1"
host['cluster1']="$host1"

svm['cluster2']="$svm2"
cluster['cluster2']="$cluster2"
host['cluster2']="$host2"

drdestination=""
drsource=""

# decode password
pwdecoded=$(echo "$password" | base64 --decode)
creds="$username:$pwdecoded"

# LOGGING FUNCTIONS
log_info(){
  printf -- "$1\n" >&2
}
log_verbose(){
  if $verbose; then
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
    log_info "${CYAN}$1${NC}"
  fi
}
log_error(){
  RED='\033[0;31m'
  NC='\033[0m' # No Color
  log_info "${RED}$1${NC}"
}
log_success(){
  GREEN='\033[0;32m'
  NC='\033[0m' # No Color
  log_info "${GREEN}$1${NC}"
}
log_title(){
  MAGENTA='\033[0;35m'
  NC='\033[0m' # No Color
  log_info "${MAGENTA}$1${NC}"
}

# HELPER FUNCTIONS
init(){
  # initializes a hash entry
  ok[$1]=false
  svm_uri[$1]=""
  svm_state[$1]=""
  svm_subtype[$1]=""
  sm_state[$1]=""
  sm_source[$1]=""
  sm_healthy[$1]=""
  sm_lagtime[$1]=""
  sm_uri[$1]=""
  reachable[$1]=false
  rest_available[$1]=false
}
get_friendly_lagmessage(){
  # transforms lag string to friendly lag message
  local result=""
  if [[ $1 =~ PT(([0-9]*)*H)?(([0-9]*)*M)?(([0-9]*)*S)? ]]; then
    hours="${BASH_REMATCH[2]}"
    minutes="${BASH_REMATCH[4]}"
    seconds="${BASH_REMATCH[6]}"
    if [ $hours ]; then result+="$hours hours, "; fi
    if [ $minutes ]; then result+="$minutes minutes, "; fi
    result+="$seconds seconds"
    echo "$result"
  else
    echo "$1"
  fi
}
get_lag_seconds(){
  # calculates lag to seconds
  if [[ $1 =~ PT(([0-9]*)*H)?(([0-9]*)*M)?(([0-9]*)*S)? ]]; then
    hours="${BASH_REMATCH[2]}"
    minutes="${BASH_REMATCH[4]}"
    seconds="${BASH_REMATCH[6]}"
    echo "$((${hours:="0"}*3600 + ${minutes:="0"}*60 + ${seconds:="0"}))"
  else
    echo 0
  fi
}
get_partner(){
  if [ "$1" == "cluster1" ]; then
    echo "cluster2"
  else
    echo "cluster1"
  fi
}
set_message(){
  # flags a status error ; action won't work on this entity
  ok[$1]=false
  message[$1]+="$2\n"
  log_error "[NOK] $2"
}
check_reachable(){
  # is entity reachable ?
  log_verbose "[ check_reachable ] ping -c1 -W1 -q ${host[$1]}"
  ping -c1 -W1 -q ${host[$1]} 2>&1 >/dev/null && reachable[$1]=true || reachable[$1]=false
  log_verbose "[ check_reachable ] --> ${reachable[$1]}"
}
rest(){
  # invoke a get rest
  # allow a json query using jq : yum install jq !
  local uri="$protocol$1$2"
  local json="$3"
  local result=""
  if [ -z "$json" ]; then
    log_verbose "[ rest ] curl -k -s -u '$creds' '$uri'"
    result=$(curl -k -s -u $creds $uri )
  else
    log_verbose "[ rest ] curl -k -s -u '$creds' '$uri' | jq -r '$json'"
    result=$(curl -k -s -u $creds $uri | jq -r "$json")
  fi
  log_verbose "[ rest ] --> $result"
  if [ "$result" == "null" ]; then
    result=""
  fi
  echo $result
}
rest_post(){
  # invokes a rest post/patch
  local uri="$protocol$1$2"
  local method="$3"
  local body="$4"
  log_verbose "[ rest_post ] curl -k -s -X $method -s -u '$creds' '$uri' --data '$body'"
  local result=$(curl -k -X $method -s -u $creds $uri --data "$body")
  log_verbose "[ rest_post ] --> $result"
  if [ "$result" == "null" ]; then
    result=""
  fi
  echo "$result"
}
jsonquery(){
  # allows a jq json query on a json string
  local result=$(jq -r "$2" <<< "$1")
  log_verbose "[ jsonquery ][ $2 ] --> $result"
  if [ "$result" == "null" ]; then
    result=""
  fi
  echo $result
}

# STATUS FUNCTIONS
print_usage() {
  echo "OPTIONS :"
  echo "-a : activate dr"
  echo "-r : resync dr"
  echo "-f : force flag"
  echo "-h : help"
  echo "-v : verbose output"
  exit 0
}
print_svm(){
  # output an analysis of the situation of an entity
  init "$1"
  log_title ""
  log_title "---------------------------------------------------------"
  log_title "cluster            : ${cluster[$1]}"
  log_title "svm                : ${svm[$1]}"
  log_title "fqdn/ip            : ${host[$1]}"
  check_svm "$1"
  log_info "---------------------------------------------------------"
  log_info "reachable          : ${reachable[$1]}"
  log_info "rest api available : ${rest_available[$1]}"
  if ${rest_available[$1]}; then
    log_info "svm state          : ${svm_state[$1]}"
    log_info "svm subtype        : ${svm_subtype[$1]}"
    log_info "snapmirror from    : ${sm_source[$1]}"
    log_info "snapmirror state   : ${sm_state[$1]}"
    log_info "snapmirror healthy : ${sm_healthy[$1]}"
    log_info "snapmirror lagtime : $(get_friendly_lagmessage ${sm_lagtime[$1]})"
    if $activate; then
      check_dr "$1"
    fi
    if $resync; then
      check_resync "$1"
    fi
    # if ! $activate && ! $resync; then # status only
    #   # check both
    #   check_dr "$1"
    #   check_resync "$1"
    # fi
  else
    log_title "---------------------------------------------------------"
  fi
}

# CHECKING HELPER FUNCTIONS
check_dr(){
  # checks if a dr activate is possible on this entity
  this="$1"
  partner=$(get_partner "$this")
  ok[$this]=true
  local analysis=""
  log_info "---------------------------------------------------------"
  log_info "Checking if this is a valid destination for dr activate"
  if [ "${sm_source[$this]}" == "${svm[$partner]}:" ]; then
    log_success "[OK] Source is coming from partner '${svm[$partner]}'"
    if [ "${svm_subtype[$this]}" == "dp_destination" ]; then
      log_success "[OK] Svm is type dp_destination"
    else
      set_message "$this" "Svm is of type '${svm_subtype[$this]}' ; expecting 'dp_destination'"
      analysis="Svm seems to be a production svm, as it's not a 'dp destination'"
    fi
    if [ "${svm_state[$this]}" == "stopped" ]; then
      log_success "[OK] Svm is stopped"
    else
      set_message "$this" "Svm is not stopped"
      analysis="Svm seems to be production svm, as it's running"
    fi
     if [ "${sm_healthy[$this]}" ]; then
      log_success "[OK] Snapmirror is healthy"
    else
      set_message "$this" "Snapmirror is unhealthy"
      analysis="The snapmirror relationship is unhealthy"
    fi
    if [ "${sm_state[$this]}" == "snapmirrored" ]; then
      log_success "[OK] Snapmirror is snapmirrored"
    elif [ "${sm_state[$this]}" == "paused" ]; then
      log_success "[OK] Snapmirror is paused"
    else
      set_message "$this" "Snapmirror is ${sm_state[$this]}"
      if [ "${sm_state[$this]}" == "broken_off" ];then
        analysis="Snapmirror is already broken_off"
      else
        analysis="Snapmirror is ${sm_state[$this]}"
      fi
    fi
  else
    analysis="Source is wrong -> '${sm_source[$this]}' ; expecting '${svm[$partner]}:'"
    set_message "$this" "$analysis"
  fi
  if ${ok[$this]}; then
    log_info "---------------------------------------------------------"
    log_info "[OK] ${svm[$1]} can be activated"
    log_title "---------------------------------------------------------"
    drdestination="$this"
    drsource="$partner"
    log_verbose "Marking $drdestination as destination and $partner as source"
  else
    log_info "---------------------------------------------------------"
    log_info "[NOK] ${svm[$1]} can not be activated"
    log_info "REASON : $analysis"
    log_title "---------------------------------------------------------"
  fi
}
check_resync(){
  # checks if a dr resync is possible on this entity
  this="$1"
  partner=$(get_partner "$this")
  ok[$this]=true
  local analysis=""
  log_info "---------------------------------------------------------"
  log_info "Checking if this is a valid destination for dr resync"
  if [ "${sm_source[$this]}" == "${svm[$partner]}:" ]; then
    log_success "[OK] Source is coming from partner '${svm[$partner]}'"
    if [ "${svm_subtype[$this]}" == "default" ]; then
      log_success "[OK] Svm is type default"
    else
      set_message "$this" "Svm is of type '${svm_subtype[$this]}' ; expecting 'default'"
      analysis="Svm seems to be already a dr destination svm, no resync required"
    fi
    if [ "${sm_healthy[$this]}" ]; then
      log_success "[OK] Snapmirror is healthy"
    else
      set_message "$this" "Snapmirror is unhealthy"
      analysis="The snapmirror relationship is unhealthy"
    fi
    if [ "${sm_state[$this]}" == "broken_off" ]; then
      log_success "[OK] Snapmirror is broken_off"
    else
      set_message "$this" "Snapmirror is ${sm_state[$this]}"
      if [ "${sm_state[$this]}" == "snapmirrored" ];then
        analysis="Snapmirror is already snapmirrored"
      else
        analysis="Snapmirror is ${sm_state[$this]}"
      fi
    fi
  else
    analysis="Source is wrong -> '${sm_source[$this]}' ; expecting '${svm[$partner]}:'"
    set_message "$this" "$analysis"
  fi
  if ${ok[$this]}; then
    log_info "---------------------------------------------------------"
    log_info "[OK] ${svm[$1]} can be resynced"
    log_title "---------------------------------------------------------"
    drdestination="$this"
    drsource="$partner"
    log_verbose "Marking $drdestination as destination and $partner as source"
  else
    log_info "---------------------------------------------------------"
    log_info "[NOK] ${svm[$1]} can not be resynced"
    log_info "REASON : $analysis"
    log_title "---------------------------------------------------------"
  fi
}
check_svm(){
  local host="${host[$1]}"
  local svm="${svm[$1]}"
  check_reachable "$1"
  if ${reachable[$1]}; then
    local svmuri=$(rest $host "/api/svm/svms?name=$svm" ".records[0]._links.self.href")
    # check if rest is possible
    if [ -z "$svmuri" ]; then
      rest_available[$1]=false
    else
      rest_available[$1]=true
      # store entity information about svm
      svm_uri[$1]="$svmuri"
      local svmobj=$(rest $host "$svmuri")
      svm_state[$1]=$(jsonquery "$svmobj" ".state")
      svm_subtype[$1]=$(jsonquery "$svmobj" ".subtype")
      # get snapmirror status
      local smuri=$(rest $host "/api/snapmirror/relationships?destination.path=$svm:" ".records[0]._links.self.href")
      if [ -z "$smuri" ]; then
        log_verbose "No snapmirror relations found"
        sm_state[$1]="N/A"
        sm_lagtime[$1]="N/A"
        sm_healthy[$1]="N/A"
        sm_source[$1]="N/A"
      else
        local smobj=$(rest $host "$smuri?fields=*")
        # store entity information about snapmirror
        sm_uri[$1]="$smuri"
        sm_state[$1]=$(jsonquery "$smobj" ".state")
        sm_lagtime[$1]=$(jsonquery "$smobj" ".lag_time")
        sm_healthy[$1]=$(jsonquery "$smobj" ".healthy")
        sm_source[$1]=$(jsonquery "$smobj" ".source.path")
      fi
    fi
  else
    log_error "$host is unreachable"
  fi
}

# MAIN FUNCTIONS
print_status(){
  # analyse both entities
  print_svm "cluster1"
  print_svm "cluster2"
}
invoke_sm_update(){
  # invokes a snapmirror update on the dr target
  log_info "Invoking snapmirror update"
  local dummyout=$(rest_post "${host[$drdestination]}" "${sm_uri[$drdestination]}transfers/" "POST" "{}")
  log_verbose "Waiting for transfer to finish"
  local transfer=$(rest "${host[$drdestination]}" "${sm_uri[$drdestination]}transfers/?fields=state" ".records[0].state")
  local watchdog=0
  while [ ! -z "$transfer" -a "$watchdog" -lt "$transferTimeoutSeconds" ]
  do
    log_info "... $transfer"
    sleep 1s
    ((watchdog=watchdog+1))
    transfer=$(rest "${host[$drdestination]}" "${sm_uri[$drdestination]}transfers/?fields=state" ".records[0].state")
  done
  if [ "$watchdog" -ge "$transferTimeoutSeconds" ]; then
    log_error "Transfer is taking too long. Aborting."
  else
    # final check to see lag
    local smlagtime=$(rest "${host[$drdestination]}" "${sm_uri[$drdestination]}?fields=lag_time" ".records[0].lag_time")
    log_success "LAG = $(get_lag_seconds "$smlagtime") seconds"
  fi
}
invoke_sm_abort(){
  log_info "Invoking snapmirror abort if needed"
  log_verbose "Getting transfer to abort"
  local transfer=$(rest "${host[$drdestination]}" "${sm_uri[$drdestination]}transfers/?state=transferring" ".records[0].uuid")
  if [[ ! -z $transfer ]]; then
    log_verbose "found transfer with uuid $transfer"
    # invokes a snapmirror abort on the dr target
    log_info "Invoking snapmirror abort"
    local dummyout=$(rest_post "${host[$drdestination]}" "${sm_uri[$drdestination]}transfers/$transfer/" "PATCH" "{\"state\":\"aborted\"}")
    log_verbose "Waiting for abort to finish"
    local transfer=$(rest "${host[$drdestination]}" "${sm_uri[$drdestination]}transfers/?fields=state" ".records[0].state")
    while [[ ! -z $transfer ]]
    do
      log_info "... $transfer"
      sleep 1s
      transfer=$(rest "${host[$drdestination]}" "${sm_uri[$drdestination]}transfers/?fields=state" ".records[0].state")
    done
  else
    log_verbose "Nothing to abort"
  fi

}
wait_job(){
  # wait for a rest job
  local uri="$1"
  if [ "$uri" != "" ]; then
    log_info "Waiting for job to finish"
    local jobstate=$(rest "${host[$drdestination]}" "$uri" ".state")
    local jobmessage=$(rest "${host[$drdestination]}" "$uri" ".message")
    log_info "... $jobstate : $jobmessage"
    while [ "$jobstate" != "success" ] && [ "$jobstate" != "error" ] && [ "$jobstate" != "failure" ]
    do
      log_info "... $jobstate : $jobmessage"
      sleep 1s
      jobstate=$(rest "${host[$drdestination]}" "$uri" ".state")
      jobmessage=$(rest "${host[$drdestination]}" "$uri" ".message")
    done
    if [[ "$jobmessage" == *"You cannot start the SVM when command confirmations are disabled"* ]]; then
      log_error "... hitting burt 1322362... ignoring failure"
    fi
    if [[ "$jobmessage" == *"management configuration for this Vserver is locked"* ]]; then
      log_error "... due to powerfailure the svm configuration is locked, manual intervention required"
      log_error "... this happens in very rare occasions"
      log_error "... manually unlock and start the svm, ssh to source cluster $cluster1 and type 'vserver unlock -vserver $svm1 -force true;vserver start -vserver $svm1'"
    fi
  else
    log_error "[ wait_job ] expected joburi ; but got nothing [$uri]"
  fi
}
set_state(){
  local host="$1"
  local uri="$2"
  local state="$3"
  local message="$4"
  local type="$5" # "svm" or "snapmirror"
  log_info "$message"
  local out=$(rest_post "$host" "$uri" "PATCH" "{\"state\":\"$state\"}")
  local joburi=$(jsonquery "$out" ".job._links.self.href")
  wait_job "$joburi"
  log_info "Waiting for $type state to be '$state'"
  local currentstate=$(rest "$host" "$uri?fields=state" ".state")
  while [ "$currentstate" != "$state" ]
  do
    log_info "... $currentstate"
    sleep 1s
    currentstate=$(rest "$host" "$uri?fields=state" ".state")
  done
  log_success "... $currentstate"
}
force_failover(){
  local host="$1"
  local uri="$2"
  local state="$3"
  local message="$4"
  local type="$5" # "svm" or "snapmirror"
  log_info "$message"
  local out=$(rest_post "$host" "$uri" "PATCH" "{\"failover\":\"true\",\"force-failover\":\"true\"}")
  local joburi=$(jsonquery "$out" ".job._links.self.href")
  wait_job "$joburi"
  log_info "Waiting for $type state to be '$state'"
  local currentstate=$(rest "$host" "$uri?fields=state" ".state")
  while [ "$currentstate" != "$state" ]
  do
    log_info "... $currentstate"
    sleep 1s
    currentstate=$(rest "$host" "$uri?fields=state" ".state")
  done
  log_success "... $currentstate"
  set_state "${host[$drdestination]}" "${svm_uri[$drdestination]}" "running" "Starting dr svm '${svm[$drdestination]}'" "svm"
}
invoke_resync(){
  # invokes a resync action
  print_status
  log_title ""
  log_title "---------------------------------------------------------"
  log_title "INVOKING DR RESYNC"
  if $force; then
    log_title "Force is enabled!"
  fi
  if [ -z $drdestination ]; then
    log_error "No valid resync candidate was found"
    log_title "---------------------------------------------------------"
    exit -100
  fi
  if $force; then
    log_title "Invoking resync from '${cluster[$drsource]}':'${svm[$drsource]}' -> '${cluster[$drdestination]}':'${svm[$drdestination]}'"
    log_info "---------------------------------------------------------"
    set_state "${host[$drdestination]}" "${svm_uri[$drdestination]}" "stopped" "Stopping dr svm '${svm[$drdestination]}'" "svm"
    set_state "${host[$drdestination]}" "${sm_uri[$drdestination]}" "snapmirrored" "Resync snapmirror" "snapmirror"
    if ${rest_available[$drsource]}; then
      set_state "${host[$drsource]}" "${svm_uri[$drsource]}" "running" "Starting source svm '${svm[$drsource]}'" "svm"
    fi
  else
    log_info "---------------------------------------------------------"
    log_error "Resync is a dangerous action, know what you are doing"
    log_error "If you still want to resync DR,"
    log_error "invoke this script with the -f force flag"
  fi
  log_title "---------------------------------------------------------"
  log_title "Resync DR finished"
  log_title "---------------------------------------------------------"
  exit 2
}
invoke_dr(){
  # invokes a dr activate
  print_status
  log_title ""
  log_title "---------------------------------------------------------"
  log_title "INVOKING DR ACTIVATE"
  if $force; then
    log_title "Force is enabled!"
  fi
  if [ -z $drdestination ]; then
    log_error "No valid dr candidate was found"
    log_title "---------------------------------------------------------"
    exit -100
  fi
  # if source is unavailable or if force flag is set
  if [ !${reachable[$drsource]} ] || $force; then
    log_title "Invoking dr from '${cluster[$drsource]}':'${svm[$drsource]}' -> '${cluster[$drdestination]}':'${svm[$drdestination]}'"
    log_info "---------------------------------------------------------"
    # only if source is available we attempt to stop the source and fire a final update
    if ${rest_available[$drsource]}; then
  	  log_info "Performing negotiated failover"
      set_state "${host[$drsource]}" "${svm_uri[$drsource]}" "stopped" "Stopping source svm '${svm[$drsource]}'" "svm"
      invoke_sm_update
      invoke_sm_abort
  	  set_state "${host[$drdestination]}" "${sm_uri[$drdestination]}" "paused" "Pausing snapmirror" "snapmirror"
  	  set_state "${host[$drdestination]}" "${sm_uri[$drdestination]}" "broken_off" "Breaking snapmirror" "snapmirror"
  	  set_state "${host[$drdestination]}" "${svm_uri[$drdestination]}" "running" "Starting dr svm '${svm[$drdestination]}'" "svm"
    else
      log_info "Performing forced failover"
      invoke_sm_abort
      force_failover "${host[$drdestination]}" "${sm_uri[$drdestination]}" "broken_off" "Breaking snapmirror" "snapmirror"
    fi

  else
    log_info "---------------------------------------------------------"
    log_error "The source cluster '${cluster[$drsource]}' is still reachable"
    log_error "If you still want to activate DR, make sure all hosts are stopped"
    log_error "and invoke this script with the -f force flag"
  fi
  log_title "---------------------------------------------------------"
  log_title "Activate DR finished"
  log_title "---------------------------------------------------------"
  exit 2
}

# MAIN
# PROCESS ARGUMENTS
while getopts ':afvrh' flag; do
  case "${flag}" in
    f) force=true ;;
    v) verbose=true ;;
    a) activate=true ;;
    r) resync=true ;;
    h) help=true ;;
  esac
  shift `expr $OPTIND - 1`
done

# SHOW HELP
if $help; then
  print_usage
fi

# INVOKE RESYNC
if $resync; then
  invoke_resync
fi

# INVOKE DR
if $activate; then
  invoke_dr
fi

# DEFAULT FALL BACK - SHOW STATUS
print_status
exit 1
