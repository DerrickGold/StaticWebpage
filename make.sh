#!/usr/bin/env bash

arg="$1"

OUTPATH="./out"
INPATH="./src"

TEMPLATES_PATH="$INPATH/templates"
WEBSITE_PATH="$INPATH/skeleton/"
GALLERIES_ROOT="$WEBSITE_PATH/assets/galleries"
GALLERIES_OUTPUT="$OUTPATH/assets/galleries"
PROJECTS_OUTPUT="$OUTPATH/projects"
GENERATED_TEMPLATES_PATH="$TEMPLATES_PATH/generated"
NEW_PHOTOS_COUNT="12"

BUILD="false"
DEPLOY="false"
CLEAN="false"
KEEP_ASSETS="false"
MAKE_GH_PROJECTS="false"
MAKE_ALBUMS="false"

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
    "keepAssets")
        KEEP_ASSETS="true"
        shift
        ;;
    "clean")
        CLEAN="true"
        shift
        ;;
    "ghProjects")
        MAKE_GH_PROJECTS="true"
        shift
        ;;
    "albums")
        MAKE_ALBUMS="true"
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
    # make sure to find templates references that only exist on their own line
    find $OUTPATH -iname '*.html' -exec grep -Er "^[[:space:]]*{{.+}}[[:space:]]*\$" {} \;
}

function resolveTemplates() {
    # scan for template usage and replace them
    template_usages=$(findUnresolvedTemplates)

    declare -a inputs
    while read -r line; do
        inputs+=("$line")
    done <<<${template_usages}

    for i in "${inputs[@]}"; do
        local file="$(echo $i | cut -d':' -f1)"
        local template="$(echo $i | cut -d':' -f2 | tr -d ' ' | tr -d '\n\r')"
        local template_file_name="$(echo -n $template | tr -d '{}' | tr -d '\n\r').html"

        if [ -z "$file" ] || [ -z "$template" ]; then
            continue
        fi

        local template_file="$TEMPLATES_PATH/$template_file_name"

        if [ ! -f "$template_file" ]; then
            template_file="$TEMPLATES_PATH/generated/$template_file_name"
        fi

        echo "Replacing $template in $file with $template_file..."
        #contents=$(sed -e "/$template/ {" -e "r $template_file" -e "d" -e "}" "$file")
        local templateContents=$(<$template_file)
        local newFileContents=$(<$file)
        #echo "${newFileContents//$template/$templateContents}" > $file
        contents=$(cat $file | sed -e "/^[[:space:]]*$template[[:space:]]*\$/ {" -e "r $template_file" -e 'd' -e '}')
        echo "$contents" >$file
    done
}

function generateGalleries() {
    local galleries=$(find $GALLERIES_ROOT -type d | tail -n+2 | sort)
    declare -a gallery_paths
    while read -r line; do
        gallery_paths+=("$line")
    done <<<${galleries}

    for p in "${gallery_paths[@]}"; do
        echo "Generating gallery for $p..."
        local outpath="$GALLERIES_OUTPUT/$(basename $p)"
        ./makeGallery.sh "$OUTPATH/" $outpath "$GENERATED_TEMPLATES_PATH"
    done

    # Generate the gallery of newest photos for the home page
    # This will generate a template "NewPics-gallery.html" that can be included
    ./scanForNewestPhotos.py ./out/assets/galleries/ '.*-tb.+,\.DS_Store,.+\.json,.+\.txt' | head -n $NEW_PHOTOS_COUNT |
        xargs ./makeGallery.sh "$OUTPATH/" "$GALLERIES_OUTPUT/NewPics" "$GENERATED_TEMPLATES_PATH" "true"

    echo "No more galleries to generate!"
}

function clean() {
    if [ "$KEEP_ASSETS" == "true" ]; then
        rm $OUTPATH/*.html
        rm -rf $OUTPATH/projects
        if [ "$MAKE_GH_PROJECTS" == "true" ]; then
            echo "Cleaning GH Project templates..."
            rm -rf $GENERATED_TEMPLATES_PATH/project-*.html
        fi
        if [ "$MAKE_ALBUMS" == "true" ]; then
            echo "Cleaning album templtes..."
            rm -rf $GENERATED_TEMPLATES/*-gallery.html
        fi
    else
        rm -rf $OUTPATH
        rm -rf "$GENERATED_TEMPLATES_PATH"
    fi
}

if [ "$CLEAN" == "true" ]; then
    clean
fi

if [ $BUILD == "true" ]; then
    if [ ! -d $OUTPATH ]; then
        mkdir -p $OUTPATH
    fi

    if [ ! -d $PROJECTS_OUTPUT ]; then
        mkdir -p $PROJECTS_OUTPUT
    fi

    if [ ! -d $GENERATED_TEMPLATES_PATH ]; then
        mkdir -p $GENERATED_TEMPLATES_PATH
    fi

    # copy website + assets to out directory for working
    # Template references are lost in the output files after they have been
    # replaced. So we need to copy our originals each time to ensure new template
    # changes will be embedded.
    cp -pr $WEBSITE_PATH $OUTPATH

    #generateProjects
    if [ "$MAKE_GH_PROJECTS" == "true" ]; then
        ./makeGHProjects.sh "$OUTPATH" "$PROJECTS_OUTPUT" "$GENERATED_TEMPLATES_PATH"
    fi

    if [ "$MAKE_ALBUMS" == "true" ]; then
        generateGalleries
    fi

    # keep resolving templates until no more are found. This allows for templates
    # to reference other templates as long as they don't reference themselves.
    echo "Resolving templates..."
    oldResolved=""
    keepLooping="true"
    while [ "$keepLooping" == "true" ]; do
        oldResolved="$(findUnresolvedTemplates | sort -u | uniq)"
        resolveTemplates
        # make sure we exit if we're not seeing any change when trying to resolve templates. This could either be
        # * an infinite loop of a template referencing (a template referencing itself)
        # * a reference to a template that just doesn't exist
        if [ "${oldResolved}" == "$(findUnresolvedTemplates | sort -u | uniq)" ] || [ -z "${oldResolved}" ]; then
            keepLooping="false"
        fi
    done
fi

if [ $DEPLOY == "true" ]; then
    echo "Deploying website data..."
    # add website files and assets, exclude galleries since they'll be a good chunk of data
    aws s3 sync --exclude "assets/galleries/*" "$OUTPATH/." "${BUCKET_PATH}" --delete

    echo "Uploading galleries..."
    # Use check size-only on galleries so that we don't reupload any regenerated images/thumbnails each time.
    # Since we're copying data to the output folder, their timestamps might change causing them to get picked up
    # as a "new" version by S3. We only want to update images that either don't exist, or have been actually modified.
    aws s3 sync "$OUTPATH/assets/galleries" "${BUCKET_PATH}/assets/galleries" --delete --size-only

    echo "Invalidating caches..."
    # invalidate the cache
    aws cloudfront create-invalidation --distribution-id "${DIST_ID}" \
        --paths /index.html /assets/css/main.css "/album/*" "/projects/*"
fi
