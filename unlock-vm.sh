#!/bin/bash
#
# USAGE: unlock-vm.sh UUID

: ${POOL_EPHEMERAL:=production-ephemeral-vms}
: ${POOL_VOLUME:=production-cinder-volumes}

CEPH_ARGS="--keyring /etc/ceph/client.production-openstack.key --id production-openstack"
export CEPH_ARGS

if [[ $1 = --off ]]; then
    POWERON=0
    shift
else
    POWERON=1
fi

vmuuid=$1

##
## Make sure the server is stopped.
##

echo "stopping server ${vmuuid}..."
openstack server stop $vmuuid
while :; do
    status=$(openstack server show $vmuuid -f value -c status)
    if [[ $status = SHUTOFF ]]; then
        break
    fi
done
echo "server is stopped"

##
## Generate a list of RBD device names to unlock
##

rbdnames=("${POOL_EPHEMERAL}/${vmuuid}_disk")

echo "inspecting server..."
volume_ids=(
    $(openstack server show $vmuuid -f value -c volumes_attached | cut -f2 -d"'")
)
echo "${volume_ids[@]}"

for uuid in "${volume_ids[@]}"; do
    rbdnames+=("${POOL_VOLUME}/volume-${uuid}")
done

##
## Remove all locks on RBD devices
##

for rbdname in "${rbdnames[@]}"; do
    # Check if the device exists (we're just guessing at the names, really,
    # so e.g. for vms booting from volumes the device for the ephemeral
    # disk won't exist)
    if ! rbd info $rbdname > /dev/null 2>&1; then
        echo "rbd device $rbdname does not exist (skipping)"
        continue
    fi

    while :; do
        if ! rbd lock list $rbdname | grep -q '^client'; then
            echo "all locks removed from $rbdname"
            break
        else
            set -- $(rbd lock list $rbdname | grep '^client' | head -1)
            echo "removing lock $3 from $rbdname"
            rbd lock remove $rbdname "auto $3" $1
        fi
    done
done

# Boot the server unless --off was specified on the command line.
if [[ $POWERON = 1 ]]; then
    echo "starting server $vmuuid..."
    openstack server start $vmuuid
    while :; do
        status=$(openstack server show $vmuuid -f value -c status)
        if [[ $status = ACTIVE ]]; then
            break
        fi
    done
    echo "server is started"
fi
