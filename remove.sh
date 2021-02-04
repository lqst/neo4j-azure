#!/bin/bash
if [ -z $1 ] ; then
  echo "Usage: call me with resource group name to delete everything in the resource group"
  exit 1
fi
STACK_NAME=$1
if [ -f "$STACK_NAME.json" ] ; then
   rm -f "$STACK_NAME.json"
fi
az group delete -n "$STACK_NAME" --no-wait --yes
exit $?