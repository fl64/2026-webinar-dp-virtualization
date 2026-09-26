# Демо: жизненный цикл

[Оглавление](README.md#шаги)

## 10. Пул виртуальных машин

### 10.1 [Пул] Создание пула

Шаблон пула и HPA

```bash
cat 03-lifecycle/pool.yaml
```

Создание пула в проекте `demo-webinar`, диски реплик из образа проекта

```bash
d8 k apply -f 03-lifecycle/pool.yaml
```

Ожидание трёх реплик и гостевых агентов на них: пул отчитывается о готовности раньше, чем загрузится гостевая ОС, а ansible нужна загруженная ОС

```bash
d8 k -n demo-webinar wait --for=jsonpath='{.status.readyReplicas}'=3 vmpool/demo-pool --timeout=15m
d8 k -n demo-webinar wait --for=condition=AgentReady vm -l vmpool.virtualization.deckhouse.io/pool=demo-pool --timeout=10m
d8 k -n demo-webinar get vmpool/demo-pool
d8 k -n demo-webinar get vm -l vmpool.virtualization.deckhouse.io/pool=demo-pool
```

Один Service на все реплики: каждый ответ несёт имя ВМ, видно ротацию

```bash
d8 k -n demo-webinar run pool-curl --rm -i --restart=Never --image=curlimages/curl:8.10.1 --overrides='{"spec":{"containers":[{"name":"pool-curl","image":"curlimages/curl:8.10.1","command":["sh","-c","sleep 3; for i in $(seq 1 12); do curl -s http://demo-pool/; done"],"resources":{"requests":{"cpu":"10m","memory":"16Mi"},"limits":{"cpu":"100m","memory":"64Mi"}},"securityContext":{"allowPrivilegeEscalation":false,"runAsNonRoot":true,"runAsUser":100,"capabilities":{"drop":["ALL"]},"seccompProfile":{"type":"RuntimeDefault"}}}]}}' | sort | uniq -c
```

## 11. Голый ansible, inventory из кластера

Плейбук: обновления и запись в /etc/motd

```bash
cat 03-lifecycle/playbooks/update.yml
```

Inventory из кластера: все ВМ проекта, группы по аннотации `ansible.deckhouse.io/groups`: ВМ демо в группе `demo`, реплики пула ещё и в `pool`

```bash
d8 v ansible-inventory -n demo-webinar -o ini
```

Плейбук на все ВМ демо с рабочей станции: `--limit demo`, `demo-iso` и `demo-win` в группу не входят. Инвентарь, пользователь, ключ и sudo заданы в `ansible.cfg`

```bash
export ANSIBLE_CONFIG=03-lifecycle/local/ansible.cfg
ansible-playbook 03-lifecycle/playbooks/update.yml --limit demo -e 'updated_by="ansible from a workstation"'
```

Что видит админ при входе на ВМ

```bash
d8 v ssh -n demo-webinar $(d8 k -n demo-webinar get vm -l vmpool.virtualization.deckhouse.io/pool=demo-pool -o jsonpath='{.items[0].metadata.name}') \
  --username cloud --identity-file keys/demo_ed25519 -c 'cat /etc/motd' \
  --ssh-args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -o LogLevel=ERROR'
```

## 12. Запуск ansible как ресурс кластера

### 12.1 [AnsibleRun] Запуск

Запуск ansible ресурсом `AnsibleRun`: плейбук из git, на каких ВМ, с каким ключом и чем подписать запуск в `/etc/motd`

```bash
cat 03-lifecycle/module/runs/site.yaml
```

[Плейбук 03-lifecycle/playbooks/update.yml на GitHub](https://github.com/fl64/2026-webinar-dp-virtualization/blob/main/03-lifecycle/playbooks/update.yml)

SSH-доступ раннера к ВМ: тот же ключ демо. Вход по паролю образ запрещает

```bash
d8 k -n demo-webinar create secret generic demo-pool --type=kubernetes.io/ssh-auth \
  --from-file=ssh-privatekey=keys/demo_ed25519 --from-literal=username=cloud \
  --dry-run=client -o yaml | d8 k apply -f -
```

Запуск

```bash
d8 k apply -f 03-lifecycle/module/runs/site.yaml
```

Ожидание итога запуска

```bash
d8 k -n demo-webinar wait --for=jsonpath='{.status.phase}'=PlaybookSucceeded ansiblerun/demo-pool-site --timeout=15m
d8 k -n demo-webinar get ansibleruns
```

Итог по каждой ВМ

```bash
d8 k -n demo-webinar get ansiblerun demo-pool-site \
  -o jsonpath='{range .status.hosts[*]}{@}{"\n"}{end}'
```

Что запуск записал в `/etc/motd`

```bash
d8 v ssh -n demo-webinar $(d8 k -n demo-webinar get vm -l vmpool.virtualization.deckhouse.io/pool=demo-pool -o jsonpath='{.items[0].metadata.name}') \
  --username cloud --identity-file keys/demo_ed25519 -c 'cat /etc/motd' \
  --ssh-args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -o LogLevel=ERROR'
```

### 12.2 [AnsibleRun] Запуск по расписанию

Тот же плейбук каждую ночь по расписанию

```bash
d8 k apply -f 03-lifecycle/module/runs/schedule.yaml
```

Раз в час проверка без установки: у каких ВМ есть обновления (`changed=1` в итоге запуска)

```bash
d8 k apply -f 03-lifecycle/module/runs/check-schedule.yaml
```

### 12.3 [AnsibleRun] Быстрый запуск без пакетов

`update.yml` зависит от зеркала пакетов и ждёт, пока на свежей ВМ закончит `unattended-upgrades`. Для быстрой проверки есть `stamp.yml`: он только переписывает `/etc/motd`

```bash
cat 03-lifecycle/playbooks/stamp.yml
ansible-playbook 03-lifecycle/playbooks/stamp.yml --limit demo
```

Тот же плейбук запуском и расписанием раз в минуту. Расписание раз в минуту удалить, когда оно больше не нужно

```bash
d8 k apply -f 03-lifecycle/module/runs/stamp.yaml
d8 k apply -f 03-lifecycle/module/runs/stamp-schedule.yaml
d8 k -n demo-webinar delete ansiblerunschedule demo-stamp-every-minute
```

Spec запуска неизменяем: чтобы прогнать `demo-stamp` ещё раз, удалить его и создать заново

```bash
d8 k -n demo-webinar delete ansiblerun demo-stamp
d8 k apply -f 03-lifecycle/module/runs/stamp.yaml
```

## 13. Нагрузка двигает пул

### 13.1 [HPA] Нагрузка

Плейбук нагрузки

```bash
cat 03-lifecycle/module/runs/stress.yaml
```

Запуск нагрузки

```bash
d8 k apply -f 03-lifecycle/module/runs/stress.yaml
```

Пул под нагрузкой

```bash
watch -n5 'd8 k -n demo-webinar get hpa/demo-pool vmpool/demo-pool; d8 k -n demo-webinar get vm -l vmpool.virtualization.deckhouse.io/pool=demo-pool'
```

### 13.2 [Пул и ansible] Удаление окружения шагов 10–13

Запуски, расписания и SSH-доступ раннера

```bash
d8 k delete -f 03-lifecycle/module/runs/ --ignore-not-found
d8 k -n demo-webinar delete secret demo-pool --ignore-not-found
```

Удаление пула вместе с ВМ, дисками и HPA

```bash
d8 k delete -f 03-lifecycle/pool.yaml --ignore-not-found
```
