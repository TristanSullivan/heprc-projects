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

for entry in data:
    try:
        thiskey = "%s-%s"%(yr,mo)
        egijobs=entry[thiskey]
    except KeyError:
        continue
    
    if entry['id'] == 'atlas':
        #check atlas script
        if shOut['atlas']['yesterday'] != egijobs and int(shOut['atlas']['today']) != egijobs:
                raise Exception("Atlas jobs do not match!\nEGI: %s\nScript Yesterday: %s\nScript Today: %s" % (egijobs,shOut['atlas']['yesterday'],shOut['atlas']['today']))
    elif entry['id'] == 'belle':
        #check belle output
        if shOut['belle']['yesterday'] != egijobs and int(shOut['belle']['today']) != egijobs:
                raise Exception("Belle jobs do not match!\nEGI: %s\nScript Yesterday: %s\nScript Today: %s" % (egijobs,shOut['belle']['yesterday'],shOut['belle']['today']))
    else:
        continue
