#!/usr/bin/env bash

arg="$1"

OUTPATH="./out"
INPATH="./src"

TEMPLATES_PATH="$INPATH/templates"
WEBSITE_PATH="$INPATH/skeleton/"
GALLERIES_ROOT="$WEBSITE_PATH/assets/galleries"
GALLERIES_OUTPUT="$OUTPATH/assets/galleries"

BUILD="false"
DEPLOY="false"

# Contains the following variables
#
# export BUCKET_PATH="s3://<BUCKET NAME>"
# export DIST_ID="<CLOUDFRONT DISTRIBUTION ID>"
#
if [ -f "./env.sh" ]; then
    source "./env.sh"
fi


while [[ $# -gt 0 ]]; do
  case $1 in
    "clean")
        rm -rf $OUTPATH
        rm -rf "$TEMPLATES_PATH/generated"
        shift
    ;;
    "build")
        BUILD="true"
        shift
    ;;
    "deploy")
        DEPLOY="true"
        shift
    ;;
  esac
done  


function findUnresolvedTemplates() {
    find $OUTPATH -iname '*.html' -exec grep -Er "{{.+}}" {} \;
}

function resolveTemplates() {
    # scan for template usage and replace them
    #template_usages=$(grep -Er "{{.+}}" $OUTPATH/***.html | sort -u | uniq)
    template_usages=$(findUnresolvedTemplates)

    declare -a inputs 
    while read -r line; do
        inputs+=("$line")
    done <<< ${template_usages}

    for i in "${inputs[@]}"; do
        file="$(echo $i | cut -d':' -f1)"
        template="$(echo $i | cut -d':' -f2 | tr -d ' ' | tr -d '\n\r')"
        template_file_name="$(echo -n $template | tr -d '{}' | tr -d '\n\r').html"

        template_file="$TEMPLATES_PATH/$template_file_name"

        if [ ! -f "$template_file" ]; then
            template_file="$TEMPLATES_PATH/generated/$template_file_name"
        fi

        echo "Replacing $template in $file with $template_file..."
        #contents=$(sed -e "/$template/ {" -e "r $template_file" -e "d" -e "}" "$file")
        templateContents=$(<$template_file)
        newFileContents=$(<$file)
        echo "${newFileContents//$template/$templateContents}" > $file
    done
}

function generateGalleries() {
    galleries=$(ls -d $GALLERIES_ROOT/* | sort)
    declare -a gallery_paths 
    while read -r line; do
        gallery_paths+=("$line")
    done <<< ${galleries}

    for p in "${gallery_paths[@]}"; do
        echo "Generating gallery for $p..."
        outpath="$GALLERIES_OUTPUT/$(basename $p)"
        ./makeGallery.sh "$OUTPATH/" $outpath "$TEMPLATES_PATH/generated"
    done
}

# clean output dir
if [ ! -d $OUTPATH ]; then
    mkdir -p $OUTPATH
fi


if [ $BUILD == "true" ]; then
    # copy website + assets to out directory for working
    rsync -tur $WEBSITE_PATH $OUTPATH

    generateGalleries

    # keep resolving templates until no more are found. This allows for templates
    # to reference other templates as long as they don't reference themselves.
    while [ ! -z  "$(findUnresolvedTemplates | sort -u | uniq)" ]; do
        resolveTemplates
    done
fi


if [ $DEPLOY == "true" ]; then
    # add files
    aws s3 sync "$OUTPATH/." "${BUCKET_PATH}" --delete
    # invalidate the cache
    aws cloudfront create-invalidation --distribution-id "${DIST_ID}" \
        --paths /index.html /assets/css/main.css
fi


