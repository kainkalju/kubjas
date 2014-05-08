#!/bin/bash
MYPID=$(service kubjas status | awk '{print $4}')
if [ $MYPID ]; then
  kill -USR1 $MYPID
fi
