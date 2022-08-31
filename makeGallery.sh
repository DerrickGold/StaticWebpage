#!/usr/bin/env bash

# Generate a gallery section from photos in a folder.
# ./makeGallery.sh "$OUTPATH/" "$OUTPATH/assets/img/<galleryFolderRoot>" "$TEMPLATES_PATH/generated"
# outputs a template '<galleryFolderRoot>-gallery.html' to be included

projectRoot="$1"
photosPath="$2"
templatePath="$3"




IMG_GALLERY_NAME=$(basename $photosPath)
OUTPUT_TEMPLATE_PATH="$templatePath/$IMG_GALLERY_NAME-gallery.html"
GENERATED_GALLERY_OUTPATH="$projectRoot"
OUTPUT_TEMPLATE_ROOT_PATH="$GENERATED_GALLERY_OUTPATH/gallery-$IMG_GALLERY_NAME.html"
MANIFEST_FILE="$templatePath/gallery-manifest.html"
OUTPUT_REL_ROOT_PATH="${OUTPUT_TEMPLATE_ROOT_PATH#"$projectRoot/"}"

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
' > $OUTPUT_TEMPLATE_PATH


images=$(find "$photosPath" -type f | sort)

declare -a inputs 
while read -r line; do
    inputs+=("$line")
done <<< ${images}

for i in "${inputs[@]}"; do
    imgRelPath="${i#"$projectRoot"}"
    imgName=$(basename "$i")
    thumbnail=$(./mkthumb.sh "$i" )
    thumbnailRelPath="${thumbnail#"$projectRoot"}"

    echo '
        <div class="col-xl-3 col-lg-4 col-md-6 col-ht-15em">
            <div class="gallery-item h-100">
                <img src='"$thumbnailRelPath"' class="img-fluid" alt="" loading="lazy">
                <div class="gallery-links d-flex align-items-center justify-content-center">
                    <a href='"$imgRelPath"' title='"$imgName"' class="glightbox preview-link"><i class="bi bi-arrows-angle-expand"></i></a>
                </div>
            </div>
        </div>' >> $OUTPUT_TEMPLATE_PATH


done

echo '
            </div>
        </div>
    </section>
' >> $OUTPUT_TEMPLATE_PATH

# generate the gallery page that includes the item template
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
            <p>Site is WIP</p>
          </div>
        </div>
      </div>
    </div><!-- End Page Header -->

    <!-- ======= Gallery Section ======= -->
    {{'"$IMG_GALLERY_NAME-gallery"'}}

  </main><!-- End #main -->

  {{footer}}

</body>

</html>' > $OUTPUT_TEMPLATE_ROOT_PATH


# Generate a "manifest" file that will be used in the header bar listing
echo "<li><a href="$OUTPUT_REL_ROOT_PATH">$IMG_GALLERY_NAME</a></li>" >> $MANIFEST_FILE


