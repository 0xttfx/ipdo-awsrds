# ipdo-awsrds

## Função
 Scrip bash para descoberta dos IPs WAN dos DOcean Droplets e inserção em security groups EC2 das instâncias AWS RDS.

## Atualizações
 
- v0.4
  - Como inteválo mínimo de execução na CRON são de 60 segundos! E eu precisava executar por mais vezes por minuto
    acabei contendo o scrip dentro de um laço wile que o executa por 10 vezes com intervalo de 2 segundos 
- v0.5
  - removido laço de x execuções a cada 60s
  - restruturado algumas conditional statement da inserção e remoção de IPs
  - O diff, antes realizado globalmente, agora é realizado para cada Security Group
- v0.6
  - Implementado o builtin *set* com as *options* *errtrace, errexit, nounset e pipefail* para deixar o script mais criterioso quanto a erros Principalmente os de APIs 5xx sem a necessidade de fazer testes em funções, condições etc.
  - Implementado trap para melhor localização do momento e local do erro.
- v0.7
  - Implementado arquivo PID.
  - Modificado método de criação de array's específicos para uso mapfile
  - Melhorias no filtro diff dos arquivos de IPs
  - Melhorias nos filtros para criação de array IPs
  - Modificado no laço aninhado de inserção e remoção de IP para melhora do parser  
- v0.8
  - Implementado tratativa para cod error diff
  - Implementado arquivo de diff temporário para cada sec. group verificado
  - Implementado tratativa para cod error na criação de array usando arquivo diff temporário
  - Implementado remoção de arquivos temporários em cada laço
- v1.0
  - Agora sim! **ipdo-awsrds** agora é GA - Disponibilidade Geral!
  - Versão estável para uso em ambiente produção. 

## Dependências

- AWS CLI
  - [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
  - [EC2](https://docs.aws.amazon.com/cli/latest/reference/ec2/)
    - [API authorize-security-group-ingress](https://docs.aws.amazon.com/cli/latest/reference/ec2/authorize-security-group-ingress.html)
    - [API describe-security-groups](https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-security-groups.html)
  - [RDS](https://docs.aws.amazon.com/cli/latest/reference/rds/)
    - [API describe-db-instances](https://docs.aws.amazon.com/cli/latest/reference/rds/describe-db-instances.html)
- DigitalOcean CLI
  - [DO CLI](https://docs.digitalocean.com/reference/doctl/how-to/install/)
    - [API compute](https://docs.digitalocean.com/reference/doctl/reference/compute/)

## Executando

Crie diretório `tools` e `tool/log` em  `/usr/local` 
```bash
mkdir -p /usr/local/tools/log && cd /usr/local/tools/ && \
git clone git@github.com:0xttfx/ipdo-awsrds.git
```

Agora criamos o arquivo *path-tools.sh* em */etc/profile.d/* para configurar o PATH para diretório *tools* 
```bash
sudo > /etc/profile.d/path-tools.sh
```

Em seguida adicione o conteúdo:
```bash
# configurando PATH para incluir diretório tools caso exista.
if [ -d "/usr/local/tools/ipdo-awsrds" ] ; then
    PATH="$PATH:/usr/local/tools/ipdo-awsrds"
fi
Eof
```

Para execução do script é necessário declarar o *user profile aws cli* usando a opção **-u**
```bash
ipdo-awsrds -u <nome>
```

## Automação 
 Para automação da execução, adicione a seguinte linha na crontab do usuário(*crontab -e*) não privilégiado.
 Devido ao update, adição e remoção dos nós dos clusters, o script será executado a cada 1 mintuo!
 - altere conforme sua necessidade.
```bash
* * * * *    /usr/bin/bash -x /usr/local/tools/ipdo-awsrds -u nome >> /usr/local/tools/log/ipdo-awsrds-$(date --date="today" +\%d\%m\%Y_\%H\%M\%S).log 2>&1
0 0 * * *    /usr/bin/find /usr/local/tools/log/ -type f -mtime +5 -name 'exec-*.log' -exec rm {} +
```
