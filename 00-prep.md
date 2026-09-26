# Демо: подготовка

[Оглавление](README.md#шаги)

## 0. Подготовка

Все команды выполняются из корня репы.

### 0.1 [Домен] Домен своего кластера

Манифесты и ранбуки ссылаются на домен `d8-virtualization.ru`: адреса страниц ВМ, консоли и Argo CD. Заменить его на домен своего кластера, это часть после `%s.` в шаблоне публичных доменов (первая команда)

```bash
d8 k get mc global -o jsonpath='{.spec.settings.modules.publicDomainTemplate}'   # %s.example.com
NEW=example.com
grep -rl d8-virtualization.ru --exclude-dir=.git --exclude=README.md . | xargs sed -i "s/d8-virtualization\.ru/$NEW/g"
```

### 0.2 [Форк] Адрес своего форка

Заменить адрес репы на свой форк: и на GitHub, и на GitHub Pages, откуда берётся Helm-чарт

```bash
OWNER=<владелец> REPO=<репа>
grep -rlE 'fl64/2026-webinar-dp-virtualization|fl64\.github\.io' --exclude-dir=.git --exclude=README.md . \
  | xargs sed -i -e "s|github.com/fl64/2026-webinar-dp-virtualization|github.com/$OWNER/$REPO|g" \
                 -e "s|fl64.github.io/2026-webinar-dp-virtualization|$OWNER.github.io/$REPO|g"
git commit -qam 'retarget' && git push
```

### 0.3 [Ключ] SSH-ключ демо

SSH-ключ, которому доверяют все ВМ демо

```bash
mkdir -p keys
test -f keys/demo_ed25519 || ssh-keygen -t ed25519 -N '' -C demo@webinar2026 -f keys/demo_ed25519
chmod 600 keys/demo_ed25519
```

Публичный ключ в манифесты: cloud-init kubectl, kustomize и terraform, ВМ Argo, пул ansible, values чарта

```bash
sed -i -E "s|ssh-ed25519 \S+ demo@webinar2026.*|$(cat keys/demo_ed25519.pub)|" \
  02-infra/kubectl/demo-kubectl.yaml \
  02-infra/kustomize/base/cfg/cloudinit.yaml \
  02-infra/terraform/cfg/cloudinit.yaml \
  02-infra/argocd/vm/vm.yaml \
  02-infra/helm/chart/values.yaml \
  03-lifecycle/pool.yaml
grep -rn 'demo@webinar2026' 02-infra 03-lifecycle
```

Argo и ansible читают манифесты и плейбуки из GitHub, поэтому ключ уходит в git

```bash
git commit -m 'keys: demo key' 02-infra 03-lifecycle
git push
```

### 0.4 [Helm] Чарт в gh-pages

Публикация Helm-чарта в ветку `gh-pages`: аддон читает Helm-репозиторий, а не git. После первой публикации один раз включить GitHub Pages для `gh-pages` в настройках репы

```bash
rm -rf /tmp/gh-pages
helm package 02-infra/helm/chart -d /tmp/gh-pages
helm repo index /tmp/gh-pages --url https://fl64.github.io/2026-webinar-dp-virtualization
git -C /tmp/gh-pages init -q -b gh-pages
git -C /tmp/gh-pages add -A
git -C /tmp/gh-pages commit -qm 'chart'
git fetch -q /tmp/gh-pages gh-pages
git push --force origin FETCH_HEAD:refs/heads/gh-pages
```

Чарт на GitHub Pages

```bash
curl -s https://fl64.github.io/2026-webinar-dp-virtualization/index.yaml
```

### 0.5 [Проект] Общий проект

Проект `demo-webinar` с квотой, в нём создаются все ВМ демо

```bash
cat 00-prep/project.yaml
d8 k apply -f 00-prep/project.yaml
d8 k wait --for=jsonpath='{.status.state}'=Deployed project/demo-webinar --timeout=120s
```

[Проект demo-webinar в веб-консоли](https://console.d8-virtualization.ru/projects/user-namespaces/demo-webinar)

### 0.6 [Argo CD] Argo CD с проверками здоровья

Argo CD для шага 9, с проверками здоровья ресурсов DP Virtualization: без них Argo считает приложение готовым, не дожидаясь диска и запуска ВМ. Нужен модуль `operator-argo`. Если Argo CD в кластере уже есть, блок его не трогает

```bash
cat 00-prep/argocd.yaml
d8 k -n argocd get argocd argocd 2>/dev/null || d8 k apply -f 00-prep/argocd.yaml
d8 k -n argocd wait --for=jsonpath='{.status.phase}'=Available argocd/argocd --timeout=5m
```

Пароль admin для входа на `https://argo.d8-virtualization.ru`

```bash
d8 k -n argocd get secret argocd-cluster -o jsonpath='{.data.admin\.password}' | base64 -d; echo
```

Без webhook Argo замечает push с задержкой. Чтобы он подхватывал push сразу, добавить в репу webhook на `https://argo.<домен>/api/webhook`, тип `application/json`, событие push

### 0.7 [Packer] Плагин packer

Плагин packer для DP Virtualization. В реестре Packer его нет, `packer init` сам его не скачает: плагин ставится из публичного бакета, после этого `packer init` находит его локально

Номер последнего релиза. Ниже команды для 0.1.1, для более нового релиза заменить номер в путях

```bash
curl -fsS https://storage.yandexcloud.net/deckhouse-virtualization-packer-plugin/releases/latest
```

Скачать, сверить контрольную сумму, установить

```bash
mkdir -p /tmp/packer-plugin
cd /tmp/packer-plugin
curl -fsSLO https://storage.yandexcloud.net/deckhouse-virtualization-packer-plugin/releases/0.1.1/packer-plugin-deckhouse-virtualization_v0.1.1_x5.0_linux_amd64.zip
curl -fsSLO https://storage.yandexcloud.net/deckhouse-virtualization-packer-plugin/releases/0.1.1/packer-plugin-deckhouse-virtualization_v0.1.1_SHA256SUMS
sha256sum --ignore-missing -c packer-plugin-deckhouse-virtualization_v0.1.1_SHA256SUMS
unzip -o packer-plugin-deckhouse-virtualization_v0.1.1_x5.0_linux_amd64.zip
packer plugins install --path packer-plugin-deckhouse-virtualization_v0.1.1_x5.0_linux_amd64 github.com/deckhouse/deckhouse-virtualization
cd -
packer plugins installed
```
