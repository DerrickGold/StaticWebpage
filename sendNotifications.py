#!/usr/bin/env python3

# Send email notifications via the Ses lambda proxy to notify
# people of new photos added to the site!

import subprocess
import json
import tempfile
import time
import argparse

EMAILS_PER_SECOND = 14


def invokeProxy(emailList, subject, message, identity, dryRun=True):
    if len(emailList) > 50:
        raise "Email list is too large."

    f = tempfile.NamedTemporaryFile()

    cmd = [
        "aws",
        "lambda",
        "invoke",
        "--cli-binary-format",
        "raw-in-base64-out",
        "--function-name",
        "SesProxy",
        "--payload",
        json.dumps({
            "emails": emailList,
            "subject": subject,
            "message": message,
            "identity": identity,
            "dryRun": dryRun,
        }),
        f.name,
    ]
    print("Command: {}".format(cmd))
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    output, error = process.communicate()

    f.seek(0)
    response = f.read().decode('utf8')
    return output.decode('utf8').strip(), response, error


def getEmailList(filePath):
    try:
        with open(filePath) as f:
            return [e.strip() for e in f.readlines()]
    except Exception as e:
        print("Failed to load email list: {}".format(e))
        return []


def getSubject(name):
    return 'New photos from {}!'.format(name)


def getMessage(name, url):
    return 'New photos have been uploaded by {}. Check them out at:  {}'.format(name, url)


def sendEmails(emailList, rate_per_second, subject, message, identity, dryRun=True):
    if len(emailList) == 0:
        print("no emails to send to, exiting...")
        return

    # split mail list into chunks that can be sent at rate_per_second
    chunks = [emailList[x:x+rate_per_second]
              for x in range(0, len(emailList), rate_per_second)]

    for c in chunks:
        output, response, error = invokeProxy(c, subject, message, identity, dryRun)
        if error is not None:
            print("Failed to send email {}".format(error))
        else:
            print("Sent mail to {}\n{}\n{}".format(c, output, response))

        # sleep to prevent throttling
        time.sleep(1.001)


parser = argparse.ArgumentParser()
parser.add_argument(
    '--name', help='Your name to reference in the email. E.g `<YOURNAME> has uploaded new photos!`'
)
parser.add_argument(
    '--mailSource', help='The source used to send mail via SNS. This is usually your configured identity that you wish to send mail from'
)
parser.add_argument(
    '--emailList', help='File containing one email/line to send notifications to.')

parser.add_argument(
    '--webUrl', default='https://www.derrickgold.com', help='Web site url to link in the emails'
)
parser.add_argument('--dryRun', default='off',
                    help='Do not actually send out the emails, just perform a dry run (lambda is invoked!)')

args = parser.parse_args()


sendEmails(getEmailList(args.emailList), EMAILS_PER_SECOND,
           getSubject(args.name), getMessage(args.name, args.webUrl), args.mailSource, args.dryRun != 'off')
