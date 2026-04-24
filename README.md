# Projeto de Administração de Sistemas 2025/2026

**IPBeja — Escola Superior de Tecnologia e Gestão**  
**Aluno:** Miguel Correia  
**Distribuição alvo:** AlmaLinux 8 (RHEL-like)

---

## Objetivo

Conjunto de scripts Bash para automatizar a configuração dos serviços de administração de sistemas pedidos nos 13 pontos do enunciado, todos no mesmo servidor Linux virtualizado em VirtualBox.

---

## Estrutura do Projeto

```
AlmaLinux-Auto-Server-Setup/
├── install.sh            Bootstrap: instala packages, activa serviços, configura firewalld e SELinux
├── asmenu.sh             Menu principal (ponto de entrada para utilização e discussão)
├── uninstall.sh          Remove as configurações criadas pelo projecto
├── config/
│   └── defaults.conf     Variáveis globais (IP do servidor, paths, portas do knock)
├── lib/
│   ├── common.sh         Cores, logging, prompts e carregamento de defaults
│   ├── validate.sh       Validação de IPs e FQDNs
│   └── backup.sh         Snapshot automático de ficheiros antes de editar
├── templates/            Templates de zona DNS, VirtualHost, página HTML e knockd.conf
└── modulos/
    ├── dns.sh            Pontos 1, 4, 5, 6 (parcial) e 13
    ├── web.sh            Pontos 3 e 6 (parcial)
    ├── samba.sh          Ponto 2
    ├── nfs.sh            Ponto 7
    ├── backup.sh         Ponto 9 (tar + rsync incremental forever)
    ├── raid.sh           Ponto 10
    ├── fail2ban.sh       Ponto 11
    └── portknock.sh      Ponto 12
```

---

## Como Utilizar

### 1. Preparar a máquina virtual

- Instalar AlmaLinux 8 com rede acessível.
- Para o RAID (Ponto 10), adicionar previamente 3 ou mais discos virtuais de 5 GB no VirtualBox.

### 2. Clonar o repositório

```bash
git clone https://github.com/miguelc2001/AlmaLinux-Auto-Server-Setup.git
cd AlmaLinux-Auto-Server-Setup
```

### 3. Editar as configurações

Editar o ficheiro `config/defaults.conf` com o IP real do servidor e restantes variáveis.

### 4. Instalar dependências

Executar **uma única vez** após clonar:

```bash
sudo ./install.sh
```

### 5. Utilizar o menu principal

```bash
sudo ./asmenu.sh
```

Cada opção do menu corresponde a um ou mais pontos do enunciado.

---

## Mapeamento Pontos → Scripts

| Ponto | Descrição | Valor | Script principal | Opção no menu |
|-------|-----------|-------|-----------------|---------------|
| 1 | Criar zona forward DNS (master) | 1 | modulos/dns.sh | DNS > 1 |
| 2 | SAMBA — CRUD de partilhas + montagem Windows | 1 | modulos/samba.sh | SAMBA |
| 3 | VirtualHost Apache + página de boas-vindas | 1 | modulos/web.sh | Web > 1 |
| 4 | Registos A, MX e CNAME | 1 | modulos/dns.sh | DNS > 2 |
| 5 | Zona reverse | 1 | modulos/dns.sh | DNS > 3 |
| 6 | Eliminar zonas forward, reverse e VirtualHosts | 1 | dns.sh + web.sh | DNS > 4, Web > 2 |
| 7 | NFS — CRUD de exports + teste de montagem | 1 | modulos/nfs.sh | NFS |
| 8 | Melhorias e inovações (ver secção abaixo) | 1 | (transversal) | — |
| 9 | Backups com tar + rsync incremental forever | 1 | modulos/backup.sh | Backups |
| 10 | RAID nível 5 | 1 | modulos/raid.sh | RAID 5 |
| 11 | fail2ban — protecção SSH contra brute force | 2 | modulos/fail2ban.sh | fail2ban |
| 12 | Port knocking — cliente e servidor | 2 | modulos/portknock.sh | Port Knocking |
| 13a | DNS blacklist — inserção e remoção de domínios | 2 | modulos/dns.sh | DNS > 6-8 |

---

## Ponto 8 — Melhorias e Inovações

Funcionalidades adicionais implementadas e demonstráveis na discussão:

- **Validação de input** — todos os IPs e FQDNs são validados por expressão regular antes de qualquer acção (`lib/validate.sh`).
- **Snapshot automático antes de editar** — qualquer escrita em ficheiros de configuração (`/etc/named.conf`, `smb.conf`, `/etc/exports`, VirtualHosts, etc.) cria primeiro uma cópia com timestamp em `/var/backups/as-projeto/` (`lib/backup.sh`).
- **Serial SOA com auto-incremento** — ao adicionar um registo a uma zona, o serial é actualizado automaticamente no formato `YYYYMMDDNN`.
- **Validação sintáctica antes de aplicar** — o DNS usa `named-checkconf` e `named-checkzone`; o Apache usa `httpd -t`; o Samba usa `testparm`. Se a validação falhar, o reload não é efectuado.
- **SELinux aware** — os contextos SELinux são aplicados correctamente para cada serviço (`httpd_sys_content_t`, `samba_share_t`, `public_content_rw_t`) e os booleans relevantes são activados.
- **Logging auditável** — todas as acções ficam registadas em `/var/log/as-projeto.log` com timestamp e nível de severidade.
- **Idempotência** — todos os scripts verificam a existência de configurações antes de criar e avisam em vez de falhar.
- **`uninstall.sh`** — permite limpar todas as configurações criadas e voltar a testar a partir do zero, útil na discussão.

---

## Testes Rápidos

### DNS (na máquina cliente ou no próprio servidor)
```bash
dig @192.168.1.103 exemplo.pt
dig @192.168.1.103 -x 192.168.1.103     # reverse
dig @192.168.1.103 mail.exemplo.pt MX
dig @192.168.1.103 facebook.com         # blacklist → 127.0.0.1
```

### Web
```bash
curl -H 'Host: exemplo.pt' http://192.168.1.103/
```

### SAMBA
```bash
smbclient -L //192.168.1.103 -U utilizador
```

### NFS (máquina cliente Linux)
```bash
sudo mount -t nfs 192.168.1.103:/srv/nfs/share /mnt/nfs
```

### fail2ban
```bash
# Falhar o login SSH 5 ou mais vezes → o IP deve ser bloqueado
ssh utilizador@192.168.1.103
# No servidor, verificar:
fail2ban-client status sshd
```

### Port Knocking (máquina cliente)
```bash
# O SSH está fechado por omissão; ligar antes do knock falha com timeout.
# Usar o menu: sudo ./asmenu.sh → Port Knocking → Cliente
```

### RAID 5
```bash
cat /proc/mdstat
mdadm --detail /dev/md0
```

### Backups
```bash
# Verificar backups tar em /backup/tar
# Verificar backups rsync incrementais em /backup/rsync
du -sh /backup/rsync/*
```

---

## Notas

- O `smbmount` está obsoleto desde o Samba 4 e foi substituído por `mount -t cifs` (package `cifs-utils`). Os scripts usam a ferramenta moderna mas mantêm a terminologia do enunciado.
- O servidor corre com **SELinux em modo enforcing** por omissão — todos os scripts aplicam os contextos e booleans necessários.
- O **firewalld** está activo; os scripts abrem e fecham serviços conforme necessário (o Ponto 12 fecha o SSH até ser feito o knock correcto).