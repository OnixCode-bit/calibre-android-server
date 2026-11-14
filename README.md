# Servidor de livros num celular Android velho

Transforme um celular Android parado na gaveta num servidor de e-books para a casa toda, com o [Calibre](https://calibre-ebook.com/):

- **biblioteca no navegador** de qualquer aparelho da rede (`http://IP_DO_CELULAR:8080`);
- **catálogo OPDS** para apps de leitura como o KOReader;
- **pasta compartilhada no Windows** (`\\IP_DO_CELULAR\livros`): arraste um livro para ela e ele entra sozinho na biblioteca;
- **liga sozinho** quando o celular reinicia.

Testei no meu Moto G6 Plus, com Debian 12 (bookworm) em chroot e Calibre 6.13. Funciona em qualquer celular que rode Debian ou Ubuntu.

> 🔓 **Este guia exige root.** Sem root? Há uma versão **beta** com Termux + proot-distro no branch [`beta`](https://github.com/OnixCode-bit/calibre-android-server/tree/beta). Ainda não testei esse caminho no meu aparelho.

---

## Sumário

1. [Como funciona](#1-como-funciona)
2. [Antes de começar](#2-antes-de-começar)
3. [IP fixo para o celular](#3-ip-fixo-para-o-celular)
4. [Acesso SSH por chave](#4-acesso-ssh-por-chave)
5. [Instalar o Calibre](#5-instalar-o-calibre)
6. [Biblioteca, usuário e primeiro start](#6-biblioteca-usuário-e-primeiro-start)
7. [Iniciar no boot](#7-iniciar-no-boot)
8. [Inbox: livros entram sozinhos](#8-inbox-livros-entram-sozinhos)
9. [Pasta compartilhada no Windows (SMB)](#9-pasta-compartilhada-no-windows-smb)
10. [Ler no KOReader (OPDS)](#10-ler-no-koreader-opds)
11. [Uso no dia a dia](#11-uso-no-dia-a-dia)
12. [Problemas comuns](#12-problemas-comuns)
13. [Segurança](#13-segurança)

---

## Valores usados neste guia

Os exemplos usam os valores abaixo. **Troque pelos seus** sempre que aparecerem:

| No guia | O que é | Onde descobrir |
| --- | --- | --- |
| `192.168.1.50` | IP do celular na rede local | passo 3 |
| `usuario` | seu usuário no Debian do celular | comando `whoami` no celular |
| `leitor` | usuário de login do Calibre (você escolhe) | passo 6 |
| `celular` | apelido SSH do celular no PC | passo 4 |

---

## 1. Como funciona

```
 PC / celular / Kindle / KOReader
        │  http://192.168.1.50:8080      \\192.168.1.50\livros
        ▼                                   ▼
┌──────────────────── celular Android ────────────────────┐
│  Debian (chroot)                                        │
│                                                         │
│   calibre-server  ◄── adiciona ──  inbox-watcher.sh     │
│   porta 8080                       vigia ~/calibre/inbox│
│        │                                  ▲             │
│        ▼                                  │             │
│   ~/calibre/library               Samba (porta 445)     │
└─────────────────────────────────────────────────────────┘
```

- O **`calibre-server`** é o servidor oficial do Calibre. Ele serve a biblioteca pela web e pelo OPDS.
- O **`inbox-watcher.sh`** olha a pasta `~/calibre/inbox` a cada 10 s. Quando chega um livro, ele adiciona à biblioteca e apaga o arquivo da pasta.
- O **Samba** mostra essa pasta na rede do Windows, então "adicionar um livro" vira "arrastar um arquivo".
- O **`calibre-server.sh`** liga e desliga o servidor e o vigia juntos. O **`calibre-init`** chama esse script no boot.

### Arquivos deste repositório

| Arquivo | O que faz | Onde fica no celular |
| --- | --- | --- |
| [`calibre/calibre-server.sh`](calibre/calibre-server.sh) | `start`, `stop`, `restart`, `status` do servidor e do vigia | `~/calibre/` |
| [`calibre/inbox-watcher.sh`](calibre/inbox-watcher.sh) | Vigia a inbox e adiciona os livros | `~/calibre/` |
| [`calibre/calibre-init`](calibre/calibre-init) | Script de boot | `/etc/init.d/calibre-server` |
| [`calibre/smb-inbox.conf`](calibre/smb-inbox.conf) | Configuração da pasta compartilhada | colado no fim de `/etc/samba/smb.conf` |
| [`.vscode/tasks.json`](.vscode/tasks.json) | Atalhos do VS Code (`Ctrl+Shift+P` → *Run Task*) | — (fica no PC) |

---

## 2. Antes de começar

Você precisa de:

- **Um celular Android rodando Debian ou Ubuntu.** O jeito mais comum é um chroot com o [Linux Deploy](https://github.com/meefik/linuxdeploy), que exige root. Sem root, veja o [branch `beta`](https://github.com/OnixCode-bit/calibre-android-server/tree/beta).
- **Um PC na mesma rede Wi-Fi.** No Windows, instale o [Git for Windows](https://git-scm.com/download/win), que traz o *Git Bash* com `ssh` e `scp`.
- **Um terminal no celular**, pelo menos para os primeiros passos: o próprio app do Linux Deploy, o Termux ou um cliente SSH como o MobaXterm no PC.

> 💡 **Por que chroot?** No chroot, o Debian roda direto sobre o kernel do Android, quase sem perda de desempenho. Por outro lado, **não há systemd**: os serviços sobem pelos scripts de `/etc/init.d`, e é por isso que este guia usa um `calibre-init` em vez de um serviço do systemd.

---

## 3. IP fixo para o celular

O PC e os apps de leitura acessam o celular pelo IP. Se o IP mudar, tudo para de funcionar. Então ele precisa ser fixo.

1. No celular, veja o IP atual em *Configurações → Wi-Fi → (sua rede) → Avançado*. No exemplo, `192.168.1.50`.
2. No painel do roteador (geralmente `http://192.168.1.1` ou `http://192.168.0.1`), procure **Reserva de DHCP** / **DHCP estático** / **Address Reservation** e associe o MAC do celular a esse IP.

> ⚠️ Desative a opção **MAC aleatório** do Wi-Fi para essa rede no Android. Senão o roteador vê um aparelho diferente a cada conexão e a reserva não pega.

---

## 4. Acesso SSH por chave

Com SSH, você controla o celular pelo terminal do PC. Com uma **chave** em vez de senha, o acesso fica mais seguro e não pede senha toda hora.

**No celular**, instale e ligue o servidor SSH:

```sh
sudo apt-get update && sudo apt-get install -y openssh-server
sudo service ssh start
```

**No PC (Git Bash)**, crie uma chave, caso ainda não tenha, e copie a parte pública para o celular:

```sh
ssh-keygen -t ed25519                     # aperte Enter em tudo
cat ~/.ssh/id_ed25519.pub | ssh usuario@192.168.1.50 \
  "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Crie um apelido para não digitar o IP sempre. Acrescente ao arquivo `~/.ssh/config` do PC:

```
Host celular
    HostName 192.168.1.50
    User usuario
    IdentityFile ~/.ssh/id_ed25519
```

Teste: `ssh celular "uname -a"` deve responder **sem pedir senha**.

> 🔒 Com a chave funcionando, desligue o login por senha. Edite `/etc/ssh/sshd_config` no celular, troque para `PasswordAuthentication no` e rode `sudo service ssh restart`.

### (Opcional) `apt` sem senha

Para instalar pacotes do PC sem digitar a senha do `sudo`, libere só os comandos de pacote e serviço. **No celular:**

```sh
echo 'usuario ALL=(root) NOPASSWD: /usr/bin/apt, /usr/bin/apt-get, /usr/sbin/service' | sudo tee /etc/sudoers.d/90-usuario-apt
sudo chmod 440 /etc/sudoers.d/90-usuario-apt && sudo visudo -c
```

> ⚠️ Liberar o `apt` sem senha equivale quase a liberar o root, porque um pacote roda scripts como administrador. Só faça isso se o celular for acessível apenas pela sua rede local e por chave SSH.

---

## 5. Instalar o Calibre

O Debian já tem o Calibre nos repositórios. O `--no-install-recommends` evita centenas de MB de pacotes gráficos que um servidor não usa:

```sh
ssh celular "sudo apt-get update && sudo apt-get install -y --no-install-recommends calibre"
ssh celular "calibre-server --version"
```

---

## 6. Biblioteca, usuário e primeiro start

### 6.1 A biblioteca

Escolha **uma** das opções.

**a) Copiar a biblioteca que você já tem no Calibre do PC.** Feche o Calibre do PC antes e rode no Git Bash:

```sh
cd "$HOME/Calibre Library"   # pasta padrão; ajuste se a sua for outra
tar -cf - . | ssh celular "mkdir -p ~/calibre/library && tar -xf - -C ~/calibre/library"
```

> 💡 `tar | ssh` copia tudo num fluxo só. Com milhares de arquivos pequenos (capas, metadados), é bem mais rápido que o `scp -r`.

**b) Começar do zero.** O `calibredb` cria uma biblioteca vazia na primeira vez que é usado numa pasta:

```sh
ssh celular "mkdir -p ~/calibre/library && calibredb --with-library ~/calibre/library list"
```

### 6.2 Os scripts

Na pasta deste repositório, no PC:

```sh
scp calibre/calibre-server.sh calibre/inbox-watcher.sh calibre/calibre-init celular:calibre/
ssh celular "chmod +x ~/calibre/*.sh"
```

### 6.3 O usuário de login

O servidor vai exigir login. Crie o usuário pelo **modo interativo**: ele pergunta a senha, e assim ela não fica gravada no histórico do terminal.

```sh
ssh -t celular "calibre-server --userdb ~/calibre/users.sqlite --manage-users"
```

Escolha *Add user*, digite `leitor` e uma senha forte.

### 6.4 Primeiro start

```sh
ssh celular "~/calibre/calibre-server.sh start"
```

Abra `http://192.168.1.50:8080` no navegador do PC e entre com `leitor` e a senha. 🎉

> 💡 **O que o `calibre-server.sh` liga** (veja os comentários no script):
> - `--listen-on 0.0.0.0`: aceita conexões de toda a rede local, não só do próprio celular;
> - `--enable-auth --auth-mode basic`: exige login. O modo *Basic* é necessário porque o KOReader não entende o modo padrão (*Digest*) e recebe erro 400;
> - `--enable-local-write`: permite editar metadados e enviar livros pela web;
> - `--max-log-size 5`: o log não passa de 5 MB e não enche o armazenamento.

---

## 7. Iniciar no boot

O Linux Deploy roda os scripts de `/etc/init.d` quando sobe o Debian, do mesmo jeito que o SSH sobe. Então basta instalar o `calibre-init` ali.

1. Abra `calibre/calibre-init` e confira se `RUN_AS="usuario"` tem o **seu** usuário.
2. **No celular** (o `sudo` vai pedir senha):

   ```sh
   sudo install -m 755 ~/calibre/calibre-init /etc/init.d/calibre-server
   sudo update-rc.d calibre-server defaults
   ls /etc/rc2.d | grep calibre      # deve mostrar S01calibre-server
   ```

3. Teste: reinicie o celular (ou só o Debian, pelo Linux Deploy) e rode `ssh celular "~/calibre/calibre-server.sh status"`.

> 💡 O `calibre-init` roda como root no boot, mas chama o servidor com `su - usuario`. **Nunca rode o Calibre como root**: se ele tiver uma falha de segurança, o estrago fica limitado ao seu usuário.
>
> 📱 No Linux Deploy, lembre de ativar *Configurações → Autostart* para o próprio Debian subir junto com o Android.

---

## 8. Inbox: livros entram sozinhos

O vigia (`inbox-watcher.sh`) adiciona os livros **pelo servidor em execução**, que exige login até para conexões do próprio celular. Por isso ele precisa de um arquivo com usuário e senha.

**No celular:**

```sh
nano ~/calibre/inbox.auth
```

Escreva duas linhas, o usuário e a senha do passo 6.3, salve (`Ctrl+O`, `Enter`, `Ctrl+X`) e proteja o arquivo:

```
leitor
SUA_SENHA_AQUI
```

```sh
chmod 600 ~/calibre/inbox.auth     # só o seu usuário consegue ler
~/calibre/calibre-server.sh restart
```

A saída deve mostrar `vigia da inbox iniciado`. Agora teste:

```sh
# do PC
scp algum-livro.epub celular:calibre/inbox/
ssh celular "sleep 30; tail -3 ~/calibre/inbox.log"
```

Você deve ver `adicionado: algum-livro.epub`.

**Como o vigia se comporta:**

| Situação | O que acontece |
| --- | --- |
| Arquivo ainda sendo copiado | espera ficar **15 s sem mudar** antes de mexer |
| Livro adicionado | o arquivo é apagado da inbox |
| Livro repetido (mesmo título e autor) | o Calibre ignora; o arquivo também sai da inbox |
| Formato não suportado ou erro | o arquivo vai para `inbox/_falhou/` e o motivo fica em `~/calibre/inbox.log` |

Formatos aceitos: epub, pdf, mobi, azw, azw3, kfx, fb2, cbz, cbr, djvu, docx, rtf, txt, lit, pdb.

---

## 9. Pasta compartilhada no Windows (SMB)

O Samba faz a pasta `~/calibre/inbox` aparecer no Explorer do Windows como `\\192.168.1.50\livros`.

1. Abra `calibre/smb-inbox.conf` e troque `usuario` pelo seu usuário (3 lugares). Envie para o celular:

   ```sh
   scp calibre/smb-inbox.conf celular:calibre/
   ```

2. **No celular:**

   ```sh
   sudo apt-get install -y samba
   cat ~/calibre/smb-inbox.conf | sudo tee -a /etc/samba/smb.conf >/dev/null
   testparm -s >/dev/null          # valida o arquivo; deve dizer "Loaded services file OK."
   sudo smbpasswd -a usuario       # cria a senha que o Windows vai pedir
   sudo service smbd restart
   ```

3. **No Windows**, abra o Explorer e digite na barra de endereço `\\192.168.1.50\livros`. Entre com `usuario` e a senha do `smbpasswd`.

> ⚠️ **Armadilha comum:** `sudo sh -c 'cat ~/arquivo >> /etc/...'` **não funciona**. Dentro do `sudo`, o `~` vira `/root`. Por isso o passo acima usa `cat ... | sudo tee -a`: o `cat` roda como você e só a escrita roda como root.
>
> 💡 Se o Windows mostrar "não é possível acessar" sem pedir senha, pode estar usando uma credencial antiga. Force o login no PowerShell: `net use \\192.168.1.50\livros /user:usuario`.

---

## 10. Ler no KOReader (OPDS)

OPDS é um "catálogo de livros" que os apps de leitura entendem.

No KOReader: *Pesquisa (lupa) → Catálogo OPDS → `+`*:

| Campo | Valor |
| --- | --- |
| Nome | o que quiser, ex.: `Biblioteca de casa` |
| URL | `http://192.168.1.50:8080/opds` |
| Usuário / Senha | `leitor` e a senha do passo 6.3 |

> ⚠️ Use `http://`, **não** `https://`. O servidor não tem certificado, e com `https` o KOReader dá o erro `tlsv1 alert protocol version`.

---

## 11. Uso no dia a dia

```sh
ssh celular "~/calibre/calibre-server.sh status"     # está rodando?
ssh celular "~/calibre/calibre-server.sh restart"    # reiniciar
ssh celular "tail -f ~/calibre/server.log"           # log do servidor
ssh celular "tail -f ~/calibre/inbox.log"            # livros entrando pela inbox
```

No VS Code, as mesmas ações estão em *Terminal → Run Task* (`.vscode/tasks.json`).

**Adicionar livros:** arraste para `\\192.168.1.50\livros` ou use o botão *Adicionar livros* na página web.

**Gerenciar usuários:**

```sh
ssh -t celular "calibre-server --userdb ~/calibre/users.sqlite --manage-users"
ssh celular "~/calibre/calibre-server.sh restart"    # sempre depois de mexer nos usuários
```

> 💾 **Backup:** a biblioteca fica toda em `~/calibre/library`. Para guardar uma cópia no PC, rode:
> `ssh celular "tar -czf - -C ~/calibre library" > biblioteca-$(date +%F).tar.gz`

---

## 12. Problemas comuns

| Sintoma | O que fazer |
| --- | --- |
| Página não abre | `ssh celular "~/calibre/calibre-server.sh status"`; se estiver parado, rode `start` e leia o `~/calibre/server.log` |
| `calibre-server falhou ao iniciar` | porta 8080 ocupada? `ssh celular "ss -tlnp \| grep 8080"` |
| Login recusado | confira usuário e senha; liste os usuários com o comando do passo 11 |
| KOReader: erro 400 | o servidor está sem `--auth-mode basic` |
| KOReader: `tlsv1 alert protocol version` | troque `https://` por `http://` na URL |
| Livro não sai da inbox | o vigia está rodando (`status`)? Leia o `~/calibre/inbox.log` |
| Inbox: `A username and password is required` | falta o `~/calibre/inbox.auth` ou ele está errado (passo 8) |
| Windows não abre `\\192.168.1.50\livros` | `sudo service smbd status` no celular; `testparm -s \| grep -A3 livros` mostra a pasta? |
| Não sobe depois de reiniciar o celular | `ls /etc/rc2.d \| grep calibre`; o Autostart do Linux Deploy está ligado? |
| O IP do celular mudou | refaça a reserva de DHCP (passo 3) e desligue o MAC aleatório |

---

## 13. Segurança

Este servidor foi feito para a **rede de casa**. Antes de publicar ou adaptar:

- **Não exponha a porta 8080 nem a 445 na internet** (nada de redirecionamento de portas no roteador). O login *Basic* manda a senha sem criptografia, e o SMB exposto é alvo constante de ataques. Para acessar de fora, use uma VPN, como WireGuard ou Tailscale.
- **Senhas fora do Git.** O [`.gitignore`](.gitignore) já ignora `inbox.auth`, `users.sqlite`, `.env`, logs e PIDs. Antes de cada commit, confira com `git status`.
- **SSH só por chave**, com login por senha desligado (passo 4).
- **Calibre nunca como root** (passo 7).
- **Configure o Git com o e-mail privado do GitHub** antes do primeiro commit público:
  `git config user.email "SEU_USUARIO@users.noreply.github.com"` (veja em *GitHub → Settings → Emails*).
