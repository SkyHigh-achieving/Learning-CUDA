#!/bin/bash
KEY_PATH="/mnt/c/Users/Administrator/.ssh/ksy.id"
cp "$KEY_PATH" /tmp/ksy.id && chmod 600 /tmp/ksy.id
ssh -p 2222 -i /tmp/ksy.id -o StrictHostKeyChecking=no qtc_yu@8.145.51.96 "ls -R ~/homework"
rm /tmp/ksy.id
