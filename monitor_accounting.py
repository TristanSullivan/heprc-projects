#!/usr/bin/env python

import urllib2
import json
import datetime as dt

import subprocess
import sys


#run bash script to get 
scriptcommand="/home/mfens98/check_accounting.sh -j"
process=subprocess.Popen(scriptcommand.split(),stdout=subprocess.PIPE)
output,error=process.communicate()

shOut=json.loads(str(output))

today=dt.date.today()

mo=str(today.month)
yr=str(today.year)


url="https://accounting.egi.eu/wlcg/site/CA-UVic-Cloud/njobs/VO/DATE/%s/%s/%s/%s/all/localinfrajobs/JSON/" % (yr,mo,yr,mo)
request=urllib2.urlopen(url)
data=json.load(request)

if len(mo) == 1:
    mo="0"+mo


atlasMismatch = False
belleMismatch = False
aegi = 0
begi = 0
for entry in data:
    try:
        thiskey = "%s-%s"%(yr,mo)
        egijobs=entry[thiskey]
    except KeyError:
        continue
    
    if entry['id'] == 'atlas':
        #check atlas script
        if int(shOut['atlas']['yesterday']) != egijobs and int(shOut['atlas']['today']) != egijobs:
            aegi=egijobs
            atlasMismatch=True    
    elif entry['id'] == 'belle':
        #check belle output
        if int(shOut['belle']['yesterday']) != egijobs and int(shOut['belle']['today']) != egijobs:
            begi=egijobs
            belleMismatch=True    
    else:
        continue


if atlasMismatch or belleMismatch:
    if atlasMismatch:
        sys.stderr.write("Atlas jobs do not match!\nEGI: %s\nScript Yesterday: %s\nScript Today: %s" % (aegi,shOut['atlas']['yesterday'],shOut['atlas']['today']))
        sys.stderr.write("\n")
    if belleMismatch:
        sys.stderr.write("Belle jobs do not match!\nEGI: %s\nScript Yesterday: %s\nScript Today: %s" % (begi,shOut['belle']['yesterday'],shOut['belle']['today']))
        sys.stderr.write("\n")
    raise Exception("Job Mismatch")
