# IPDropSecGroupAWSEC2RDS

## Função
 Scrip bash para descoberta de IPs de Droplets Nodes dos clusters Kubernetes e inserção destes IPs, no security group EC2 das instâncias AWS RDS.

## Atualizações
 
- 0.4v
  - Como inteválo mínimo de execução na CRON são de 60 segundos! E eu precisava executar por mais vezes por minuto
    acabei contendo o scrip dentro de um laço wile que o executa por 10 vezes com intervalo de 2 segundos 
- 0.5v
  - removido laço de execução a cada 60s
  - restruturado algumas conditional statement da inserção e remoção de IPs
  - O diff, antes realizado globalmente, agora é realizado para cada Security Group

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
```
mkdir -p /usr/local/tools/log && cd /usr/local/tools/ && \
git clone git@github.com:0xttfx/ip-do_aws-rds.git && cd ip-*
```

 Não há argumentos, bastando executar o .sh
```
./script-0.5.sh
```

## Automação 


 Para automação da execução, adicione a seguinte linha na cron
 Devido ao update dos nós dos clusters, que alteram os seus IPs, o script será executado a cada 1 mintuo!
 - altere conforme sua necessidade.

```
* * * * * 	user	/usr/bin/bash -x /usr/local/tools/ip-do_aws-rds/script-0.5.sh >> /usr/local/tools/log/exec-script-0.5-$(date --date="today" +\%d\%m\%Y_\%H\%M\%S).log 2>&1
0 0 * * *   user	find /usr/local/tools/log/ -type f -mtime +3 -name 'exec-*.log' -exec rm {} +
```
