#!/usr/bin/env bash

# Generate a gallery section from photos in a folder.
# ./makeGallery.sh "$OUTPATH/" "$OUTPATH/assets/img/<galleryFolderRoot>" "$TEMPLATES_PATH/generated"
# outputs a template '<galleryFolderRoot>-gallery.html' to be included

projectRoot="$1"
photosPath="$2"
templatePath="$3"

# if set to true, gallery image templates will be generated but
# a gallery specific page will not be generated or linked in the nav bar.
# Also will not scan a given path for images, all images must be provided as additional
# parameters
embeddedGallery="$4"
if [ ! -z "$embeddedGallery" ]; then
  shift 4
fi

IMG_GALLERY_NAME=$(basename $photosPath)
OUTPUT_TEMPLATE_PATH="$templatePath/$IMG_GALLERY_NAME-gallery.html"
GENERATED_GALLERY_OUTPATH="$projectRoot/album"
OUTPUT_TEMPLATE_ROOT_PATH="$GENERATED_GALLERY_OUTPATH/$IMG_GALLERY_NAME.html"
MANIFEST_FILE="$templatePath/gallery-manifest.html"
OUTPUT_REL_ROOT_PATH="${OUTPUT_TEMPLATE_ROOT_PATH#"$projectRoot/"}"
DETAILS_JSON="$photosPath/details.json"

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

declare -a inputs

if [ -z "$embeddedGallery" ]; then
  images=$(find "$photosPath" -type f -not -name '*-tb*' | sort)
  while read -r line; do
    inputs+=("$line")
  done <<<${images}
else
  while [[ $# -gt 0 ]]; do
    inputs+=("$1")
    shift
  done
fi

for i in "${inputs[@]}"; do
  imgFile="$i"
  mimeType=$(file -b --mime-type "$imgFile")
  icon="bi-arrows-angle-expand"

  if [ ! -z "$(echo $mimeType | grep 'video')" ]; then
    icon="bi-play-btn-fill"

    if [ -z "$(echo $mimeType | grep 'mp4')" ]; then
      # make sure video is streamable
      extension="${i##*.}"
      mp4Out=${i/.$extension/"-web.mp4"}
      if [ ! -f "$mp4Out" ]; then
        ffmpeg -i "$i" -c:v copy -c:a copy "$mp4Out"
        # make sure we preserve the creation dates
        touch -r "$i" "$mp4Out"
        rm "$i"
      fi
      imgFile="$mp4Out"
    fi
  elif [ ! -z "$(echo $mimeType | grep 'image')" ]; then
    # convert any heic files to jpg if found. Heic is a patented image format that browsers may
    # not support natively
    if [[ $imgFile == *.heic ]]; then
      imgFile="${i%.heic}.jpg"
      convert "$i" "$imgFile"
      touch -r "$i" "$imgFile"
      # remove the heic file so it doesn't get included in the gallery
      rm "$i"
    fi
  else
    # skip processing file if it's not an image or video
    continue
  fi

  imgRelPath="${imgFile#"$projectRoot"}"
  imgName=$(basename "$imgFile")

  # skip already added file
  if [ ! -z "$(grep $imgRelPath $OUTPUT_TEMPLATE_PATH)" ]; then
    continue
  fi

  # thumbnail should point to the newly generated file from the source
  thumbnail=$(./makeThumbnail.sh "$imgFile")
  thumbnailRelPath="${thumbnail#"$projectRoot"}"

  # if a details.json file exists (<filename>:<text>), add the corresponding description
  # of the file to the big image viewer.
  details="$imgName"
  detailsPath="$(dirname $imgFile)/details.json"
  if [ -f "$detailsPath" ]; then
    details=$(cat "$detailsPath" | jq '.["'"$imgName"'"]')
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

if [ "$embeddedGallery" == "true" ]; then
  echo "Embedded gallery templates generated"
  exit 0
fi

# generate the gallery page that includes the item template
echo "Creating gallery page for '$IMG_GALLERY_NAME'"

albumDescription=""
if [ -f "$DETAILS_JSON" ]; then
  albumDescription=$(cat "$DETAILS_JSON" | jq -r '.description')
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
