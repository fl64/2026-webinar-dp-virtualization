# Виртуальные машины как обычные ресурсы Kubernetes

Демо вебинара по DP Virtualization. Одно приложение (ВМ с nginx за ingress с сертификатом) разворачивается четырьмя способами: `d8 k` (одним файлом и через kustomize), terraform, Helm-аддон и Argo CD. Плюс обслуживание пула ВМ через ansible и масштабирование пула обычным `HorizontalPodAutoscaler`.

Пошаговый сценарий: [Шаги](#шаги).

## Что нужно

**В кластере** (проверка: `d8 k get module <имя>`):

| Что | Зачем |
| --- | --- |
| модули `virtualization`, `multitenancy-manager` | ВМ и проекты, в которых они живут |
| модули `operator-argo`, `operator-helm`, `ansible` | GitOps, Helm-аддон, обслуживание пула. Сам Argo CD с проверками здоровья ресурсов DP Virtualization ставит шаг 0 (`00-prep/argocd.yaml`), если своего в кластере нет |
| `VirtualMachineClass` `generic` | класс ВМ во всех манифестах |
| StorageClass для блочных устройств | диски ВМ |
| ingress-nginx, cert-manager с ClusterIssuer `letsencrypt` | публикация страниц с TLS |
| DNS `*.<домен>` на ingress кластера | адреса вида `demo-kustomize-dev.<домен>` |
| права администратора кластера | демо создаёт ресурсы уровня кластера: `Project`, `ClusterVirtualImage`, `HelmClusterAddon` и его репозиторий, Argo CD в `argocd` |

**Снаружи:**

- публичный форк этой репы на GitHub: Argo и модуль ansible читают его без учётных данных;
- GitHub Pages на ветке `gh-pages`: оттуда аддон берёт Helm-чарт;
- локально: `git`, `helm`, `ssh-keygen`, `d8`, `terraform`, `packer`, `ansible`, `remote-viewer` (его открывает `d8 v vnc`);
- kubeconfig в `~/.kube/config`: провайдер terraform читает только этот путь (`02-infra/terraform/provider.tf`);
- плагин packer `deckhouse-virtualization`: ставится в шаге 0.7 [00-prep.md](00-prep.md).

## Шаги

Блоки выполняются по порядку из корня репы. Подшаг «Удаление окружения» в конце шага убирает то, что шаг создал.

| Шаг | Что в шаге | Файл |
| --- | --- | --- |
| 0 | Подготовка: домен и форк, SSH-ключ, чарт, общий проект, Argo CD, плагин packer | [00-prep.md](00-prep.md#0-подготовка) |
| 1 | Старый способ: ISO, пустой диск, установщик | [01-image.md](01-image.md#1-старый-способ-iso-пустой-диск-установщик) |
| 2 | Тот же образ как код: packer собирает его внутри кластера | [01-image.md](01-image.md#2-тот-же-образ-как-код-packer-собирает-его-внутри-кластера) |
| 3 | Где живут образы | [01-image.md](01-image.md#3-где-живут-образы) |
| 4 | cloud-init лежит рядом с ВМ | [01-image.md](01-image.md#4-cloud-init-лежит-рядом-с-вм) |
| 5 | В Windows это называется sysprep, и это то же самое | [01-image.md](01-image.md#5-в-windows-это-называется-sysprep-и-это-то-же-самое) |
| 6 | d8 k и kustomize | [02-infra.md](02-infra.md#6-d8-k-и-kustomize) |
| 7 | Terraform, ровно как раньше | [02-infra.md](02-infra.md#7-terraform-ровно-как-раньше) |
| 8 | Helm, через operator-helm | [02-infra.md](02-infra.md#8-helm-через-operator-helm) |
| 9 | Argo CD: выкат, удаление ВМ, изменения через git | [02-infra.md](02-infra.md#9-argo-cd) |
| 10 | Пул виртуальных машин | [03-lifecycle.md](03-lifecycle.md#10-пул-виртуальных-машин) |
| 11 | Голый ansible, inventory из кластера | [03-lifecycle.md](03-lifecycle.md#11-голый-ansible-inventory-из-кластера) |
| 12 | Запуск ansible как ресурс кластера | [03-lifecycle.md](03-lifecycle.md#12-запуск-ansible-как-ресурс-кластера) |
| 13 | Нагрузка двигает пул | [03-lifecycle.md](03-lifecycle.md#13-нагрузка-двигает-пул) |
| | Уборка | [04-cleanup.md](04-cleanup.md) |

## Что поменять под свой кластер

Манифесты написаны под кластер, на котором готовилось демо. Значения, которые отличаются от кластера к кластеру:

| Значение в репе | Что сделать |
| --- | --- |
| домен `d8-virtualization.ru` | заменить на свой, шаг 0.1 |
| адрес репы `fl64/2026-webinar-dp-virtualization` и её GitHub Pages | заменить на свой форк, шаг 0.2 |
| SSH-ключ демо | создать свой и подставить в манифесты, шаг 0.3 |
| класс ВМ `generic` | создать такой `VirtualMachineClass` или заменить имя в манифестах ВМ, `02-infra/terraform/terraform.tfvars`, `01-image/packer/ubuntu.pkr.hcl`, `02-infra/helm/chart/values.yaml` |
| ClusterIssuer `letsencrypt` | заменить в `expose.yaml` и `demo-kubectl.yaml`, `02-infra/terraform/vars.tf`, values чарта, `00-prep/argocd.yaml` |
| ingress-класс `nginx` | заменить в тех же манифестах публикации, `vars.tf` и values чарта |
| namespace ingress-контроллера `d8-ingress-nginx` | заменить в NetworkPolicy: она пускает к ВМ трафик только из этого namespace |
| Argo CD в namespace `argocd` | если свой Argo CD живёт в другом namespace, заменить в `02-infra/argocd/app.yaml` и `appproject.yaml` |

## Раскладка

```
00-prep/              шаг 0
  project.yaml        общий проект demo-webinar с квотой
  argocd.yaml         Argo CD с проверками здоровья ресурсов DP Virtualization
01-image/             шаги 1–5
  cvi-iso.yaml        установочный ISO Ubuntu уровня кластера
  iso/                ВМ с установкой с ISO на пустой диск
  packer/             сборка образа проекта demo-ubuntu-26-04-packer
  windows/golden/     сборка золотого образа Windows
  windows/clone/      ВМ из золотого образа через sysprep
02-infra/             шаги 6–9
  kubectl/            ВМ одним файлом
  kustomize/          база и оверлеи dev, prod
  terraform/          ВМ через провайдер kubernetes
  helm/               HelmClusterAddon, репозиторий и исходник чарта
  argocd/             AppProject и Application; vm/ синкает Argo
03-lifecycle/         шаги 10–13
  pool.yaml           пул ВМ с HPA
  playbooks/          плейбуки ansible
  module/             запуски и расписания модуля ansible
  local/              запуск ansible с рабочей станции
keys/                 SSH-пара демо, создаётся в шаге 0, в git не лежит
```
