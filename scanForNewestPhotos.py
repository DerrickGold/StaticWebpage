#!/usr/bin/env python3

# Returns a list of all photos/videos in order of newest to oldest.

import os
import sys
import platform
from datetime import datetime
from functools import cmp_to_key
import re

rootDir=sys.argv[1]
exclude=sys.argv[2]

def creation_date(path_to_file):
    """
    Try to get the date that a file was created, falling back to when it was
    last modified if that isn't possible.
    See http://stackoverflow.com/a/39501288/1709587 for explanation.
    """
    if platform.system() == 'Windows':
        return os.path.getctime(path_to_file)
    else:
        stat = os.stat(path_to_file)
        try:
            return stat.st_birthtime
        except AttributeError:
            return stat.st_mtime


# get the file date based on either the name (if name contains a valid date) or file creation time
def get_file_date(filename, path):
    datepart = re.split(r'[-_]', filename)[0]    
    try:
        return datetime.strptime(datepart, "%Y%m%d")
    except:
        return datetime.utcfromtimestamp(creation_date(path + os.sep + filename))

class FileEntry:
    def __init__(self, path, name):
        self.path = path
        self.name = name
        self.date = get_file_date(name, path)

def compare(a):
    return a.date

def scanDir(start_dir, excludePartialsList):
    found=[]
    for root, dirs, files in os.walk(start_dir):
        for file in files:
            skip = False
            for i in excludePartialsList:
                if re.fullmatch(i, file) is not None:
                    skip = True
                    break

            if not skip:
                found.append(FileEntry(root, file))            

    return sorted(found, key=compare, reverse=True)    

files = scanDir(rootDir, exclude.split(','))
for i in files:
    print(i.path + os.sep + i.name)




