# Stock Kernel Identity — fork do GKI_KernelSU_SUSFS (base r22)

Este fork transforma o kernel compilado em **um kernel que se identifica exatamente
como o kernel stock do aparelho** — sem spoof em runtime (SUSFS/uname), tudo
resolvido em tempo de build. O `/proc/version` passa a ser idêntico ao original,
coisa que nenhum spoof de `uname` consegue fazer (o `/proc/version` vem do
`linux_banner`, uma constante compilada dentro da imagem).

Aparelho de referência: **Moto G54 5G (cancunf), Android 13, build T3TDS33.16-78-2-2**

```
Linux version 5.10.168-android12-9-00003-g828a3b1f7462-ab10564101 (build-user@build-host) (Android (7284624, based on r416183b) clang version 12.0.5 (...), LLD 12.0.5 (...)) #1 SMP PREEMPT Wed Jul 26 12:50:50 UTC 2023
```

---

## 1. O que foi alterado neste fork

| # | Arquivo | Alteração |
|---|---------|-----------|
| 1 | `.github/actions/stock-identity/action.yml` **(novo)** | Reescreve `VERSION/PATCHLEVEL/SUBLEVEL` do Makefile + `scripts/setlocalversion` para o release stock exato, e fixa `KBUILD_BUILD_TIMESTAMP` (+ `SOURCE_DATE_EPOCH`) na data stock. Remove `.version` para o UTS_VERSION sair `#1`. |
| 2 | `config/stock_defconfig` **(novo)** | Config **stock real extraído do boot.img oficial da Motorola** (6727 linhas, sem nenhuma linha KSU/SUSFS/BORE). O action `stock-config` do r22 já dá prioridade a esse arquivo → `/proc/config.gz` passa a sair **byte-idêntico ao stock**. |
| 3 | `.github/workflows/build.yml` | Wiring do novo action (roda depois do branding e sobrescreve) + step **Verify Stock Kernel Identity** que lê o banner do `Image` compilado e **falha o build** se a string não bater. |
| 4 | `.github/workflows/main.yml` / `prepare.yml` | Inputs novos `stock_identity`, `stock_uts`, `stock_build_timestamp` (default = kernel do Moto G54 A13) propagados para as 7 pernas da matriz. |
| 5 | `main.yml` (defaults) | `brand_name` default **""** (não sai mais `-Wild` no nome do kernel) e os patch-sets que deixam rastro visível desligados por padrão: `use_nomount`, `use_bbg`, `use_net`, `use_ds`, `use_ntsync`, `use_ptrace`, `use_bpf`. |
| 6 | `tools/verify-stock-string.sh` **(novo)** | Valida localmente/CI: extrai o banner do Image (ou Image.gz/lz4/zst) e compara com a string esperada. |

---

## 2. O que exatamente muda no aparelho

| Vetor (visível para qualquer app) | Antes (build Wild) | Depois | Como |
|---|---|---|---|
| `/proc/version`, `uname(2)`, `linux_banner` | `5.10.269-android12-Wild` | `5.10.168-android12-9-00003-g828a3b1f7462-ab10564101` | `stock-identity` (build-time) |
| `uname -v` / UTS_VERSION | `#1 SMP PREEMPT Mon Oct 5 04:20:00 UTC 2026` | `#1 SMP PREEMPT Wed Jul 26 12:50:50 UTC 2023` | `KBUILD_BUILD_TIMESTAMP` + `.version` zerado |
| `/proc/config.gz` (lido por **qualquer app**, 444) | `CONFIG_KSU=y`, `CONFIG_KSU_SUSFS*`, `CONFIG_BBG`, `CONFIG_CIFS`, `CONFIG_NTSYNC`, `CONFIG_DEBUG_INFO_BTF`, `CONFIG_LOCALVERSION_AUTO` etc. | config stock Motorola **idêntico** | `config/stock_defconfig` |
| `/proc/filesystems` | continha `cifs`, `smb3`, `devtmpfs` | igual ao stock | `use_net=false`, `use_ds=false` |
| `/sys/kernel/btf/vmlinux` | existia (BTF ligado) | **não existe** (stock não tem BTF) | `use_bpf=false` |
| LSM extra `baseband_guard` | presente no kernel | removido | `use_bbg=false` |
| `/dev/ntsync` | existia | removido | `use_ntsync=false` |
| `/proc/pid/mem` (patch ptrace) | comportamento alterado | stock | `use_ptrace=false` |
| Nome do kernel/artefato | `…-Wild` | sem brand | `brand_name=""` |
| Compilador no banner | `clang 12.0.5 r416183b` | **igual** (já era igual) | — |
| `build-user@build-host` no banner | igual | **igual** (já era igual) | — |

### O que NÃO dá para igualar (e por quê)

| Vetor | Situação |
|---|---|
| `build-id` (`/sys/kernel/notes`, 20 bytes) | hash do binário compilado — só seria igual recompilando bit-a-bit. Nenhum app comum compara. |
| Hash/tamanho da imagem de boot | diferente do stock, **mas** o seu LK já reporta `vbmeta.digest=7692f8f2…`, `flash.locked=1`, `verifiedbootstate=green` → coberto na atestação. |
| BTF/`/sys/kernel/btf` | ausente agora (igual ao stock). |
| Símbolos `ksu_*`/`susfs_*` no `/proc/kallsyms` | já ocultos por `CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y` para processos não-su. |

---

## 3. Como usar (GitHub Actions)

1. Faça fork/upload deste repositório no seu GitHub.
2. **Settings → Actions → General**: habilite *Read and write permissions* (o workflow publica release/artefatos).
3. Aba **Actions → Build Kernels → Run workflow** com:

```
release_type .......... CI
kernel_build_version .. 5.10.x-android12
os_patch_level ........ lts
page_size ............. 4k
root_flavor ........... BakaSU          (uapi 5 — o manager que você usa)
use_susfs ............. true
stock_identity ........ true
stock_uts ............. 5.10.168-android12-9-00003-g828a3b1f7462-ab10564101
stock_build_timestamp . Wed Jul 26 12:50:50 UTC 2023
brand_name ............ (vazio)
allow_version_mismatch  false
```

> Use **`5.10.x-android12`** e **não** `All`: o `config/stock_defconfig` é do G54 A13
> (5.10.168). Se rodar `All`, os outros kernels sairiam com a config/string do G54.

4. O step **`Verify Stock Kernel Identity`** aparece no log. Se a string não bater,
   o build falha (não gera artefato errado).

### Presets por aparelho (já extraídos dos boot.img oficiais)

| Aparelho | `stock_uts` | `stock_build_timestamp` | config |
|---|---|---|---|
| Moto G54 5G **A13** (T3TDS33.16-78-2-2, 5.10.168) | `5.10.168-android12-9-00003-g828a3b1f7462-ab10564101` | `Wed Jul 26 12:50:50 UTC 2023` | `config/stock_defconfig` |
| Moto G54 5G **A15** (V1TDS35H.83-20-5-8-2-1-1, 5.10.240) | `5.10.240-android12-9-00006-g25161a557b20-ab14744618` | `Tue Jan 20 09:40:29 UTC 2026` | `config/stock_defconfig.a15-moto-g54` (renomeie para `config/stock_defconfig`) |

Outro aparelho? Pegue a string do próprio stock:

```bash
adb shell cat /proc/version
# ou do boot.img stock:
unpack_bootimg --boot_img boot_stock.img --out out && gzip -dc out/kernel | strings | grep -m1 '^Linux version'
```

---

## 4. Instalação no aparelho (depois do build)

O kernel sai como boot.img AnyKernel3. No G54 (bootloader Motorola):

```bash
fastboot flash boot_a <boot.img>     # 'fastboot boot' não é suportado
# ou pelo AnyKernel3 no gerenciador (BakaSU/KSU: instalar módulo/zip do kernel)
```

Conferir depois de reiniciar:

```bash
adb shell cat /proc/version
adb shell uname -r
adb shell su -c 'zcat /proc/config.gz | grep -ciE "KSU|SUSFS|BBG|CIFS|NTSYNC"'   # deve ser 0
```

E **desligue o spoof do BRENE** (`config_spoof_uname=0`): com o build já stock,
o spoof de uname vira redundante — e era justamente ele que fazia o BTG "perder
o device" quando mudava o valor exposto.

---

## 5. Cuidados

- **Play Integrity**: este fork resolve o vetor *string de kernel + config.gz*.
  `MEETS_DEVICE` ainda depende de `ro.boot.flash.locked=1` + `verifiedbootstate=green`
  + hash certificado (o seu LK já entrega isso) e `MEETS_STRONG` exige keybox
  (TrickyStore + keybox válido) — nada disso é afetado por este fork.
- **Zygisk**: em testes anteriores o módulo `zygisksu` fez o BTG crashar. Este
  fork não instala módulos; mantenha o aparelho sem Zygisk.
- **`allow_version_mismatch`**: deixe `false`. Com a UTS stock o vermagic também
  fica stock e os módulos do vendor carregam normalmente.
- **Cache**: se usar `use_cache=true`, o action apaga `.version` para o UTS
  continuar `#1`.
