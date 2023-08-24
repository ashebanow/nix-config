#!/usr/bin/env bash
scp -A -p -r github_rsa github_rsa.pub id_ed25519 config \
  ashebanow@10.40.0.172:/home/ashebanow/.ssh/