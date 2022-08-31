# Derrick's Static Website

A collection of bash scripts and assets used to generate my static webpage.

The website: https://aws.derrickgold.com

## About

This package contains scripts generating a static website with photo galleries and project pages based from github URLs. This website can then be hosted via AWS S3 and CloudFront.

## Required Software

Requires the following programs:
* `sips` (Scriptable Image Processing System) for thumbnail generation
  * Or `ImageMagic` with the following wrapper: https://gist.github.com/Aerilius/4557816
* `marked` for markdown rendering of github ReadMes: https://github.com/markedjs/marked
* `aws` cli tools: https://aws.amazon.com/cli/
* `jq`: https://stedolan.github.io/jq/


## Scripts Overview

### make.sh

This is the root script that should be executed to generate everything. Includes the following parameters:

* `clean` - deletes the `out` folder in which all the generated pages are written into
* `build` - runs all the generation scripts to produce static HTML files in the `out` folder
* `deploy` - syncs the `out` folder contents to an S3 bucket and invalidates the CloudFront cache

Supports very basic templating to simplify syncing common pieces across multiplate pages. I would recommend using something like Jinja for a more flexible solution. I just wanted a very simple system with minimal dependencies for my own use-cases.

Templates can be inserted in pages using the syntax `{{<template name>}}` where `<template name>` refers to an html file located within the `src/templates` directory.

e.g. `{{footer}}` -> `src/templates/footer.html`

Outputs are **not** linted and will look pretty ugly in terms of generated code. But your whitespace within the templated code shouldn't be impacted.


### makeGalleries.sh

Scans the `out/asset/galleries` path for directories containing images, generates thumbnails for each image, and then generates an html gallery page with the images in the said directories.

e.g.

`out/assets/galleries/MyGallery/image1.jpg`

outputs `gallery-MyGallery.html` containing an:

* image tag with the generated thumbnail (\<img\> -> image1-tb.jpg )
* a link to the full image on the thumbnail (\<a href\> -> image1.jpg)

### mkthumb.sh

Generates a thumbnail from an input image.


## Architecture Setup

* Create an S3 bucket
  * It's safe to enable SSE using a managed KMS key
* Enable "Static website hosting" for S3 bucket
* disable "Block all public access"
* Create a CloudFront distibution for your S3 bucket 
  * make sure to have a domain name ready or use Route53 to create one
  * If bringing your own domain you may need to generate an SSL cert via ACM and perform a DNS validation
* Update `Origin access control settings` and create one for your S3 bucket
* Add policy (see below) to S3 bucket
* Optional: tweak your caching strategy on CloudFront

### Bucket Policy Sample

```
{
    "Version": "2008-10-17",
    "Id": "PolicyForCloudFrontPrivateContent",
    "Statement": [
        {
            "Sid": "AllowCloudFrontServicePrincipal",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudfront.amazonaws.com"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::<YOUR BUCKET NAME>/*",
            "Condition": {
                "StringEquals": {
                    "AWS:SourceArn": "arn:aws:cloudfront::<YOUR ACCOUNT ID>:distribution/<DISTRIBUTEION ID>"
                }
            }
        }
    ]
}
```


## Execution

1. Create an IAM user with S3 and CloudFront permissions. Note the AKID and SKID somewhere safe
2. Configure aws cli credentials using the new IAM user AKID and SKID by running `aws configure`
3. Generate an `env.sh` file in the root directory containing the following:

```
export BUCKET_PATH="s3://<BUCKET NAME>"
export DIST_ID="<CLOUDFRONT DISTRIBUTION ID>"
```

4. Run `./make.sh clean build` to generate gallery thumbnails, galleries, and project pages
5. Run `./make.sh deploy` to sync files to S3 and invalidate the CloudFront cache



## Legal Stuff

Source Template:

```
Template Name: PhotoFolio
Template URL: https://bootstrapmade.com/photofolio-bootstrap-photography-website-template/
Author: BootstrapMade.com
License: https://bootstrapmade.com/license/
```

Template contains some modifications.