#!/bin/bash

set -ex

CLUSTER1=cluster1
CLUSTER2=cluster2
POOL=mirror
IMAGE=image-
MOUNT=/mnt/test
WORKLOAD_TIMEOUT=5m
MIRROR_POOL_MODE=image
MIRROR_IMAGE_MODE=snapshot

. $(dirname $0)/rbd_mirror_helpers.sh

launch_manual_msnaps() {
  local cluster=$1
  local pool=$2
  local image=$3

  for i in {1..20}; do
    mirror_image_snapshot $cluster $pool $image
    sleep 3s;
  done

  sleep 10s;
}

run_bench() {
  local mountpt=$1
  local timeout=$2

  KERNEL_TAR_URL="https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.14.280.tar.gz"
  sudo wget $KERNEL_TAR_URL -O $mountpt/kernel.tar.gz
  sudo timeout $timeout bash -c "tar xvfz $mountpt/kernel.tar.gz -C $mountpt | pv -L 1k --timer &> /dev/null" || true
}

wait_for_demote_snap () {
  local cluster=$1
  local pool=$2
  local image=$3

  while [ true ] ;
  do
    RET=`rbd --cluster $cluster snap ls --all $pool/$image | grep non_primary | grep demote | grep -v "%" ||true`
    if [ "$RET" != "" ]; then
      echo demoted snapshot received, continuing
      sleep 10s #wait a bit for it to propagate
      break
    fi

    echo waiting for demoted snapshot...
    sleep 5s
  done
}

compare_images() {
    j=$1
    sudo umount ${MOUNT}${j}

    unmap ${CLUSTER1} ${POOL} ${IMAGE}${j}
    demote_image ${CLUSTER1} ${POOL} ${IMAGE}${j}

    DEMOTE=$(rbd --cluster ${CLUSTER1} snap ls --all ${POOL}/${IMAGE}${j} --debug-rbd 0 | grep mirror\.primary | grep demoted | awk '{print $2}')
    BDEV=$(map ${CLUSTER1} ${POOL} ${IMAGE}${j} ${DEMOTE})
    DEMOTE_MD5=$(sudo dd if=${BDEV} bs=4M | md5sum | awk '{print $1}')
    unmap ${CLUSTER1} ${POOL} ${IMAGE}${j} ${DEMOTE}
    promote_image ${CLUSTER2} ${POOL} ${IMAGE}${j}

    PROMOTE=$(rbd --cluster ${CLUSTER2} snap ls --all ${POOL}/${IMAGE}${j} --debug-rbd 0 | grep mirror\.primary | awk '{print $2}')
    BDEV=$(map ${CLUSTER2} ${POOL} ${IMAGE}${j} ${PROMOTE})
    PROMOTE_MD5=$(sudo dd if=${BDEV} bs=4M | md5sum | awk '{print $1}')
  
    unmap ${CLUSTER2} ${POOL} ${IMAGE}${j} ${PROMOTE}
    if [ "${DEMOTE_MD5}" == "${PROMOTE_MD5}" ]; then
      echo "md5sum comparison for image: ${IMAGE}${j} passed!"
    else
      echo "md5sum comparison for image: ${IMAGE}${j} failed!"
    fi
}

setup

start_mirrors ${CLUSTER1}
start_mirrors ${CLUSTER2}

for i in {1..1};
do
  for j in {1..10};
  do
    create_image ${CLUSTER1} ${POOL} ${IMAGE}${j} 10G
    enable_mirror ${CLUSTER1} ${POOL} ${IMAGE}${j} 
  
    #initial setup
    BDEV=$(map ${CLUSTER1} ${POOL} ${IMAGE}${j})
    sudo mkfs.ext4 ${BDEV}

    sudo mkdir -p ${MOUNT}${j}
    sudo mount ${BDEV} ${MOUNT}${j}
    launch_manual_msnaps ${CLUSTER1} ${POOL} ${IMAGE}${j} &
    run_bench ${MOUNT}${j} ${WORKLOAD_TIMEOUT} &
  done
  wait

  for j in {1..10};
  do
    compare_images $j &
  done
  wait
done
