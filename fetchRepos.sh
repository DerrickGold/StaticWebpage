#!/usr/bin/env bash

projectRoot="$1"
projectsRootPath="$2"
templatePath="$3"

MANIFEST_FILE="$templatePath/project-manifest.html"

if [ -f "./env.sh" ]; then
    source "./env.sh"
fi

function getReadMe() {
    local repo="$1"
    local readMeAPI="https://api.github.com/repos/$repo/readme"

    url=$(curl -s  -f --request GET --header "Authorization: Bearer $GH_TOKEN" \
        --header "Accept: application/vnd.github.v3+json" \
        --url "$readMeAPI" \
        | jq '.download_url' | tr -d '"')


    curl -s -f "$url"
}

function getPersonalRepos() {
    local page="$1"

    curl -s --request GET --header "Authorization: Bearer $GH_TOKEN" \
        --header "Accept: application/vnd.github.v3+json" \
        --url "https://api.github.com/users/$GH_USERNAME/repos?page=$page" \
        | jq -c ".[]|select(.private == false and .fork == false)|{html_url,description,full_name,name,default_branch}"
}

function generateReadMeSection() {
    local projectFullName="$1"
    local projectName="$2"
    local defaultBranch="$3"
    local templateOutput="$4"
    local rawReadMe=$(getReadMe "$projectFullName")    
    # Process the readme for a better web experience
    # First strip the project title and just replace it with "ReadMe" since the
    # project name is already at the top of the page
    local readMeHtml=$(echo "$rawReadMe" | marked | tail -n+2)
    local newTitledReadMe=$(printf "<h1>ReadMe.md</h1>\n%s" "$readMeHtml")
  
    # Next, replace any relative image paths with absolute paths to the blobs
    local imagePaths=$(echo "$newTitledReadMe" | grep -Eo "img.+src=\"[^ ]+\"" | cut -d'"' -f2)

    if [ -z "$imagePaths" ]; then
        echo "No images found."
        echo "$newTitledReadMe" > $templateOutput
        return 0
    fi

    echo "Found images: $imagePaths"
    declare -a pathsArray
    while read -r line; do
        pathsArray+=("$line")
    done <<< ${imagePaths}

    for url in "${pathsArray[@]}"; do
        if [ -z "$(echo $url | grep -E '^https.+')" ]; then
            # no absolute path was found, insert it
            local newUrl="https://raw.githubusercontent.com/${projectFullName}/${defaultBranch}${url}"
            echo "Replacing relative url: $url with $newUrl"
            local temp=$(echo "$newTitledReadMe" | sed -e "s,$url,$newUrl,g")
            newTitledReadMe="$temp"
        fi
    done
    echo "$newTitledReadMe" > $templateOutput
}


function makeProjectPage() {
    local name="$1"
    local description="$2"
    local fullName="$3"
    local ghUrl="$4"
    local defaultBranch="$5"

    local projectDir="$projectsRootPath/$name"
    mkdir -p "$projectDir"
    local relPath="${projectDir#"$projectRoot/"}"
    local templateName="project-$name-md"
    local templateOutput="$templatePath/$templateName"

    if [ -f "$templateOutput" ]; then 
        return 0
    fi

    generateReadMeSection "$fullName" "$name" "$defaultBranch" "$templateOutput.html"
    if [ "$description" == "null" ]; then
        description=""
    fi

echo '
<!DOCTYPE html>
<html lang="en">
{{head}}
<body>
  {{header}}
  <main id="main" data-aos="fade" data-aos-delay="1500">
    <div class="page-header d-flex align-items-center">
      <div class="container position-relative">
        <div class="row d-flex justify-content-center">
          <div class="col-lg-6 text-center">
            <h2>'"$name"'</h2>
            <p>'"$description"'</p>
          </div>
        </div>
      </div>
    </div>

    <section id="gallery-single" class="gallery-single">
      <div class="container">
        <div class="row justify-content-between gy-4 mt-4">
          <div class="col-lg-8">
            <div class="portfolio-description">
              {{'"$templateName"'}}
            </div>
          </div>

          <div class="col-lg-3">
            <div class="portfolio-info">
              <h3>Project information</h3>
              <ul>
                <li><strong>Project URL</strong> <a href="'"$ghUrl"'"><i class="bi bi-github"></i> Github</a></li>                
              </ul>
            </div>
          </div>

        </div>

      </div>
    </section>
  </main>
  {{footer}}
</body>
</html>
' > "$projectDir/project.html"


    # Generate a "manifest" file that will be used in the header bar listing
    manifest_entry='<li><a href="'"/$relPath/project.html"'">'"$name"'</a></li>'

    if [ ! -f $MANIFEST_FILE ]; then
        echo  "$manifest_entry" >> $MANIFEST_FILE
    elif [ -z "$(grep $name $MANIFEST_FILE)" ]; then
        echo  "$manifest_entry" >> $MANIFEST_FILE
    fi
}

function fetchGHProjects() {
    local ghPage=1
    local repos=$(getPersonalRepos "$ghPage")
    while [ ! -z "$repos" ]; do
        declare -a repoArray
        while read -r line; do
            repoArray+=("$line")
        done <<< ${repos}

        for r in "${repoArray[@]}"; do
            local url=$(echo "$r" | jq .html_url | tr -d '"')
            local desc=$(echo "$r" | jq .description | tr -d '"')
            local name=$(echo "$r" | jq .name | tr -d '"')
            local fullName=$(echo "$r" | jq .full_name | tr -d '"')
            local defaultBranch=$(echo "$r" | jq .default_branch | tr -d '"')
            echo "Generating $fullName..."
            makeProjectPage "$name" "$desc" "$fullName" "$url" "$defaultBranch"
        done

        
        (( ghPage++ ))
        echo "Fetching next page of projects: $ghPage"
        repos=$(getPersonalRepos "$ghPage")
    done
}

fetchGHProjects