# Демо: уборка

[Оглавление](README.md#шаги)

## Остановить, прежде чем удалять

Остановка ВМ Windows

```bash
d8 v stop -n demo-webinar demo-win
```

## Всё остальное в кластере

Argo первым: пока приложение живо, Argo возвращает то, что удаляют следующие блоки. Приложение раньше AppProject: если удалить AppProject первым, удаление приложения зависнет на финализаторе

```bash
d8 k -n argocd delete application demo-argocd --ignore-not-found
d8 k delete -k 02-infra/argocd --ignore-not-found
```

Аддон и репозиторий чартов уровня кластера, удаление проекта их не заберёт. ВМ аддона удаляется вместе с аддоном

```bash
d8 k delete -k 02-infra/helm --ignore-not-found
```

terraform до удаления общего проекта, иначе в его стейте останутся ресурсы, которых уже нет

```bash
terraform -chdir=02-infra/terraform destroy -auto-approve
```

Общий проект: вместе с namespace уходят все оставшиеся ВМ, диски, образы проекта (включая золотой образ Windows), пул и запуски ansible

```bash
d8 k delete project demo-webinar --ignore-not-found
```

Ожидание ухода namespace: пока он удаляется, проект с тем же именем не создать

```bash
d8 k wait --for=delete ns/demo-webinar --timeout=300s
```

Проверка, что кластер чист

```bash
d8 k get ns demo-webinar --ignore-not-found
d8 k get helmclusteraddon,helmclusteraddonrepository
```

## Рабочая станция

Уборка локальных файлов

```bash
git checkout 02-infra/helm/addon.yaml
rm -f 01-image/windows/clone/cfg/authorized_keys
rm -rf 02-infra/terraform/.terraform 02-infra/terraform/terraform.tfstate*
```

Вернуть в git исходные диск и число ядер ВМ Argo из шага 9.3, когда приложение Argo уже удалено

```bash
sed -i 's/size: 10Gi/size: 4Gi/' 02-infra/argocd/vm/vd.yaml
sed -i 's/    cores: 2/    cores: 1/' 02-infra/argocd/vm/vm.yaml
git commit -m 'demo-argocd: back to the starting point' 02-infra/argocd/vm
git push
```

## Что оставляем намеренно

Установочные ISO уровня кластера переживают удаление проекта, заново их скачивать не нужно. Удалить, если больше не нужны

```bash
d8 k delete cvi demo-ubuntu-26-04-iso demo-windows-server-2022-iso demo-virtio-win-0-1-302-iso --ignore-not-found
```
