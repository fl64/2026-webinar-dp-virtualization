# Демо: инфраструктура

[Оглавление](README.md#шаги)

## 6. d8 k и kustomize

### 6.1 [d8 k] Одним файлом

Cloud-init, диск, ВМ и публикация в одном файле

```bash
cat 02-infra/kubectl/demo-kubectl.yaml
```

Создание ВМ, диска и окружения в проекте demo-webinar, диск из образа проекта

```bash
d8 k apply -f 02-infra/kubectl/demo-kubectl.yaml
```

Пока диск создаётся из образа, ВМ в `Pending`: условия в статусе показывают, чего она ждёт

```bash
d8 k -n demo-webinar get vm demo-kubectl
d8 k -n demo-webinar get vm demo-kubectl -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
```

Ожидание гостевого агента

```bash
d8 k -n demo-webinar wait --for=condition=AgentReady vm/demo-kubectl --timeout=10m
```

Что создалось

```bash
d8 k -n demo-webinar get vd/demo-kubectl-root vm/demo-kubectl
```

Ответ страницы

```bash
curl -sf --retry 30 --retry-delay 5 --retry-all-errors https://demo-kubectl.d8-virtualization.ru | grep h1
```

[Страница demo-kubectl в браузере](https://demo-kubectl.d8-virtualization.ru)

### 6.2 [kustomize] База и два оверлея

База и два оверлея поверх неё: две ВМ `dev` и `prod` из одних файлов, cloud-init отдельным файлом, Secret собирает kustomize

Описание ВМ в базе

```bash
cat 02-infra/kustomize/base/vm.yaml
```

Оверлей prod: суффикс имён, метка ВМ, адрес и размер машины

```bash
cat 02-infra/kustomize/overlays/prod/kustomization.yaml
```

Чем отличаются dev и prod после сборки

```bash
diff <(d8 k kustomize 02-infra/kustomize/overlays/dev) <(d8 k kustomize 02-infra/kustomize/overlays/prod)
```

kustomize не знает полей ресурсов DP Virtualization. Этот файл показывает ему, где в ВМ ссылки на диск и Secret, чтобы суффикс оверлея добавлялся и к ним

```bash
cat 02-infra/kustomize/base/transformer.yaml
```

Создание двух ВМ с дисками и окружением в проекте demo-webinar, диски из образа проекта

```bash
d8 k apply -k 02-infra/kustomize/overlays/dev
d8 k apply -k 02-infra/kustomize/overlays/prod
```

Ожидание гостевых агентов

```bash
d8 k -n demo-webinar wait --for=condition=AgentReady vm/demo-kustomize-dev vm/demo-kustomize-prod --timeout=10m
```

Что создалось

```bash
d8 k -n demo-webinar get vd/demo-kustomize-root-dev vd/demo-kustomize-root-prod vm/demo-kustomize-dev vm/demo-kustomize-prod
```

cloud-init из шага 4 в Secret'е ВМ: kustomize собрал его из файла

```bash
d8 k -n demo-webinar get secret demo-kustomize-dev -o jsonpath='{.data.userdata}' | base64 -d | head -20
```

Ответ страниц: каждая ВМ называет себя

```bash
curl -sf --retry 30 --retry-delay 5 --retry-all-errors https://demo-kustomize-dev.d8-virtualization.ru | grep h1
curl -sf --retry 30 --retry-delay 5 --retry-all-errors https://demo-kustomize-prod.d8-virtualization.ru | grep h1
```

[Страница demo-kustomize-prod в браузере](https://demo-kustomize-prod.d8-virtualization.ru)

### 6.3 [d8 k и kustomize] Удаление окружения

Удаление всех трёх ВМ с дисками и публикацией

```bash
d8 k delete -f 02-infra/kubectl/demo-kubectl.yaml --ignore-not-found
d8 k delete -k 02-infra/kustomize/overlays/dev --ignore-not-found
d8 k delete -k 02-infra/kustomize/overlays/prod --ignore-not-found
```

## 7. Terraform, ровно как раньше

### 7.1 [Terraform] Создание ВМ

Пример описания ВМ в виде спецификации terraform

```bash
cat 02-infra/terraform/vm.tf
```

Инициализация

```bash
terraform -chdir=02-infra/terraform init -input=false
```

Что terraform создаст

```bash
terraform -chdir=02-infra/terraform plan
```

Создание ВМ, диска и окружения в проекте demo-webinar

```bash
terraform -chdir=02-infra/terraform apply -auto-approve
```

Адрес страницы из output

```bash
terraform -chdir=02-infra/terraform output vm_url
```

Ответ страницы

```bash
curl -sf --retry 30 --retry-delay 5 --retry-all-errors https://demo-terraform.d8-virtualization.ru | grep h1
```

[Страница demo-terraform в браузере](https://demo-terraform.d8-virtualization.ru)

### 7.2 [Terraform] Удаление окружения

Удаление всего, что создал terraform

```bash
terraform -chdir=02-infra/terraform destroy -auto-approve
```

## 8. Helm, через operator-helm

### 8.1 [Helm] Создание ВМ аддоном

Аддон: чарт, версия, values

```bash
cat 02-infra/helm/addon.yaml
```

Что чарт ставит с этими values: NetworkPolicy, Service, Ingress, Certificate, VirtualDisk, VirtualMachine. Кластер для рендера не нужен

```bash
helm template demo-helm 02-infra/helm/chart -n demo-webinar \
  --set name=demo-helm --set cpu.cores=1 --set cpu.coreFraction=10% --set memory=1Gi
```

Репозиторий чартов: аддон берёт чарт из него, поэтому создаётся первым

```bash
d8 k apply -f 02-infra/helm/repository.yaml
d8 k wait --for=condition=Ready helmclusteraddonrepository/demo-helm --timeout=180s
```

Создание аддона: он ставит чарт с ВМ, диском и окружением

```bash
d8 k apply -k 02-infra/helm
```

Статус аддона и репозитория

```bash
d8 k get helmclusteraddon,helmclusteraddonrepository
```

Ожидание ВМ из чарта

```bash
d8 k -n demo-webinar wait --for=create vm/demo-helm --timeout=5m
d8 k -n demo-webinar wait --for=condition=AgentReady vm/demo-helm --timeout=10m
```

Чарт на GitHub Pages: индекс, который читает репозиторий чартов

```bash
curl -s https://fl64.github.io/2026-webinar-dp-virtualization/index.yaml
```

Ответ страницы

```bash
curl -sf --retry 30 --retry-delay 5 --retry-all-errors https://demo-helm.d8-virtualization.ru | grep h1
```

[Страница demo-helm в браузере](https://demo-helm.d8-virtualization.ru)

### 8.2 [Helm] Второе ядро правкой values

Два ядра вместо одного в values аддона

```bash
sed -i 's/      cores: 1/      cores: 2/' 02-infra/helm/addon.yaml
d8 k apply -k 02-infra/helm
```

Ядро добавилось. `UPTIME` в выводе показывает, перезагружалась ли ВМ

```bash
d8 k -n demo-webinar wait --for=jsonpath='{.status.resources.cpu.cores}'=2 vm/demo-helm --timeout=5m
d8 k -n demo-webinar get vm demo-helm
```

### 8.3 [Helm] Удаление окружения

Удаление аддона вместе с ВМ и репозитория чартов, в файле аддона снова одно ядро

```bash
d8 k delete -k 02-infra/helm --ignore-not-found
git checkout 02-infra/helm/addon.yaml
```

## 9. Argo CD

### 9.1 [Argo CD] Подготовка окружения

Описание ВМ в репозитории, за которым следит Argo

```bash
cat 02-infra/argocd/vm/vm.yaml
```

Приложение Argo: какой репозиторий и куда выкатывать

```bash
cat 02-infra/argocd/app.yaml
```

[Каталог 02-infra/argocd/vm на GitHub, его читает Argo](https://github.com/fl64/2026-webinar-dp-virtualization/tree/main/02-infra/argocd/vm)

Подключение Argo к репозиторию и создание приложения

```bash
d8 k apply -k 02-infra/argocd
```

Приложение и его состояние

```bash
d8 k -n argocd get applications
```

Ожидание ВМ

```bash
d8 k -n demo-webinar wait --for=create vm/demo-argocd --timeout=5m
d8 k -n demo-webinar wait --for=condition=AgentReady vm/demo-argocd --timeout=15m
d8 k -n demo-webinar get vd/demo-argocd-root vm/demo-argocd
```

Ответ страницы

```bash
curl -sf --retry 30 --retry-delay 5 --retry-all-errors https://demo-argocd.d8-virtualization.ru | grep h1
```

[Страница demo-argocd в браузере](https://demo-argocd.d8-virtualization.ru)

[Argo CD в браузере, argo.d8-virtualization.ru](https://argo.d8-virtualization.ru)

### 9.2 [Argo CD] Удаление рабочей ВМ

Удаление ВМ руками

```bash
d8 k -n demo-webinar delete vm demo-argocd
```

Argo создаёт ВМ заново на прежнем диске

```bash
d8 k -n demo-webinar wait --for=create vm/demo-argocd --timeout=5m
d8 k -n demo-webinar wait --for=condition=AgentReady vm/demo-argocd --timeout=10m
d8 k -n demo-webinar get vd/demo-argocd-root vm/demo-argocd
```

### 9.3 [Argo CD] Изменения через git

Диск 10Gi коммитом

```bash
sed -i 's/size: 4Gi/size: 10Gi/' 02-infra/argocd/vm/vd.yaml
git commit -qm 'demo-argocd-root: 10Gi' 02-infra/argocd/vm/vd.yaml && git push -q
```

Диск вырос на работающей ВМ

```bash
d8 k -n demo-webinar wait --for=jsonpath='{.status.capacity}'=10Gi vd/demo-argocd-root --timeout=5m
d8 k -n demo-webinar get vd/demo-argocd-root vm/demo-argocd
```

Второе ядро коммитом. `UPTIME` в выводе показывает, перезагружалась ли ВМ

```bash
sed -i 's/    cores: 1/    cores: 2/' 02-infra/argocd/vm/vm.yaml
git commit -m 'demo-argocd: 2 cores' 02-infra/argocd/vm/vm.yaml
git push
d8 k -n demo-webinar wait --for=jsonpath='{.status.resources.cpu.cores}'=2 vm/demo-argocd --timeout=5m
d8 k -n demo-webinar get vm demo-argocd
```

Обратно одно ядро коммитом

```bash
sed -i 's/    cores: 2/    cores: 1/' 02-infra/argocd/vm/vm.yaml
git commit -m 'demo-argocd: 1 core' 02-infra/argocd/vm/vm.yaml
git push
d8 k -n demo-webinar wait --for=jsonpath='{.status.resources.cpu.cores}'=1 vm/demo-argocd --timeout=5m
d8 k -n demo-webinar get vm demo-argocd
```

[История коммитов 02-infra/argocd/vm на GitHub](https://github.com/fl64/2026-webinar-dp-virtualization/commits/main/02-infra/argocd/vm)

### 9.4 [Argo CD] Удаление окружения

Сначала приложение: Argo удаляет ВМ и диск, команда ждёт конца. Потом AppProject: если удалить его раньше, удаление приложения зависнет на финализаторе

```bash
d8 k -n argocd delete application demo-argocd --ignore-not-found
d8 k delete -k 02-infra/argocd --ignore-not-found
```

Вернуть в git исходные диск и число ядер ВМ из шага 9.3

```bash
sed -i 's/size: 10Gi/size: 4Gi/' 02-infra/argocd/vm/vd.yaml
sed -i 's/    cores: 2/    cores: 1/' 02-infra/argocd/vm/vm.yaml
git commit -m 'demo-argocd: back to the starting point' 02-infra/argocd/vm
git push
```
