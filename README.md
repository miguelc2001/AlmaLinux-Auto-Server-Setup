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