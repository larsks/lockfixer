import json
import logging
import os_client_config

nova = os_client_config.make_client('compute')
all_vms = [vm.to_dict() for vm in nova.servers.list(search_opts=dict(all_tenants=True))]
computes = {}
problem_state = ['CLEAN', 'AFFECTED', 'UNKNOWN']

for vm in all_vms:
    vm_info = nova.servers.get(vm['id'])
    host = getattr(vm_info, 'OS-EXT-SRV-ATTR:host')

    try:
        console = nova.servers.get_console_output(vm['id'])
        if 'blk_update_request: I/O error' in console:
            has_problem=1
            print('%s: VM %s with ID %s is AFFECTED' % (host, vm['name'], vm['id']))
        else:
            has_problem=0

    except Exception as e:
        logging.error(e)
        has_problem=2

    print('{} {} {} {}'.format(host, vm['id'], vm['status'], problem_state[has_problem]))
