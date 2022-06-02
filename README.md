# bash_svmdr
A bash script to invoke svm dr activate (using rest)

# Examples
## Help
```
# bash svmdr.sh -h
OPTIONS :
-a : activate dr
-r : resync dr
-f : force flag
-h : help
-v : verbose output
```
## Status
```
# bash svmdr.sh

---------------------------------------------------------
cluster            : r2d2
svm                : svmin
fqdn/ip            : r2d2.slash.local
---------------------------------------------------------
reachable          : true
rest api available : true
svm state          : stopped
svm subtype        : dp_destination
snapmirror from    : svmup:
snapmirror state   : snapmirrored
snapmirror healthy : true
snapmirror lagtime : 26 minutes,  seconds

---------------------------------------------------------
cluster            : c3po
svm                : svmup
fqdn/ip            : c3po.slash.local
---------------------------------------------------------
reachable          : true
rest api available : true
svm state          : running
svm subtype        : default
snapmirror from    : N/A
snapmirror state   : N/A
snapmirror healthy : N/A
snapmirror lagtime : N/A
```
## Activate DR
```
# bash svmdr.sh -a

---------------------------------------------------------
cluster            : r2d2
svm                : svmin
fqdn/ip            : r2d2.slash.local
---------------------------------------------------------
reachable          : true
rest api available : true
svm state          : stopped
svm subtype        : dp_destination
snapmirror from    : svmup:
snapmirror state   : snapmirrored
snapmirror healthy : true
snapmirror lagtime : 27 minutes, 53 seconds
---------------------------------------------------------
Checking if this is a valid destination for dr activate
[OK] Source is coming from partner 'svmup'
[OK] Svm is type dp_destination
[OK] Svm is stopped
[OK] Snapmirror is healthy
[OK] Snapmirror is snapmirrored
---------------------------------------------------------
[OK] svmin can be activated
---------------------------------------------------------

---------------------------------------------------------
cluster            : c3po
svm                : svmup
fqdn/ip            : c3po.slash.local
---------------------------------------------------------
reachable          : true
rest api available : true
svm state          : running
svm subtype        : default
snapmirror from    : N/A
snapmirror state   : N/A
snapmirror healthy : N/A
snapmirror lagtime : N/A
---------------------------------------------------------
Checking if this is a valid destination for dr activate
[NOK] Source is wrong -> 'N/A' ; expecting 'svmin:'
---------------------------------------------------------
[NOK] svmup can not be activated
REASON : Source is wrong -> 'N/A' ; expecting 'svmin:'
---------------------------------------------------------

---------------------------------------------------------
INVOKING DR ACTIVATE
Invoking dr from 'c3po':'svmup' -> 'r2d2':'svmin'
---------------------------------------------------------
Stopping source svm 'svmup'
Waiting for job to finish
Waiting for svm state to be 'stopped'
... running
... running
... running
... stopped
Invoking snapmirror update
... transferring
... transferring
... transferring
... transferring
... transferring
... transferring
... transferring
... transferring
LAG = 0 seconds
Breaking snapmirror
Waiting for job to finish
Waiting for snapmirror state to be 'broken_off'
... snapmirrored
... snapmirrored
... snapmirrored
... broken_off
Starting dr svm 'svmin'
Waiting for job to finish
Waiting for svm state to be 'running'
... stopped
... stopped
... stopped
... stopped
... running
---------------------------------------------------------
Activate DR finished
---------------------------------------------------------
```
## Resync dr
```
# bash svmdr.sh -rf

---------------------------------------------------------
cluster            : r2d2
svm                : svmin
fqdn/ip            : r2d2.slash.local
---------------------------------------------------------
reachable          : true
rest api available : true
svm state          : running
svm subtype        : default
snapmirror from    : svmup:
snapmirror state   : broken_off
snapmirror healthy : true
snapmirror lagtime :
---------------------------------------------------------
Checking if this is a valid destination for dr resync
[OK] Source is coming from partner 'svmup'
[OK] Svm is type default
[OK] Snapmirror is healthy
[OK] Snapmirror is broken_off
---------------------------------------------------------
[OK] svmin can be resynced
---------------------------------------------------------

---------------------------------------------------------
cluster            : c3po
svm                : svmup
fqdn/ip            : c3po.slash.local
---------------------------------------------------------
reachable          : true
rest api available : true
svm state          : stopped
svm subtype        : default
snapmirror from    : N/A
snapmirror state   : N/A
snapmirror healthy : N/A
snapmirror lagtime : N/A
---------------------------------------------------------
Checking if this is a valid destination for dr resync
[NOK] Source is wrong -> 'N/A' ; expecting 'svmin:'
---------------------------------------------------------
[NOK] svmup can not be resynced
REASON : Source is wrong -> 'N/A' ; expecting 'svmin:'
---------------------------------------------------------

---------------------------------------------------------
INVOKING DR RESYNC
Force is enabled!
Invoking resync from 'c3po':'svmup' -> 'r2d2':'svmin'
---------------------------------------------------------
Stopping dr svm 'svmin'
Waiting for job to finish
Waiting for svm state to be 'stopped'
... running
... running
... running
... stopped
Resync snapmirror
Waiting for job to finish
... running
Waiting for snapmirror state to be 'snapmirrored'
... broken_off
... broken_off
... broken_off
... broken_off
... broken_off
... broken_off
... broken_off
... broken_off
... broken_off
... snapmirrored
Starting source svm 'svmup'
Waiting for job to finish
Waiting for svm state to be 'running'
... stopped
... stopped
... stopped
... stopped
... stopped
... stopped
... stopped
... stopped
... stopped
... running
---------------------------------------------------------
Resync DR finished
---------------------------------------------------------
```

# svmdr_bash
# svmdr_bash
