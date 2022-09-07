#!/usr/bin/env bash

# Generate a gallery section from photos in a folder.
# ./makeGallery.sh "$OUTPATH/" "$OUTPATH/assets/img/<galleryFolderRoot>" "$TEMPLATES_PATH/generated"
# outputs a template '<galleryFolderRoot>-gallery.html' to be included

projectRoot="$1"
photosPath="$2"
templatePath="$3"

IMG_GALLERY_NAME=$(basename $photosPath)
OUTPUT_TEMPLATE_PATH="$templatePath/$IMG_GALLERY_NAME-gallery.html"
GENERATED_GALLERY_OUTPATH="$projectRoot/album"
OUTPUT_TEMPLATE_ROOT_PATH="$GENERATED_GALLERY_OUTPATH/$IMG_GALLERY_NAME.html"
MANIFEST_FILE="$templatePath/gallery-manifest.html"
OUTPUT_REL_ROOT_PATH="${OUTPUT_TEMPLATE_ROOT_PATH#"$projectRoot/"}"
DETAILS_JSON="$photosPath/details.json"

# values go from 0 (best) to 63 (worst)
WEBM_QUALITY="30"

if [ ! -d "$templatePath" ]; then
  mkdir -p "$templatePath"
fi

if [ ! -d "$GENERATED_GALLERY_OUTPATH" ]; then
  mkdir -p "$GENERATED_GALLERY_OUTPATH"
fi

# Generate gallery item listing

echo '
    <section id="gallery" class="gallery">
      <div class="container-fluid">
        <div class="row gy-4 justify-content-center">
' >$OUTPUT_TEMPLATE_PATH

images=$(find "$photosPath" -type f -not -name '*-tb*' | sort)


declare -a inputs
while read -r line; do
  inputs+=("$line")
done <<<${images}

for i in "${inputs[@]}"; do
  # skip processing file if it's not an image
  imgFile="$i"
  mimeType=$(file -b --mime-type "$imgFile")
  icon="bi-arrows-angle-expand"
  cleanUpSrc="false"

  if [ ! -z "$(echo $mimeType | grep 'video')" ]; then
    # if it's a video, create a thumbnail from the first frame
    echo "Video found, generating thumbnail"
    imgFile="${i}.jpg"
    yes | ffmpeg -i "$i" -ss 00:00:1.000 -vframes 1 "$imgFile"
    icon="bi-play-btn-fill"
    # don't let the img extracted from video files be included in the album
    # as it's own entry.
    cleanUpSrc="true"

    # make sure video is streamable
    if [ -z "$(echo $mimeType | grep 'mp4')" ]; then
      mp4Out="${i}.mp4"
      if [ ! -f "$mp4Out" ]; then
        ffmpeg -i "$i" -c:v copy -c:a copy "$mp4Out"
        rm "$i"
      fi
      i="$mp4Out"
    fi

    # Then convert the video to webm for best web performance if it isn't already
    # Make sure we don't reconvert videos that have already been converted.
    # You will need to delete old videos if the quality parameters are changed to regenerate
    # them.

    #if [ ! "$i" == "*.webm" ]; then
    #  webmOut="${i}.webm"
    #  if [ ! -f "$webmOut" ]; then
        # constant quality (single pass mode)
    #    ffmpeg -i "$i" -c:v libvpx-vp9 -crf "${WEBM_QUALITY}" -b:v 0 -c:a libvorbis "$webmOut"
        # two pass mode
        #ffmpeg -i "$i" -c:v libvpx-vp9 -b:v 0 -crf "${WEBM_QUALITY}"  -pass 1 -an -f null /dev/null && \
        #ffmpeg -i "$i" -c:v libvpx-vp9 -b:v 0 -crf "${WEBM_QUALITY}"  -pass 2 -c:a libopus "$webmOut"

     #   rm "$i"
     # fi
     # i="$webmOut"
    # fi
  fi

  # convert any heic files to jpg if found. Heic is a patented image format that browsers may
  # not support natively
  if [[ $imgFile == *.heic ]]; then
    imgFile="${i%.heic}.jpg"
    convert "$i" "$imgFile"
    # remove the heic file so it doesn't get included in the gallery
    rm "$i"
    # update our file path pointer to our new jpg file
    i="$imgFile"
  fi

  mimeType=$(file -b --mime-type "$imgFile")
  if [ -z "$(echo $mimeType | grep 'image')" ]; then
    continue
  fi

  # always point to the source object if it's a video or image
  imgRelPath="${i#"$projectRoot"}"
  imgName=$(basename "$i")

  # skip already added images
  if [ ! -z "$(grep $imgRelPath $OUTPUT_TEMPLATE_PATH)" ]; then
    continue
  fi

  # thumbnail should point to the newly generated file from the source
  thumbnail=$(./makeThumbnail.sh "$imgFile")
  thumbnailRelPath="${thumbnail#"$projectRoot"}"

  
  if [ "$cleanUpSrc" == "true" ]; then
    rm "$imgFile"
  fi

  # if a details.json file exists (<filename>:<text>), add the corresponding description
  # of the file to the big image viewer.
  details="$imgName"
  if [ -f "$DETAILS_JSON" ]; then
    details=$(cat "$DETAILS_JSON" | jq '.["'"$imgName"'"]' )
    if [ "$details" == "null" ]; then
      details="$imgName"
    fi
  fi

  echo '
      <div class="col-xl-3 col-lg-4 col-md-6 col-ht-15em">
          <div class="gallery-item h-100">
              <img src='"/$thumbnailRelPath"' class="img-fluid" alt="" loading="lazy">
              <div class="gallery-links d-flex align-items-center justify-content-center">
                  <a href='"/$imgRelPath"' title='"$details"' class="glightbox preview-link"><i class="bi '"$icon"'"></i></a>
              </div>
          </div>
      </div>' >>$OUTPUT_TEMPLATE_PATH

done

echo '
            </div>
        </div>
    </section>
' >>$OUTPUT_TEMPLATE_PATH

# generate the gallery page that includes the item template
echo "Creating gallery page for '$IMG_GALLERY_NAME'"


albumDescription=""
if [ -f "$DETAILS_JSON" ]; then
  albumDescription=$(cat "$DETAILS_JSON" | jq -r '.description' )
  if [ "$albumDescription" == "null" ]; then
    albumDescription=""
  fi
fi

echo '
<!DOCTYPE html>
<html lang="en">

{{head}}

<body>

  <!-- ======= Header ======= -->
  {{header}}

  <main id="main" data-aos="fade" data-aos-delay="1500">

    <!-- ======= End Page Header ======= -->
    <div class="page-header d-flex align-items-center">
      <div class="container position-relative">
        <div class="row d-flex justify-content-center">
          <div class="col-lg-6 text-center">
            <h2>'$IMG_GALLERY_NAME'</h2>
            <p>'$albumDescription'</p>
          </div>
        </div>
      </div>
    </div><!-- End Page Header -->

    <!-- ======= Gallery Section ======= -->
    {{'"$IMG_GALLERY_NAME-gallery"'}}

  </main><!-- End #main -->

  {{footer}}

</body>

</html>' >$OUTPUT_TEMPLATE_ROOT_PATH

# Generate a "manifest" file that will be used in the header bar listing
echo "Adding '$IMG_GALLERY_NAME' to the menu bar"
manifest_entry="<li><a href="/$OUTPUT_REL_ROOT_PATH">$IMG_GALLERY_NAME</a></li>"

if [ ! -f $MANIFEST_FILE ]; then
  echo "$manifest_entry" >>$MANIFEST_FILE
elif [ -z "$(grep $IMG_GALLERY_NAME $MANIFEST_FILE)" ]; then
  echo "$manifest_entry" >>$MANIFEST_FILE
fi

echo "Galery '$IMG_GALLERY_NAME' done generating"
