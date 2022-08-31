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

BUILD="false"
DEPLOY="false"
KEEP_ASSETS="false"

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
        if [ $KEEP_ASSETS == "true" ]; then
            rm $OUTPATH/*.html
            rm -rf $OUTPATH/projects
        else
            rm -rf $OUTPATH
        fi
        rm -rf "$GENERATED_TEMPLATES_PATH"
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
        local file="$(echo $i | cut -d':' -f1)"
        local template="$(echo $i | cut -d':' -f2 | tr -d ' ' | tr -d '\n\r')"
        local template_file_name="$(echo -n $template | tr -d '{}' | tr -d '\n\r').html"

        local template_file="$TEMPLATES_PATH/$template_file_name"

        if [ ! -f "$template_file" ]; then
            template_file="$TEMPLATES_PATH/generated/$template_file_name"
        fi

        echo "Replacing $template in $file with $template_file..."
        #contents=$(sed -e "/$template/ {" -e "r $template_file" -e "d" -e "}" "$file")
        local templateContents=$(<$template_file)
        local newFileContents=$(<$file)
        echo "${newFileContents//$template/$templateContents}" > $file
    done
}

function generateGalleries() {
    #galleries=$(ls -d $GALLERIES_ROOT/* | sort)
    local galleries=$(find $GALLERIES_ROOT -type d | tail -n+2)
    declare -a gallery_paths 
    while read -r line; do
        gallery_paths+=("$line")
    done <<< ${galleries}

    for p in "${gallery_paths[@]}"; do
        echo "Generating gallery for $p..."
        local outpath="$GALLERIES_OUTPUT/$(basename $p)"
        if [ ! -f "$outpath" ]; then
            ./makeGallery.sh "$OUTPATH/" $outpath "$GENERATED_TEMPLATES_PATH"
        fi
    done
}

function generateProjects() {
    local projects=$(find $PROJECTS_OUTPUT -type d | tail -n+2)
    declare -a project_paths 
    while read -r line; do
        project_paths+=("$line")
    done <<< ${projects}

    for p in "${project_paths[@]}"; do
        echo "Generating project for $p..."
        local outpath="$PROJECTS_OUTPUT/$(basename $p)"
        ./makeProject.sh "$OUTPATH/" $outpath "$GENERATED_TEMPLATES_PATH"
    done

}


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
    rsync -tur $WEBSITE_PATH $OUTPATH

    #generateProjects
    ./fetchRepos.sh "$OUTPATH" "$PROJECTS_OUTPUT" "$GENERATED_TEMPLATES_PATH"
    generateGalleries

    # keep resolving templates until no more are found. This allows for templates
    # to reference other templates as long as they don't reference themselves.
    oldResolved="notEmpty"
    keepLooping="true"
    while [ ! -z "${oldResolved}" ] && [ "$keepLooping" == "true" ]; do
        oldResolved="$(findUnresolvedTemplates | sort -u | uniq)"
        resolveTemplates
        if [ "${oldResolved}" == "$(findUnresolvedTemplates | sort -u | uniq)" ]; then
            keepLooping="false"
        fi
    done
fi


if [ $DEPLOY == "true" ]; then
    echo "Deploying..."
    # add files
    aws s3 sync "$OUTPATH/." "${BUCKET_PATH}" --delete
    # invalidate the cache
    aws cloudfront create-invalidation --distribution-id "${DIST_ID}" \
        --paths /index.html /assets/css/main.css
fi


