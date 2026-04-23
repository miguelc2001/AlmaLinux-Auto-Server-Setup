# Projeto de Administracao de Sistemas 2025/2026

**IPBeja - Escola Superior de Tecnologia e Gestao**
**Aluno:** Miguel Correia
**Docente:** Armando Ventura
**Distribuicao alvo:** AlmaLinux 8 (RHEL-like)

## Objetivo

Conjunto de scripts bash para automatizar a configuracao dos servicos de
administracao de sistemas pedidos nos 13 pontos do enunciado, todos no
mesmo servidor Linux virtualizado em VirtualBox.

## Estrutura

```
as-projeto/
├── install.sh        Bootstrap (instala packages, ativa servicos, firewalld, SELinux)
├── asmenu.sh         Menu principal (entry point para a discussao)
├── uninstall.sh      Limpa as configuracoes criadas pelo projeto
├── config/
│   └── defaults.conf Variaveis globais (IP, paths, portas do knock)
├── lib/
│   ├── common.sh     Cores, logging, prompts, carregamento de defaults
│   ├── validate.sh   Validacao de IPs e FQDNs
│   └── backup.sh     Snapshot automatico de ficheiros antes de editar
├── templates/        Templates de zona DNS, vhost, index.html, knockd.conf
└── modulos/
    ├── dns.sh        Pontos 1, 4, 5, 6 (parcial), 13a
    ├── web.sh        Pontos 3, 6 (parcial)
    ├── samba.sh      Ponto 2
    ├── nfs.sh        Ponto 7
    ├── backup.sh     Ponto 9 (tar + rsync incremental forever)
    ├── raid.sh       Ponto 10
    ├── fail2ban.sh   Ponto 11
    └── portknock.sh  Ponto 12
```

## Como correr

1. **Preparar a VM**: AlmaLinux 8 com rede acessivel. Para o RAID,
   adicionar previamente 3+ discos virtuais de 5GB em VirtualBox.
2. **Editar** `config/defaults.conf` com o IP real do servidor.
3. **Instalar dependencias** (correr UMA vez):
   ```bash
   sudo ./install.sh
   ```
4. **Usar o menu**:
   ```bash
   sudo ./asmenu.sh
   ```
   Cada opcao corresponde a um ponto do enunciado.

## Mapeamento pontos -> scripts

| # | Ponto | Valor | Ficheiro principal | Opcao no menu |
|---|-------|-------|--------------------|---------------|
| 1 | Criar zona forward DNS | 1 | modulos/dns.sh | DNS > 1 |
| 2 | SAMBA (CRUD partilhas + smbmount) | 1 | modulos/samba.sh | SAMBA |
| 3 | VirtualHost + pagina boas-vindas | 1 | modulos/web.sh | Web > 1 |
| 4 | Registos A / MX / CNAME | 1 | modulos/dns.sh | DNS > 2 |
| 5 | Zona reverse | 1 | modulos/dns.sh | DNS > 3 |
| 6 | Eliminar zonas + vhosts | 1 | dns.sh + web.sh | DNS > 4, Web > 2 |
| 7 | NFS (CRUD + teste mount) | 1 | modulos/nfs.sh | NFS |
| 8 | Melhorias/inovacoes | 1 | (transversal) | (ver abaixo) |
| 9 | Backups tar + rsync | 1 | modulos/backup.sh | Backups |
| 10 | RAID 5 | 1 | modulos/raid.sh | RAID 5 |
| 11 | fail2ban | 2 | modulos/fail2ban.sh | fail2ban |
| 12 | Port-knocking | 2 | modulos/portknock.sh | Port Knocking |
| 13a | DNS blacklist | 2 | modulos/dns.sh | DNS > 6-8 |

## Ponto 8 - Melhorias/Inovacoes

Implementadas e demonstraveis na discussao:

- **Validacao de input**: todos os IPs e FQDNs sao validados por regex antes
  de qualquer acao (`lib/validate.sh`).
- **Snapshot automatico antes de editar**: qualquer escrita em
  `/etc/named.conf`, `smb.conf`, `exports`, vhosts, fstab, etc. faz primeiro
  uma copia para `/var/backups/as-projeto/<timestamp>/` (`lib/backup.sh`).
- **SOA serial auto-incremento**: ao adicionar um registo a uma zona, o
  serial e atualizado no formato `YYYYMMDDNN` com contador sequencial.
- **Validacao sintatica antes de aplicar**: DNS usa `named-checkconf` +
  `named-checkzone`; Apache usa `httpd -t`; Samba usa `testparm`. Se a
  validacao falhar o reload nao e feito.
- **SELinux aware**: contextos aplicados para `httpd_sys_content_t`,
  `samba_share_t`, `public_content_rw_t` conforme necessario, e booleans
  relevantes ligados.
- **Logging auditavel**: todas as accoes ficam em `/var/log/as-projeto.log`
  com timestamp e nivel - mostravel na opcao 9 do menu.
- **Idempotencia**: todos os scripts verificam existencia antes de criar e
  avisam em vez de rebentar.
- **`uninstall.sh`**: permite limpar configs criadas e voltar a testar a
  partir do zero, util na discussao.

## Testes sugeridos

### DNS (na maquina cliente ou no proprio servidor)
```bash
dig @192.168.1.100 exemplo.pt
dig @192.168.1.100 -x 192.168.1.100     # reverse
dig @192.168.1.100 mail.exemplo.pt MX
dig @192.168.1.100 facebook.com         # blacklist -> 127.0.0.1
```

### Web
```bash
curl -H 'Host: exemplo.pt' http://192.168.1.100/
```

### SAMBA (cliente Windows: explorer \\192.168.1.100)
```bash
smbclient -L //192.168.1.100 -U utilizador
```

### NFS (cliente Linux)
```bash
sudo mount -t nfs 192.168.1.100:/srv/nfs/share /mnt/nfs
```

### fail2ban
```bash
# Desde outro IP, falhar SSH 5+ vezes -> deve ser banido
ssh utilizador@192.168.1.100   # senha errada repetidas vezes
# No servidor:
fail2ban-client status sshd
```

### Port knocking (no cliente)
```bash
# SSH esta fechado; tentar primeiro falha:
ssh utilizador@192.168.1.100   # timeout
# Usar o cliente:
sudo ./modulos/portknock.sh    # opcao 3
```

### RAID
```bash
cat /proc/mdstat
mdadm --detail /dev/md0
```

### Backups
```bash
# Backup tar - ver em /backup/tar
# Backup rsync incremental - ver em /backup/rsync
#   - primeiro snapshot: ocupa espaco total
#   - seguintes: so diff (hardlinks para o resto)
du -sh /backup/rsync/*
```

## Notas importantes

- `smbmount` esta depreciado desde Samba 4; foi substituido por
  `mount -t cifs` (package `cifs-utils`). O modulo continua a falar em
  "smbmount" para alinhar com o enunciado mas usa a ferramenta moderna.
- O servidor tem **SELinux enforcing** por default - todos os scripts
  aplicam os contextos e booleans necessarios.
- O firewalld esta ativo; os scripts abrem/fecham servicos conforme
  necessario (nomeadamente Ponto 12 fecha SSH).
