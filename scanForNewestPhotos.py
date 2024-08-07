#!/usr/bin/env python3

# Generates a gallery from an input folder.
# Image descriptions can be defined in a `details.json` file in the same directory as the image
# that maps `[filename]:<description>`, where filename is the name of the file excluding it's extension.

import os
import platform
from datetime import datetime
import re
import mimetypes
import subprocess
import json
import argparse

CONVERT = "/opt/homebrew/bin/convert"


def runCommandArray(cmds):
    process = subprocess.Popen(cmds, stdout=subprocess.PIPE)
    output, error = process.communicate()
    return output.decode('utf8').strip(), error

def removeSilent(path):
    try:
        print("Deleting {0}".format(path))
        os.remove(path)
    except:
        pass


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
    datepart = re.split(r'[-_]', filename)

    try:
        while len(datepart) > 0:
            curDate = datepart.pop(0)
            if not curDate.isnumeric():
                continue
            
            return str(datetime.strptime(curDate, "%Y%m%d")) + ''.join(datepart)
        raise "No dates found in name"
    except:
        return str(datetime.utcfromtimestamp(creation_date(path + os.sep + filename)))


class AlbumDetailsCache:
    def __init__(self):
        self.cache = {}
        self.pathCache = {}

    def loadAlbumDetails(self, albumName, rootPath):
        detailsPath = rootPath + os.sep + "details.json"
        self.pathCache[albumName] = detailsPath
        try:
            with open(detailsPath) as j:
                self.cache[albumName] = json.load(j)
        except:
            pass

    def getAlbumData(self, albumName):
        if albumName in self.cache:
            return self.cache[albumName]
        return None

    def loadDetails(self, fileEntry):
        if fileEntry.albumName not in self.cache:
            self.loadAlbumDetails(fileEntry.albumName, fileEntry.path)

    def getEntryDetails(self, fileEntry):
        self.loadDetails(fileEntry)
        if fileEntry.detailKey in self.cache[fileEntry.albumName]:
            return self.cache[fileEntry.albumName][fileEntry.detailKey]
        else:
            self.cache[fileEntry.albumName][fileEntry.detailKey] = ""
            return ""
        
    def dumpDetails(self, albumName):
        with open(self.pathCache[albumName], "w") as j:
            j.write(json.dumps(self.cache[albumName], indent=2, sort_keys=True))


class FileEntry:
    def __init__(self, path, name, detailCache):
        self.path = path
        self.name = name
        self.date = get_file_date(name, path)
        self.albumName = os.path.basename(self.path)
        self.detailKey, _ = os.path.splitext(self.name)
        self.detailCache = detailCache

    def getDetails(self):
        return self.detailCache.getEntryDetails(self)


def compareFileEntry(a):
    return a.date


class GalleryGenerator:
    def __init__(self, rootDir, excludePatterns, isEmbedded, projectRoot, templateOutputPath, albumsOutputDir, navBarTemplatePath, maxImages):
        self.detailsCache = AlbumDetailsCache()
        
        self.mimetypes = mimetypes.MimeTypes()
        self.mimetypes.add_type("image/heic", ".heic")

        self.outputRoot = projectRoot
        self.isEmbedded = isEmbedded
        self.templateOutputPath = templateOutputPath
        self.albumsRoot = albumsOutputDir
        os.makedirs(self.albumsRoot, exist_ok=True)

        self.galleryName = os.path.basename(rootDir)
        albumOutputPath = self.getAlbumOutputPath(self.galleryName)
        self.navBarTemplatePath = navBarTemplatePath

        self.detailsCache.loadAlbumDetails(self.galleryName, rootDir)
        albumDetails = self.detailsCache.getAlbumData(self.galleryName)

        self.galleryNiceName = re.sub('_', ' ', self.galleryName)
        # allow overriding of album name
        if 'albumName' in albumDetails:
            self.galleryNiceName = albumDetails['albumName']

        reverseListing = False
        if albumDetails is not None and 'reverseList' in albumDetails:
            reverseListing = albumDetails['reverseList']

        files = self.scanFiles(
            rootDir, excludePatterns.split(','), reverseListing)

        if maxImages > 0:
            newFiles = files[0:maxImages]
            self.makeGalleryListing(newFiles)
        else:
            self.makeGalleryListing(files)

        if not self.isEmbedded and albumDetails is not None:
            self.makeGalleryPage(albumOutputPath, albumDetails['description'])
            self.addToNavBar()

        self.detailsCache.dumpDetails(self.galleryName)

    def getAlbumOutputPath(self, albumName):
        return self.albumsRoot + os.sep + albumName + '.html'

    def getAlbumRelUrl(self, albumName):
        localPath = self.getAlbumOutputPath(albumName)
        return localPath.replace(self.outputRoot, u'', 1)

    def scanFiles(self, start_dir, excludePartialsList, reverseList):
        found = []
        for root, dirs, files in os.walk(start_dir):
            for file in files:
                skip = False
                for i in excludePartialsList:
                    if re.fullmatch(i, file) is not None:
                        skip = True
                        print("Skipping {0}".format(file))
                        break

                if not skip:
                    found.append(FileEntry(root, file, self.detailsCache))

        return sorted(found, key=compareFileEntry, reverse=reverseList)

    def convertVideo(self, filePath, fname):
        mp4Out = fname+"-web.mp4"
        if not os.path.exists(mp4Out):
            print("Non-mp4 video found, converting...")
            print("Conversion input: " + 'ffmpeg -i ' + filePath + ' -vcodec libx264 -pix_fmt yuv420p ' + mp4Out)
            _, error = runCommandArray(['ffmpeg', '-i', filePath, '-vcodec', 'libx264', '-pix_fmt', 'yuv420p', mp4Out])
            if error:
                print(error)

            runCommandArray(['touch','-r', filePath, mp4Out])
        else:
            print("Path already exists: " + mp4Out)
        # cleanup original file
        removeSilent(filePath)
        return mp4Out
    
    def shouldConvertVideo(self, mimetype, filePath):
        result, error = runCommandArray(['file', filePath])
        if error:
            print(error)
            return False
        
        sanitizedResult = result.replace(filePath, '')        
        # 3gp+ can apepar as a regular mp4 file in the mime type, but
        # isn't compatable in all browsers
        if '3gp' in sanitizedResult.lower() or "mp4" not in mimetype or "ISO 14496-14" in sanitizedResult:
            return True
        
        print("Skipping conversion of video. Found supported mimetype: {0}, OS reported type: {1}".format(mimetype, sanitizedResult))
        return False


    def convertImage(self, filePath, fname):
        newImage = fname + ".jpg"
        if not os.path.exists(newImage):
            print("heic image found, converting {0} to {1}".format(filePath, newImage))
            _, error = runCommandArray([
                CONVERT,
                filePath,
                '-quality', 
                '100',
                newImage
            ])
            runCommandArray(['touch', '-r', filePath, newImage])

        removeSilent(filePath)
        return newImage

    def makeGalleryListing(self, itemList):
        addedImages = set()

        with open(self.templateOutputPath, "w") as template:
            template.write('''
                <section id="gallery" class="gallery">
                    <div class="container-fluid">
                        <div class="row gy-4 justify-content-center">
            ''')

            for i in itemList:
                filePath = i.path + os.sep + i.name
                mt = self.mimetypes.guess_type(filePath)[0]

                icon = "bi-arrows-angle-expand"
                fname, fext = os.path.splitext(filePath)
                if fname in addedImages:
                    print("Skipping already added image {0}".format(fname))
                    continue

                try:
                    if "video" in mt:
                        icon = "bi-play-btn-fill"
                        print("Adding video {0}".format(filePath))
                        if self.shouldConvertVideo(mt, filePath):
                            filePath = self.convertVideo(filePath, fname)
                    elif "image" in mt:
                        print("Adding image {0}".format(filePath))
                        if "heic" in fext:
                            filePath = self.convertImage(filePath, fname)
                    else:
                        continue
                except Exception as e:
                    print("Failed on: " + filePath)
                    print(e)
                    continue

                imageRelPath = filePath.replace(self.outputRoot, u'', 1)
                imageDetails = i.getDetails()
                galleryLink = ""
                if self.isEmbedded:
                    galleryLink = '<a href="{0}" class="details-link"><i class="bi bi-link-45deg"></i></a>' \
                        .format(self.getAlbumRelUrl(i.albumName))

                thumbnail, _ = runCommandArray(['./makeThumbnail.sh', filePath])
                thumbnailRelPath = str(thumbnail).replace(
                    self.outputRoot, u'', 1)

                template.write('''
                    <div class="col-xl-3 col-lg-4 col-md-6 col-ht-15em">
                        <div class="gallery-item h-100">
                            <img src="{0}" class="img-fluid" alt="" loading="lazy">
                            <div class="gallery-links d-flex align-items-center justify-content-center">
                                <a href="{1}" title="{2}" class="glightbox preview-link"><i class="bi {3}"></i></a>
                                {4}
                            </div>
                        </div>
                    </div>
                '''.format(thumbnailRelPath, imageRelPath, imageDetails, icon, galleryLink))

                addedImages.add(fname)

            template.write('''            
                    </div>
                </div>
            </section>''')

    def makeGalleryPage(self, galleryOutputPath, description, ):
        with open(galleryOutputPath, 'w+') as o:
            o.write('''
<!DOCTYPE html>
<html lang="en">

{{{{head}}}}

<body>

  <!-- ======= Header ======= -->
  {{{{header}}}}

  <main id="main" data-aos="fade" data-aos-delay="1500">

    <!-- ======= End Page Header ======= -->
    <div class="page-header d-flex align-items-center">
      <div class="container position-relative">
        <div class="row d-flex justify-content-center">
          <div class="col-lg-6 text-center">
            <h2>{1}</h2>
            <p>{2}</p>
          </div>
        </div>
      </div>
    </div><!-- End Page Header -->

    <!-- ======= Gallery Section ======= -->
    {{{{gallery-{0}}}}}

  </main><!-- End #main -->
  {{{{footer}}}}
</body>
</html>          
            '''.format(self.galleryName, self.galleryNiceName, description))

    def addToNavBar(self):
        entry = '<li><a href="{0}">{1}</a></li>\n'.format(
            self.getAlbumRelUrl(self.galleryName), self.galleryNiceName)

        # Sort the albums
        lines = []
        try:
            with open(self.navBarTemplatePath, 'r') as f:
                lines = f.readlines()
        except:
            print("Nav bar manifest doesn't exist, will create one...")
            pass

        found = False
        for l in lines:
            if self.galleryName in l:
                found = True
                break

        if not found:
            lines.append(entry)
        
        # always re-sort entries just in case
        lines.sort()
        with open(self.navBarTemplatePath, 'w') as f:
            f.writelines(lines)


# Script start
parser = argparse.ArgumentParser()
parser.add_argument(
    '--scanDir', help='directory to scan for images and videos')
parser.add_argument(
    '--excludes', help='comma separated list of regexps of file names to exclude in scan')
parser.add_argument('--embedded', action='store_true',
                    help='if true only the image gallery listing temlate is generated and no dedicate gallery page will be created.')
parser.add_argument('--maxImages', default=0,
                    help='Max number of images to generate in a gallery. Leave 0 for all images', type=int)
parser.add_argument(
    '--outputRoot', help='Root output folder containing all generated webpage data')
parser.add_argument('--galleryTemplatePath',
                    help='file path to write out the generated gallery items listing template')
parser.add_argument('--albumOutputRoot',
                    help='output directory to write generated album page')
parser.add_argument(
    '--manifestPath', help='path to write out the album listing template included in the nav bar')

args = parser.parse_args()

GalleryGenerator(rootDir=args.scanDir, excludePatterns=args.excludes, isEmbedded=args.embedded, projectRoot=args.outputRoot,
                 templateOutputPath=args.galleryTemplatePath, albumsOutputDir=args.albumOutputRoot, navBarTemplatePath=args.manifestPath,
                 maxImages=args.maxImages)
