#!/bin/bash

#some basic settings
curFile="$1"
newWidth=${2:-"446"}
newHeight=${3:-"240"}
outTag=${4:-"-tb"}


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
    sips -1 -g pixelWidth $file | cut -d'|' -f2 | grep -Eo '[0-9]+'
}

function getHeight() {
    file="$1"
    sips -1 -g pixelHeight $file | cut -d'|' -f2 | grep -Eo '[0-9]+'
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

    #offsetX="0"
    #offsetY=$(echo "($imgHeight-$newHeight)/2" | bc)

    sips --resampleWidth "$tW" $inFile --out "$outFile.tmp" &> /dev/null
    sips --cropToHeightWidth "$tH" "$tW" "$outFile.tmp" --out "$outFile" &> /dev/null
    #rm "$outFile.tmp"
    echo "$outFile.tmp"
}

function scaleHoritzontalImage() {
    inFile="$1"
    outFile="$2"
    tH="$3"
    tW="$4"

    sips --resampleHeight "$tH" $inFile --out "$outFile.tmp" &> /dev/null
    sips --cropToHeightWidth "$tH" "$tW" "$outFile.tmp" --out "$outFile" &> /dev/null
    echo "$outFile.tmp"
}


if (( $(echo "scale=2; $imgRatio > 1.4" | bc) )); then
    # panorama type photos. Resample based on height and crop the horizontal middle section
    tmp=$(scaleHoritzontalImage $curFile $outfile $newHeight $newWidth)
    tmpW=$(getWidth $tmp)
    
    if (( $tmpW < $newWidth )); then
        tmp=$(scaleVerticalImage $curFile $outfile $newHeight $newWidth)
    fi

    rm "$tmp"
else 
    # portrait mode. Resample based on width and crop the vertical middle
    tmp=$(scaleVerticalImage $curFile $outfile $newHeight $newWidth)

    tmpH=$(getHeight $tmp)

    if (( $tmpH < $newHeight )); then
        tmp=$(scaleHoritzontalImage $curFile $outfile $newHeight $newWidth)
    fi

    rm "$tmp"
fi


echo $outfile