#!/bin/bash

# Generate a thumbnail for an input image or video file

#some basic settings
curFile="$1"
newWidth=${2:-"446"}
newHeight=${3:-"240"}
outTag=${4:-"-tb"}

deleteInput="false"

if [ -z $curFile ]; then
    echo "No file found"
    exit 0
fi

#get file extension
extension="${curFile##*.}"
if [ -z $extension ]; then
    echo "No image extension found"
    exit 0
fi

mimeType=$(file -b --mime-type "$curFile")
if [ ! -z "$(echo $mimeType | grep 'video')" ]; then
    # if it's a video, create a thumbnail from the first frame
    imgFile="${curFile/.$extension/.jpg}"

    # Check if the thumbnail already exists before extracting
    outfile="${curFile/.$extension/$outTag.jpg}"
    # if the thumbnail exists already, skip processing it
    if [ -f "$outfile" ]; then
        echo "$outfile"
        exit 0
    fi

    yes | ffmpeg -i "$curFile" -ss 00:00:1.000 -frames:v 1 "$imgFile"
    extension="jpg"
    curFile="$imgFile"
    deleteInput="true"
fi

#set output file name
outfile="${curFile/.$extension/$outTag.$extension}"
# if the thumbnail exists already, skip processing it
if [ -f "$outfile" ]; then
    echo "$outfile"
    exit 0
fi

#resize the image
#if (( $(echo "scale=2; $imgRatio > 1.6" | bc) )); then
function getWidth() {
    file="$1"
    #sips -1 -g pixelWidth $file | cut -d'|' -f2 | grep -Eo '[0-9]+'
    identify -quiet -auto-orient -format %w "$file" | grep -Eo '[0-9]+'
}

function getHeight() {
    file="$1"
    #sips -1 -g pixelHeight $file | cut -d'|' -f2 | grep -Eo '[0-9]+'
    identify -quiet -auto-orient -format %h "$file" | grep -Eo '[0-9]+'
}

# get image dimensions to figure out the best way of generating the thumbnail
imgWidth="$(getWidth $curFile)"
imgHeight="$(getHeight $curFile)"
imgRatio=$(echo "scale=2; $imgWidth/$imgHeight" | bc)
function scaleVerticalImage() {
    inFile="$1"
    outFile="$2"
    tH="$3"
    tW="$4"
    convert -quiet -auto-orient "$inFile" -resize "${tW}x" "$outFile.tmp"
    convert -quiet -auto-orient -gravity center "$outFile.tmp" -crop "${tW}x${tH}+0+0" "$outFile"
    echo "$outFile.tmp"
}

function scaleHoritzontalImage() {
    inFile="$1"
    outFile="$2"
    tH="$3"
    tW="$4"
    convert -quiet -auto-orient "$inFile" -resize "x${tW}" "$outFile.tmp"
    convert -quiet -auto-orient -gravity center "$outFile.tmp" -crop "${tW}x${tH}+0+0" "$outFile"
    echo "$outFile.tmp"
}

if (($(echo "scale=2; $imgRatio > 1.4" | bc))); then
    # panorama type photos. Resample based on height and crop the horizontal middle section
    tmp=$(scaleHoritzontalImage $curFile $outfile $newHeight $newWidth)
    tmpW=$(getWidth $tmp)

    if (($tmpW < $newWidth)); then
        tmp=$(scaleVerticalImage $curFile $outfile $newHeight $newWidth)
    fi

    rm "$tmp"
elif (($(echo "scale=2; $imgRatio > 0.9" | bc))); then
    # portrait mode. Resample based on width and crop the vertical middle
    tmp=$(scaleVerticalImage $curFile $outfile $newHeight $newWidth)

    tmpH=$(getHeight $tmp)

    if (($tmpH < $newHeight)); then
        tmp=$(scaleHoritzontalImage $curFile $outfile $newHeight $newWidth)
    fi

    rm "$tmp"
else
    # portrait mode. Resample based on width and crop the vertical middle
    tmp=$(scaleVerticalImage $curFile $outfile $newHeight $newWidth)
    rm "$tmp"
fi

if [ "$deleteInput" == "true" ]; then
    rm "$curFile"
fi

echo $outfile
