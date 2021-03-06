#!/usr/bin/env  python3
# Upload a single file in current directory to internet archive.org

import os,sys
sys.path.append('/usr/local/lib/python2.7/dist-packages')
import json
import shutil
import subprocess
import internetarchive
import re
from datetime import datetime

# error out if environment is missing
try:
   MR_SSD = os.environ["MR_SSD"]
except:
   print('The environment is not set. Please source "<map repo>/generate-regions/setenv"') 
   sys.exit(1)

if len(sys.argv) ==1:
   print("Please indicate permaref for region")
   sys.exit(1)

URL_PREAMBLE = 'https://archive.org/downloads'
region = sys.argv[1]
REGION_INFO = os.path.join(MR_SSD,'../resources/regions.json')
REGION_LIST = os.environ.get("REGION_LIST")
BLAST_VERSION = os.environ.get("BLAST_VERSION")
#print('Regions to process list:%s'%REGION_LIST)
PLANET = os.environ.get("PLANET_MBTILES","")
PROCESS_LIST = json.loads(REGION_LIST)
#print('region.list limits processing to: %s'%REGION_LIST)

MR_HARD_DISK = os.environ.get("MR_HARD_DISK",'/hd/mapgen')
MAP_DATE = os.environ.get("MAP_DATE",'2019-03-09')
MAP_VERSION = os.environ.get("MAP_VERSION",'v.999')
if MAP_VERSION == 'v.999':
   print('The environment is not set. Please run "source setenv"') 
   sys.exit(1)

with open(REGION_INFO,'r') as region_fp:
   try:
      data = json.loads(region_fp.read())
   except:
      print("regions.json parse error")
      sys.exit(1)

   # pull the version string out of the url for use in identity
   #url = data['regions'][region]['url']
   #match = re.search(r'.*\d{4}-\d{2}-\d{2}_(v\d+\.\d+)\..*',url)
   #version =  match.group(1)
   version = MAP_VERSION
   perma_ref = 'en-osm-omt_' + region 
   filename = "%s_%s_%s"%(perma_ref,MAP_DATE,MAP_VERSION)
   url = os.path.join(URL_PREAMBLE,perma_ref,filename + '.zip')

   # Fetch the md5 to see if local file needs uploading
   target_zip = os.path.join(MR_HARD_DISK,os.path.basename(url))
   print(target_zip)

   # Get the md5sum for the specified file
   cmd = 'md5sum %s > /tmp/%s'%(target_zip,filename)
   print('executing command %s'%cmd)
   subprocess.check_output(cmd,shell=True)
   cmd = "awk '{print $1}' /tmp/%s"%filename
   md5 = subprocess.check_output(cmd,shell=True)
   print(md5)

   '''
   with open(target_zip + '.md5','r') as md5_fp:
      instr = md5_fp.read()
      md5 = instr.split(' ')[0]
   if len(md5) == 0:
      print('md5 was zero length. ABORTING')
      sys.exit(1)
   '''

   # Gather together the metadata for archive.org
   md = {}
   md['title'] = "OSM Vector Server for %s"%region
   #md['collection'] = "internetinabox"
   md["creator"] = "Internet in a Box" 
   md["subject"] = "rpi" 
   md["subject"] = "maps" 
   md["licenseurl"] = "http://creativecommons.org/licenses/by-sa/4.0/"
   md["zip_md5"] = md5
   md["mediatype"] = "software"
   md["description"] = "This client/server IIAB package makes OpenStreetMap data in vector format browsable from clients running Windows, Android, iOS browsers." 

   # Check is this has already been uploaded
   identifier = filename
   item = internetarchive.get_item(identifier)
   print('Identifier: %s. Filename: %s'%(identifier,target_zip,))
   if item.metadata:
      if item.metadata['zip_md5'] == md5:
         # already uploaded
         print('local file md5:%s  metadata md5:%s'%(md5,item.metadata['zip_md5']))
         print('Skipping %s -- checksums match'%region)
         sys.exit(1)
      else:
         print('md5sums for %s do not match'%region)
         r = item.modify_metadata({"zip_md5":"%s"%md5})
   else:
      print('Archive.org does not have file with identifier: %s'%identifier) 
   # Debugging information
   print('Uploading %s'%region)
   print('MetaData: %s'%md)
   try:
      r = internetarchive.upload(identifier, files=[target_zip], metadata=md)
      print(r[0].status_code) 
      status = r[0].status_code
   except Exception as e:
      status = 'error'
      with open('./upload.log','a+') as ao_fp:
         ao_fp.write("Exception from internetarchive:%s"%e) 
   with open('./upload.log','a+') as ao_fp:
      now = datetime.now()
      date_time = now.strftime("%m/%d/%Y, %H:%M:%S")
      ao_fp.write('Uploaded %s at %s Status:%s\n'%(identifier,date_time,status))
