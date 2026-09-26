# Демо: образ

[Оглавление](README.md#шаги)

## 1. Старый способ: ISO, пустой диск, установщик

### 1.1 [ISO] ISO в кластер

Установочный ISO Ubuntu уровня кластера: с него ставится ВМ в 1.2 и собирает образ packer в шаге 2

```bash
cat 01-image/cvi-iso.yaml
```

Загрузка ISO в кластер

```bash
d8 k apply -f 01-image/cvi-iso.yaml
d8 k wait --for=jsonpath='{.status.phase}'=Ready cvi/demo-ubuntu-26-04-iso --timeout=15m
```

### 1.2 [ISO] Установка с ISO

Описание ВМ: ISO первым, пустой диск вторым

```bash
cat 01-image/iso/vm.yaml
```

Создание ВМ и пустого диска в проекте demo-webinar

```bash
d8 k apply -k 01-image/iso
```

Запуск ВМ: у неё ручной режим запуска, после создания она выключена

```bash
d8 k -n demo-webinar wait --for=jsonpath='{.status.phase}'=Stopped vm/demo-iso --timeout=2m
d8 v start -y -n demo-webinar demo-iso
d8 k -n demo-webinar wait --for=jsonpath='{.status.phase}'=Running vm/demo-iso --timeout=5m
```

Что создалось

```bash
d8 k get cvi demo-ubuntu-26-04-iso
d8 k -n demo-webinar get vd/demo-iso-root vm/demo-iso
```

Экран установщика

```bash
d8 v vnc -n demo-webinar demo-iso
```

### 1.3 [ISO] Удаление окружения

Удаление ВМ и диска, ISO остаётся для packer

```bash
d8 k delete -k 01-image/iso --ignore-not-found
```

## 2. Тот же образ как код: packer собирает его внутри кластера

### 2.1 [Packer] Запуск сборки

Сборка образа проекта `demo-ubuntu-26-04-packer`: packer ставит систему с ISO из шага 1.1 и снимает образ, из него создаются диски Linux-ВМ демо. Если образ уже есть, сборка упадёт: плагин его не перезаписывает, первая команда показывает, есть ли он

```bash
d8 k -n demo-webinar get vi demo-ubuntu-26-04-packer
packer init 01-image/packer
packer build 01-image/packer
```

### 2.2 [Packer] Шаблон сборки

Шаблон сборки: ISO из шага 1, маленький диск, ответы установщику, скрипты подготовки

```bash
cat 01-image/packer/ubuntu.pkr.hcl
```

Ответы установщику: минимальная система, разметка под BIOS и EFI, без swap

```bash
cat 01-image/packer/autoinstall.yaml
```

Что делают скрипты: агент, hardening, облачная обвязка, проверка образа, очистка перед клонированием

```bash
ls 01-image/packer/scripts
cat 01-image/packer/scripts/80-verify.sh
```

### 2.3 [Packer] Готовый образ

Собранный образ

```bash
d8 k -n demo-webinar wait --for=jsonpath='{.status.phase}'=Ready vi/demo-ubuntu-26-04-packer --timeout=10m
d8 k -n demo-webinar get vi demo-ubuntu-26-04-packer
```

## 3. Где живут образы

Образы на весь кластер

```bash
d8 k get cvi
```

Образы проекта

```bash
d8 k -n demo-webinar get vi
```

Размер образа

```bash
d8 k -n demo-webinar get vi demo-ubuntu-26-04-packer -o jsonpath='{.status.size}{"\n"}'
```

## 4. cloud-init лежит рядом с ВМ

cloud-init в репозитории

```bash
cat 02-infra/kustomize/base/cfg/cloudinit.yaml
```

## 5. В Windows это называется sysprep, и это то же самое

### 5.1 [sysprep] Сборка золотого образа

Windows ставится с ISO сама, вручную только Enter в VNC на старте установки. Если образ уже собран (`d8 k -n demo-webinar get vi demo-windows-server-2022-sysprep` показывает `Ready`), подшаг пропустить

Установочные носители

```bash
d8 k apply -f 01-image/windows/golden/cvi-images.yaml
d8 k wait --for=jsonpath='{.status.phase}'=Ready cvi/demo-windows-server-2022-iso cvi/demo-virtio-win-0-1-302-iso --timeout=20m
```

Создание сборочной ВМ. Следующий блок запускать сразу: приглашение загрузки с CD быстро исчезает

```bash
d8 k apply -k 01-image/windows/golden
```

Нажать Enter на "Press any key to boot from CD or DVD". Приглашение быстро исчезает, VNC часто подключается позже. Тогда прошивка открывает UEFI shell: в нём набрать `fs0:\efi\boot\bootx64.efi` и сразу жать Enter

```bash
d8 v vnc -n demo-webinar demo-win-build
```

Ожидание конца установки

```bash
d8 k -n demo-webinar wait --for=jsonpath='{.status.phase}'=Stopped vm/demo-win-build --timeout=30m
```

Снимок диска после sysprep. С диска, подключённого к ВМ, образ не снять, поэтому образ делается через снимок. Снимать только после остановки ВМ: снимок фиксирует диск в момент создания

```bash
d8 k apply -f 01-image/windows/golden/snapshot.yaml
d8 k -n demo-webinar wait --for=jsonpath='{.status.phase}'=Ready vdsnapshot/demo-windows-server-2022-sysprep --timeout=10m
```

Диск из снимка и золотой образ с этого диска, оба в одном файле

```bash
d8 k apply -f 01-image/windows/golden/golden-image.yaml
d8 k -n demo-webinar wait --for=jsonpath='{.status.phase}'=Ready vd/demo-windows-server-2022-sysprep --timeout=10m
d8 k -n demo-webinar wait --for=jsonpath='{.status.phase}'=Ready vi/demo-windows-server-2022-sysprep --timeout=20m
```

### 5.2 [sysprep] Файл ответов и золотой образ

Файл ответов Windows

```bash
cat 01-image/windows/clone/cfg/unattend.xml
```

Цепочка золотого образа: сборочная ВМ, её диск, снимок, диск из снимка, образ. В спецификации образа видно, с какого диска он снят

```bash
d8 k -n demo-webinar get vi demo-windows-server-2022-sysprep
d8 k -n demo-webinar get vi demo-windows-server-2022-sysprep -o jsonpath='{.spec.dataSource.objectRef}{"\n"}'
d8 k -n demo-webinar get vm/demo-win-build vd/demo-win-build-root vdsnapshot/demo-windows-server-2022-sysprep vd/demo-windows-server-2022-sysprep --ignore-not-found
```

### 5.3 [sysprep] ВМ из золотого образа

Создание ВМ из золотого образа с SSH-ключом

```bash
cp keys/demo_ed25519.pub 01-image/windows/clone/cfg/authorized_keys
d8 k apply -k 01-image/windows/clone
```

Запуск ВМ, если она остановлена (шаг 5.4)

```bash
d8 v start -y -n demo-webinar demo-win
```

Ожидание гостевого агента

```bash
d8 k -n demo-webinar wait --for=condition=AgentReady vm/demo-win --timeout=15m
```

Вход по SSH-ключу. Агент отвечает раньше, чем Windows запускает OpenSSH: при `Connection refused` подождать и повторить

```bash
d8 v ssh -n demo-webinar demo-win --username cloud --identity-file keys/demo_ed25519 \
  --ssh-args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes'
```

### 5.4 [sysprep] Остановка ВМ

Остановить ВМ, чтобы она не занимала ресурсы. Удаляется она при уборке

```bash
d8 v stop -n demo-webinar demo-win
```
