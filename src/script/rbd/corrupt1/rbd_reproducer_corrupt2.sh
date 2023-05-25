#!/bin/bash

set -ex

SCRIPT_DIR=../src/script/rbd/corrupt1/ 

setup () {
  local cluster1=$1
  local cluster2=$2
  local pool=$3
  local image=$4
  ##removed, see launch_manual_msnaps  local interval=$5

  #setup environment
  ${SCRIPT_DIR}/mirrorenv.sh start

  #create image
  ./bin/rbd --cluster $cluster1 create $image --size 10G --pool $pool  --image-feature layering,exclusive-lock,object-map,fast-diff 

  #setup snapshot mirroring
  ./bin/rbd --cluster $cluster1 mirror image enable $pool/$image snapshot

  #set schedule for image
#  ./bin/rbd mirror snapshot schedule add --pool $pool --image $image $interval  --cluster $cluster1
}

map () {
  local cluster=$1
  local pool=$2
  local image=$3

  sudo ./bin/rbd --cluster $cluster device map $pool/$image
}

format () {
  local bdev=$1
  
  sudo mkfs.ext4 $bdev
}

mount() {
  local bdev=$1
  local mountpt=$2
  local user=$3

  sudo mkdir -p $mountpt
  sudo mount $bdev $mountpt

  sudo chown $user $mountpt
}

launch_manual_msnaps() {
  local cluster=$1
  local pool=$2
  local image=$3

  for i in {1..40}; do
    ./bin/rbd --cluster $cluster mirror image snapshot $pool/$image --debug-rbd 0;
    sleep 3s;
  done

  sleep 10s;
  killall timeout

}

run_bench() {
  local timeout=$1

  timeout $timeout sh ${SCRIPT_DIR}/kernel_untar.sh &> /dev/null || true
}

umount () {
  local mountpt=$1
  
  sudo umount $mountpt
}

unmap () {
  local cluster=$1
  local pool=$2
  local image=$3
  
  sudo ./bin/rbd --cluster $cluster device unmap $pool/$image
}

promote () {
  local cluster=$1
  local pool=$2
  local image=$3

  sudo ./bin/rbd --cluster $cluster mirror image promote $pool/$image
}

demote () {
  local cluster=$1
  local pool=$2
  local image=$3

  sudo ./bin/rbd --cluster $cluster mirror image demote $pool/$image
}

wait_for_demote_snap () {
  local cluster=$1
  local pool=$2
  local image=$3

  while [ true ] ;
  do
    RET=`./bin/rbd --cluster $cluster snap ls --all $pool/$image | grep non_primary | grep demote | grep -v "%" ||true`
    if [ "$RET" != "" ]; then
      echo demoted snapshot received, continuing
      sleep 10s #wait a bit for it to propagate
      break
    fi

    echo waiting for demoted snapshot...
    sleep 5s
  done
}

fsck_check () {
  local bdev=$1

  sudo fsck -fn $bdev
}

CLUSTER1=site-a
CLUSTER2=site-b
POOL=pool1
IMAGE=image1
MOUNT=/mnt/test
PRIMARY=${CLUSTER1}
SECONDARY=${CLUSTER2}
MIRROR_INTERVAL=1m
WORKLOAD_TIMEOUT=5m
MY_USER=$(whoami)

setup ${PRIMARY} ${SECONDARY} ${POOL} ${IMAGE} ${MIRROR_INTERVAL}

#initial setup
BDEV=$(map ${PRIMARY} ${POOL} ${IMAGE})
format ${BDEV}

  mount ${BDEV} ${MOUNT} ${MY_USER}

  launch_manual_msnaps ${PRIMARY} ${POOL} ${IMAGE} &
  run_bench ${WORKLOAD_TIMEOUT}
  sync
  umount ${MOUNT}
  unmap ${PRIMARY} ${POOL} ${IMAGE}
  demote ${PRIMARY} ${POOL} ${IMAGE}
  wait_for_demote_snap ${SECONDARY} ${POOL} ${IMAGE}

  promote ${SECONDARY} ${POOL} ${IMAGE}

  TEMP=${PRIMARY}
  PRIMARY=${SECONDARY}
  SECONDARY=${TEMP}

  BDEV=$(map ${PRIMARY} ${POOL} ${IMAGE})
  fsck_check ${BDEV}
  unmap ${PRIMARY} ${POOL} ${IMAGE}
  
  sleep 5s

#this wont be reached
#${SCRIPT_DIR}/mirrorenv.sh stop
