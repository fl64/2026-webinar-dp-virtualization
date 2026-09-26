#!/bin/sh
# Динамический инвентарь для обычного ansible: пул ВМ из DVP, без промежуточных файлов.
#   ansible -i 03-lifecycle/local/inventory.sh pool -m ping -u cloud
# ansible сам вызывает скрипт с --list / --host <хост>, поэтому "$@" прокидываем как есть.
# Namespace можно переопределить: ANSIBLE_VM_NS=demo-helm ansible -i ... all -m ping
exec d8 v ansible-inventory -n "${ANSIBLE_VM_NS:-demo-webinar}" "$@"
