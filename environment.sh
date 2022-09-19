#!/bin/bash
BACKUP_LABEL=${BACKUP_LABEL:-"tech.embrio.backup"}
BACKUP_DIR=${BACKUP_DIR:-"$(pwd)/volumes"}
GS_BUCKET_NAME=${GS_BUCKET_NAME:-""}
GS_SA_KEY=${GS_SA_KEY:-""}